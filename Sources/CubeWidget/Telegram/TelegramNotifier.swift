import CoreGraphics
import Foundation
import SessionFile

/// Watches every session (not only the widget's front card) and sends a Telegram message
/// when one starts waiting for you, completes a task, or finishes its answer. A message
/// is the project's name in bold with what happened, and below, the task's short title
/// (or the beginning of the answer):
///
///     **CubeWidget** - Tâche finie ✅
///     Ajouter la cloche
///
/// Only when you are away from the Mac: no mouse or keyboard for `awayDelay`. An event
/// that happens while you just left is kept, and sent once you have been away long
/// enough, if it is still true then (Claude still waiting…). Touching the Mac after the
/// event means you saw it: nothing is sent.
@MainActor
final class TelegramNotifier {
    private enum Event: String {
        case waiting, taskCompleted, answered
    }

    /// An event not sent yet.
    private struct Pending {
        let sessionID: String
        let event: Event
        let folder: URL
        let text: String
        /// "Réponse terminée": the first line and the whole answer, to send a summary instead.
        var summary: (firstLine: String, answer: String)? = nil
        let at: Date
        /// The session must still have this status when the message goes (nil: no condition).
        let status: SessionFile.Status?
        /// "Attend ta réponse" for a permission or a question: when it was asked (for its
        /// buttons: Oui / Non, or one per choice).
        var requestAt: Date? = nil
    }

    private let settings = TelegramSettings.shared
    /// The last version of each session's file, to see what changed.
    private var known: [String: SessionFile] = [:]
    private var hasLoaded = false
    private var pending: [Pending] = []
    /// Last message per session and event ("<id>/<event>"), against spam.
    private var lastSent: [String: Date] = [:]
    /// The last permission or question sent per session (when it was asked).
    private var lastRequestSent: [String: Date] = [:]
    private var timer: Timer?
    /// Called with each message sent and its session, so that your replies to it can
    /// reach that session ("Commandes depuis Telegram").
    var onSent: ((_ messageID: Int, _ sessionID: String) -> Void)?
    /// The buttons for a session asking for a permission or asking a question (nil: no buttons).
    var buttons: ((SessionFile) -> [[TelegramClient.Button]]?)?

    /// Called with all the session files each time they are read.
    func process(_ files: [SessionFile]) {
        let byID = Dictionary(files.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
        // At launch, what is already there sends nothing: only changes count.
        if hasLoaded {
            for file in files {
                guard let old = known[file.sessionID] else { continue }
                let name = URL(fileURLWithPath: file.cwd).lastPathComponent
                if file.status == .waiting, old.status != .waiting {
                    // The task Claude was on: the one in progress, or else the last one created.
                    let task = file.tasks.last { $0.status == "in_progress" } ?? file.tasks.last
                    var text = Self.text(name, "Attend ta réponse ⏳", task?.subject)
                    if let permission = file.pendingPermission {
                        text += "\n" + TelegramRemote.permissionText(permission)
                    } else if let question = file.pendingQuestion {
                        text += "\n" + TelegramRemote.questionText(question, index: 0)
                    }
                    add(.waiting, file, text, at: file.statusChangedAt, status: .waiting,
                        requestAt: Self.requestDate(of: file))
                }
                if let task = file.lastCompletedTask, task.at != old.lastCompletedTask?.at {
                    add(.taskCompleted, file, Self.text(name, "Tâche finie ✅", task.subject), at: task.at, status: nil)
                }
                // Claude finished its answer: sent only if it is still your turn by then.
                if let answer = file.lastAnswer, answer.at != old.lastAnswer?.at {
                    let event = "Réponse terminée 💬"
                    add(.answered, file,
                        Self.text(name, event, Self.firstWords(of: answer.excerpt),
                                  limit: Constants.Telegram.answerExcerptMaxLength),
                        at: answer.at, status: .done,
                        summary: Self.needsSummary(answer.excerpt) ? (Self.text(name, event, nil), answer.excerpt) : nil)
                }
            }
        }
        hasLoaded = true
        known = byID
        // Forget what is no longer true (session closed, you answered…).
        pending.removeAll { event in
            guard let file = byID[event.sessionID] else { return true }
            return event.status.map { file.status != $0 } ?? false
        }
        flush()
    }

    /// "<b>CubeWidget</b> - Tâche finie ✅", then the task's title (kept short) on the
    /// next line. Without a task, only the first line. Sent as HTML (for the bold).
    static func text(_ project: String, _ event: String, _ task: String?,
                             limit: Int = Constants.Telegram.taskTitleMaxLength) -> String {
        let firstLine = "<b>\(TelegramClient.escapeHTML(project))</b> - \(event)"
        let task = task?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !task.isEmpty else { return firstLine }
        let short = task.count > limit ? task.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…" : task
        return firstLine + "\n" + TelegramClient.escapeHTML(short)
    }

    /// The first sentence of an answer: its first line with words that is not a title
    /// (a title only if there is nothing else), without its Markdown marks (titles,
    /// bullets, bold, code).
    private static func firstWords(of answer: String) -> String {
        let lines = answer.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
        let line = lines.first { !$0.hasPrefix("#") } ?? lines.first ?? ""
        let unmarked = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .drop { "#->*•+ ".contains($0) }
        return String(unmarked)
    }

    /// An answer of one short sentence is sent as is: nothing to summarize.
    private static func needsSummary(_ answer: String) -> Bool {
        let lines = answer.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.count > 1 || answer.count > Constants.Telegram.answerExcerptMaxLength
    }

    private func add(_ event: Event, _ file: SessionFile, _ text: String, at: Date, status: SessionFile.Status?,
                     summary: (firstLine: String, answer: String)? = nil, requestAt: Date? = nil) {
        pending.removeAll { $0.sessionID == file.sessionID && $0.event == event }
        pending.append(Pending(sessionID: file.sessionID, event: event, folder: URL(fileURLWithPath: file.cwd),
                               text: text, summary: summary, at: at, status: status, requestAt: requestAt))
    }

    /// When the permission or the question the session waits on was asked.
    private static func requestDate(of file: SessionFile) -> Date? {
        file.pendingPermission?.at ?? file.pendingQuestion?.at
    }

    /// Sends what can be sent now, drops what is no longer wanted, keeps the rest.
    private func flush() {
        let idle = Self.secondsSinceLastInput()
        let lastInput = Date().addingTimeInterval(-idle)
        pending.removeAll { event in
            // Not wanted: general switch off, project's bell off, or Telegram not set up.
            guard settings.isEnabled, settings.isConfigured, settings.isOn(for: event.folder) else { return true }
            if settings.alwaysSend || idle >= Constants.Telegram.awayDelay {
                send(event)
                return true
            }
            // You used the Mac after the event: you saw it.
            return lastInput > event.at.addingTimeInterval(Constants.Telegram.presenceGrace)
        }
        if pending.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            // Look again regularly until you have been away long enough.
            let timer = Timer(timeInterval: Constants.Telegram.checkInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func send(_ event: Pending) {
        let key = "\(event.sessionID)/\(event.event.rawValue)"
        // A new permission or question is a real request: always sent, even soon after
        // the previous message (but each request only once).
        let isNewRequest = event.requestAt.map { $0 != lastRequestSent[event.sessionID] } ?? false
        if !isNewRequest, let last = lastSent[key], Date().timeIntervalSince(last) < Constants.Telegram.minimumInterval { return }
        lastSent[key] = Date()
        if let requestAt = event.requestAt { lastRequestSent[event.sessionID] = requestAt }
        var text = event.text
        let summary = event.summary
        let sessionID = event.sessionID
        // Oui / Non, or the choices, if Claude still asks that same thing now. Without
        // buttons, a question's choices are written out.
        var buttons: [[TelegramClient.Button]]?
        if let askedAt = event.requestAt, let file = known[sessionID], Self.requestDate(of: file) == askedAt {
            buttons = self.buttons?(file)
            if buttons == nil, let question = file.pendingQuestion, let first = question.items.first {
                text += "\n" + TelegramRemote.choicesText(first)
            }
        }
        Task {
            // "Réponse terminée": the answer in a few bullet points (else its first sentence).
            var message = text
            if let summary, let bullets = await AnswerSummary.bullets(of: summary.answer) {
                message = summary.firstLine + "\n" + TelegramClient.escapeHTML(bullets)
            }
            // A failure is shown in the menu.
            if let messageID = await settings.send(message, isHTML: true, buttons: buttons) {
                onSent?(messageID, sessionID)
            }
        }
    }

    /// Time since the last mouse or keyboard event, from macOS (no permission needed).
    private static func secondsSinceLastInput() -> TimeInterval {
        if let anyInput = CGEventType(rawValue: ~0) {
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown, .flagsChanged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }
}
