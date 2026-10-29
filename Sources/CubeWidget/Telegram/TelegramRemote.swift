import Combine
import Foundation
import SessionFile

/// "Commandes depuis Telegram": a reply to one of the bot's messages is typed into the
/// Claude session that message was about, as if you typed it in the Cube Hub.
///
/// Nothing listens on the Mac: the app asks Telegram for new messages ("long polling"),
/// only while the switch is on and Telegram is set up. What is accepted:
/// - only your private conversation with the bot, and messages written after the switch
///   was turned on;
/// - only while unlocked: `/unlock` with the six-digit code of your code app, for
///   `unlockDuration` (`RemoteLock`); `/lock` locks again;
/// - only replies to a message the bot sent during this run of the app;
/// - only sessions running in the Cube Hub, with Claude in the foreground of their
///   terminal (not the shell, not another program), and not waiting on a question or a
///   permission;
/// - no shell command (a leading "!"), no Claude command ("/"), no memory note ("#"),
///   no control characters;
/// - everything is written in a journal, and what matters shows as a notification on
///   the Mac (`RemoteLog`);
/// - each message once (even after a relaunch), only if written less than
///   `remoteMaxAge` ago, `remoteMaxPerMinute` at most, not the same text twice in a row;
///   too many refusals lock again;
/// - a permission Claude asks for is answered with the Oui / Non buttons of its message
///   ("1" or Échap pressed in its terminal), never with text;
/// - a question Claude asks is answered with one button per choice (its number pressed in
///   the terminal), one question after the other, never with text.
@MainActor
final class TelegramRemote {
    private typealias T = Constants.Telegram

    /// Why a message was not typed, in words sent back to you.
    private struct Refusal: Error {
        let reason: String
        /// The request is over: its buttons are removed.
        var isFinal = false
    }

    private let settings = TelegramSettings.shared
    private let lock = RemoteLock.shared
    private let hub: HubModel
    /// The last version of each session's file.
    private var files: [String: SessionFile] = [:]
    /// Which session each sent message was about (message number → session ID), newest last.
    private var sessionOfMessage: [Int: String] = [:]
    private var messageOrder: [Int] = []
    /// When messages were typed into a session (the last minute), and the last one.
    private var typedTimes: [Date] = []
    private var lastTyped: (sessionID: String, text: String, date: Date)?
    /// The Oui / Non buttons sent (their code → which session, which request, when sent).
    /// Each one works once, and only while that same request is still on screen.
    private var permissionButtons: [String: (sessionID: String, askedAt: Date, sentAt: Date)] = [:]
    /// The choice buttons sent for Claude's questions (their code → which session, which
    /// questions, which one of them, when sent). Each message's buttons work once.
    private var questionButtons: [String: (sessionID: String, askedAt: Date, index: Int, sentAt: Date)] = [:]
    /// Several questions are answered one after the other: the next one to answer, per session.
    private var questionProgress: [String: (askedAt: Date, index: Int)] = [:]
    /// `/unlock` was sent alone: until then, a message with just the six digits is the code.
    private var codeAskedUntil: Date?
    /// When messages were refused while unlocked (the last `remoteRefusalWindow`).
    private var refusalTimes: [Date] = []
    private var loop: Task<Void, Never>?
    /// Locks again (and tells you) when the unlock time is up.
    private var relock: Task<Void, Never>?
    private var observers = Set<AnyCancellable>()

    init(hub: HubModel) {
        self.hub = hub
        // The commands only work with an unlock code: without one, they stay off.
        if !lock.isSetUp { settings.remoteEnabled = false }
        // Asks Telegram only while the switch is on and a bot and a conversation are set.
        Publishers.CombineLatest3(settings.$remoteEnabled, settings.$botName, settings.$chatID)
            .map { enabled, bot, chat in enabled && bot != nil && chat != nil }
            .removeDuplicates()
            .sink { [weak self] isOn in MainActor.assumeIsolated { self?.setListening(isOn) } }
            .store(in: &observers)
    }

    /// Called with all the session files each time they are read.
    func update(_ files: [SessionFile]) {
        self.files = Dictionary(files.map { ($0.sessionID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// A message the bot sent about this session: your reply to it goes there.
    func remember(_ messageID: Int, for sessionID: String) {
        sessionOfMessage[messageID] = sessionID
        messageOrder.append(messageID)
        while messageOrder.count > T.remoteRememberedMessages {
            sessionOfMessage[messageOrder.removeFirst()] = nil
        }
    }

    // MARK: - Listening

    private func setListening(_ isOn: Bool) {
        loop?.cancel()
        loop = nil
        // Turning the switch on or off always starts locked.
        relock?.cancel()
        lock.lock()
        updateBotCommands(isOn)
        guard isOn else { return }
        RemoteLog.requestNotifications()
        RemoteLog.write("ÉCOUTE  commandes depuis Telegram allumées")
        let start = Date()
        loop = Task { [weak self] in await self?.listen(since: start) }
    }

    private func listen(since start: Date) async {
        guard let token = TelegramKeychain.token() else { return }
        // Messages written while the switch was off are skipped: only the last one is
        // asked for, and reading from the next number marks it as read.
        var offset: Int?
        if let last = try? await TelegramClient.updates(token: token, offset: -1, wait: 0).last {
            offset = last.updateID + 1
        }
        while !Task.isCancelled {
            do {
                let messages = try await TelegramClient.updates(token: token, offset: offset, wait: T.remoteWait)
                for message in messages {
                    offset = message.updateID + 1
                    handle(message, since: start)
                }
            } catch is CancellationError {
                return
            } catch {
                try? await Task.sleep(for: .seconds(T.remoteRetryDelay))
            }
        }
    }

    private func handle(_ message: TelegramClient.Incoming, since start: Date) {
        if let press = message.button {
            handleButton(press, on: message)
            return
        }
        guard settings.remoteEnabled,
              message.date.timeIntervalSince1970 >= start.timeIntervalSince1970.rounded(.down) else { return }
        // Anyone else writing to the bot: ignored, without an answer, but you are told.
        guard message.isPrivate, message.chatID == settings.chatID else {
            RemoteLog.write("IGNORÉ  message d'une autre conversation (\(message.chatID))", text: message.text)
            RemoteLog.notify("Telegram : message d'un inconnu", "Quelqu'un d'autre a écrit à ton bot. Il a été ignoré.")
            return
        }
        // Each message once, even after a relaunch: its number must be newer than the last
        // one handled (numbers only go up in a conversation).
        guard message.messageID > lastHandledMessageID else { return }
        lastHandledMessageID = message.messageID
        let age = Date().timeIntervalSince(message.date)
        guard age <= T.remoteMaxAge else {
            RemoteLog.write("REFUSÉ  arrivé en retard (\(Self.duration(age)))", text: message.text)
            answer("✗ Refusé : message arrivé en retard (écrit il y a \(Self.duration(age))). Renvoie-le si c'est toujours d'actualité.", to: message)
            return
        }
        guard let text = message.text else {
            RemoteLog.write("REFUSÉ  pas un message texte")
            answer("✗ Seuls les messages texte sont acceptés.", to: message)
            return
        }
        // After "/unlock" alone, the next message with just the six digits is the code.
        // Any other message stops the wait.
        let digits = text.filter(\.isNumber)
        let isLoneCode = digits.count == TOTP.digits && text.allSatisfy { $0.isNumber || $0.isWhitespace }
        if let until = codeAskedUntil {
            codeAskedUntil = nil
            if isLoneCode, Date() < until {
                unlock(code: digits, message: message)
                return
            }
        }
        // Six digits alone, without "/unlock" first (or too late): removed, so a code does
        // not stay in the conversation, and not counted as a wrong code.
        if isLoneCode {
            deleteMessage(message)
            RemoteLog.write("IGNORÉ  code sans /unlock")
            send("Envoie d'abord /unlock, puis le code (dans la minute).")
            return
        }
        // "/unlock 123456" (or "/unlock@NomDuBot 123456" from Telegram's command list), "/lock".
        let words = text.split(whereSeparator: \.isWhitespace)
        switch words.first.map({ $0.split(separator: "@").first.map(String.init) ?? "" }) {
        case "/unlock":
            let code = words.dropFirst().joined()
            guard !code.isEmpty else {
                // Alone (touched in Telegram's list of commands): the bot waits for the code.
                RemoteLog.write("CODE DEMANDÉ  /unlock")
                codeAskedUntil = Date().addingTimeInterval(T.remoteCodeWait)
                Task {
                    await settings.send("🔑 Envoie le code à 6 chiffres de ton app de codes (dans la minute).",
                                        isHTML: true, askReply: "123456")
                }
                return
            }
            unlock(code: code, message: message)
            return
        case "/lock":
            relock?.cancel()
            lock.lock()
            RemoteLog.write("VERROUILLÉ  /lock")
            answer("🔒 Verrouillé.", to: message)
            return
        case "/aide", "/help", "/start":
            RemoteLog.write("AIDE")
            answer(Self.helpText, to: message)
            return
        case "/sessions":
            guard lock.isUnlocked else {
                RemoteLog.write("REFUSÉ  /sessions verrouillé")
                answer("🔒 Verrouillé : envoie /unlock suivi du code pour voir tes sessions.", to: message)
                return
            }
            RemoteLog.write("SESSIONS")
            listSessions()
            return
        case let word? where word.hasPrefix("/") && message.replyTo == nil:
            RemoteLog.write("IGNORÉ  commande inconnue", text: text)
            answer("Commande inconnue. " + Self.helpText, to: message)
            return
        default:
            break
        }
        guard lock.isUnlocked else {
            RemoteLog.write("REFUSÉ  verrouillé", text: text)
            answer("🔒 Verrouillé : envoie /unlock suivi du code à 6 chiffres de ton app de codes.", to: message)
            return
        }
        guard let replyTo = message.replyTo, let sessionID = sessionOfMessage[replyTo] else {
            RemoteLog.write("IGNORÉ  pas une réponse à une notification", text: text)
            answer("Réponds à une notification d'une session (glisse-la vers la gauche) pour lui écrire.", to: message)
            return
        }
        do {
            let name = try type(text, into: sessionID)
            RemoteLog.write("ENVOYÉ", project: name, text: text)
            RemoteLog.notify("Telegram → \(name)", text)
            answer("✓ Envoyé à <b>\(TelegramClient.escapeHTML(name))</b>", to: message, about: sessionID)
        } catch let refusal as Refusal {
            RemoteLog.write("REFUSÉ  \(refusal.reason)", project: projectName(of: sessionID), text: text)
            answer("✗ Refusé : \(TelegramClient.escapeHTML(refusal.reason))", to: message, about: sessionID)
            noteRefusal()
        } catch {}
    }

    /// Too many refusals in a short time (someone trying, or something gone wrong): locked again.
    private func noteRefusal() {
        let now = Date()
        refusalTimes = refusalTimes.filter { now.timeIntervalSince($0) < T.remoteRefusalWindow } + [now]
        guard refusalTimes.count >= T.remoteMaxRefusals, lock.isUnlocked else { return }
        refusalTimes = []
        relock?.cancel()
        lock.lock()
        RemoteLog.write("VERROUILLÉ  trop de messages refusés")
        RemoteLog.notify("Telegram : reverrouillé", "Trop de messages refusés en peu de temps.")
        send("🔒 Trop de messages refusés : reverrouillé. Envoie /unlock suivi du code pour continuer.")
    }

    // MARK: - Commands of the bot

    private static let commands: [(name: String, description: String)] = [
        ("unlock", "Déverrouiller (le bot te demande ton code à 6 chiffres)"),
        ("lock", "Reverrouiller tout de suite"),
        ("sessions", "Tes sessions et leur état (réponds à l'une pour lui écrire)"),
        ("aide", "Comment ça marche"),
    ]

    private static var helpText: String {
        """
        <b>Commandes</b>
        /unlock : déverrouille \(Int(T.unlockDuration / 60)) min, le bot te demande le code de ton app de codes (ou /unlock 123456 d'un coup)
        /lock : reverrouille
        /sessions : tes sessions et leur état
        /aide : ce message

        Pour écrire à une session : réponds à une de ses notifications (glisse-la vers la gauche), ou à son message dans /sessions.
        """
    }

    /// Telegram proposes the bot's commands only while the commands are on.
    private func updateBotCommands(_ isOn: Bool) {
        guard let token = TelegramKeychain.token() else { return }
        Task {
            if isOn {
                try? await TelegramClient.setCommands(Self.commands, token: token)
            } else {
                try? await TelegramClient.deleteCommands(token: token)
            }
        }
    }

    /// `/sessions`: one message per session (waiting ones first, then the most recent),
    /// so that a reply to one of them goes to that session.
    private func listSessions() {
        let sessions = files.values.sorted {
            ($0.status == .waiting ? 0 : 1, -$0.statusChangedAt.timeIntervalSince1970)
                < ($1.status == .waiting ? 0 : 1, -$1.statusChangedAt.timeIntervalSince1970)
        }
        Task {
            guard !sessions.isEmpty else {
                await settings.send("Aucune session Claude ouverte.", isHTML: true)
                return
            }
            let shown = sessions.prefix(T.remoteSessionsListMax)
            var header = "📋 <b>\(sessions.count) session\(sessions.count > 1 ? "s" : "")</b>"
            if sessions.count > shown.count { header += " (les \(shown.count) premières)" }
            await settings.send(header + " : réponds à l'une d'elles pour lui écrire.", isHTML: true)
            for file in shown {
                let buttons = buttons(for: file)
                guard let id = await settings.send(describe(file, withChoices: buttons == nil), isHTML: true,
                                                   buttons: buttons) else { return }
                remember(id, for: file.sessionID)
            }
        }
    }

    /// "<b>CubeWidget</b> - bosse · 12 min", its current task, what it waits for, and
    /// whether a reply can go there. A question's choices are written out when they have
    /// no buttons.
    private func describe(_ file: SessionFile, withChoices: Bool) -> String {
        let folder = URL(fileURLWithPath: file.cwd)
        let status = switch file.status {
        case .working: "bosse 🔵"
        case .waiting: "attend ta réponse ⏳"
        case .done: "terminé ✅"
        }
        var lines = ["<b>\(TelegramClient.escapeHTML(folder.lastPathComponent))</b> - \(status) · \(Self.duration(Date().timeIntervalSince(file.startedAt)))"]
        let task = file.tasks.last(where: { $0.status == "in_progress" }) ?? file.tasks.last
        if let task, !task.subject.isEmpty {
            let subject = task.subject.count > T.taskTitleMaxLength
                ? task.subject.prefix(T.taskTitleMaxLength - 1) + "…" : task.subject
            lines.append(TelegramClient.escapeHTML(subject))
        }
        if file.status == .waiting, let permission = file.pendingPermission {
            lines.append(Self.permissionText(permission))
        } else if file.status == .waiting, let question = file.pendingQuestion {
            let index = questionIndex(of: file)
            lines.append(Self.questionText(question, index: index))
            if withChoices { lines.append(Self.choicesText(question.items[index])) }
        }
        if hub.project(forTTY: file.tty) == nil {
            lines.append("<i>Dans Terminal : réponses impossibles</i>")
        } else if !settings.isRemoteAllowed(for: folder) {
            lines.append("<i>Réponses non autorisées (à autoriser sur le Mac)</i>")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Permissions: the Oui / Non buttons (T5)

    /// "🔐 Bash : touch notes.txt", and below, what Claude says it is for.
    static func permissionText(_ permission: SessionFile.Permission) -> String {
        func short(_ text: String) -> String {
            let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            return flat.count > T.permissionDetailMaxLength ? flat.prefix(T.permissionDetailMaxLength - 1) + "…" : flat
        }
        var text = "🔐 <b>\(TelegramClient.escapeHTML(permission.tool))</b> : <code>\(TelegramClient.escapeHTML(short(permission.detail)))</code>"
        if let description = permission.description, !description.isEmpty {
            text += "\n<i>\(TelegramClient.escapeHTML(short(description)))</i>"
        }
        return text
    }

    /// The buttons under a message about a session that waits for you: Oui / Non for a
    /// permission, one per choice for a question. Only if your answers can go there
    /// (commands on, project allowed). Nil otherwise.
    func buttons(for file: SessionFile) -> [[TelegramClient.Button]]? {
        guard settings.remoteEnabled, file.status == .waiting,
              settings.isRemoteAllowed(for: URL(fileURLWithPath: file.cwd)) else { return nil }
        if let permission = file.pendingPermission {
            let now = Date()
            permissionButtons = permissionButtons.filter { now.timeIntervalSince($0.value.sentAt) < T.permissionButtonsMaxAge }
            let code = Self.newCode()
            permissionButtons[code] = (file.sessionID, permission.at, now)
            return [[TelegramClient.Button(text: "✅ Oui", data: "perm:y:\(code)"),
                     TelegramClient.Button(text: "❌ Non", data: "perm:n:\(code)")]]
        }
        if let question = file.pendingQuestion {
            return questionButtons(question, index: questionIndex(of: file), of: file.sessionID)
        }
        return nil
    }

    private static func newCode() -> String { String(UUID().uuidString.prefix(8)) }

    /// A tap on a button: Oui / Non of a permission, or a choice of a question.
    private func handleButton(_ press: TelegramClient.ButtonPress, on message: TelegramClient.Incoming) {
        guard let chatID = settings.chatID else { return }
        // Someone else (a forwarded message, a group…): ignored, but you are told.
        guard message.isPrivate, message.chatID == chatID, press.fromID == chatID else {
            RemoteLog.write("IGNORÉ  bouton touché depuis une autre conversation (\(press.fromID))")
            RemoteLog.notify("Telegram : bouton d'un inconnu", "Quelqu'un d'autre a touché un bouton de ton bot. Ignoré.")
            toast(press, "✗ Refusé")
            return
        }
        let parts = press.data.split(separator: ":").map(String.init)
        guard parts.count == 3, ["perm", "q"].contains(parts[0]) else {
            toast(press, "Bouton inconnu")
            return
        }
        guard settings.remoteEnabled else {
            toast(press, "✗ Commandes depuis Telegram éteintes sur le Mac")
            return
        }
        if parts[0] == "perm" {
            handlePermissionButton(press, answer: parts[1], code: parts[2], on: message)
        } else {
            handleQuestionButton(press, code: parts[1], choice: parts[2], on: message)
        }
    }

    /// The short text shown on the phone after a tap.
    private func toast(_ press: TelegramClient.ButtonPress, _ text: String) {
        guard let token = TelegramKeychain.token() else { return }
        Task { try? await TelegramClient.answerButton(press.id, text: text, token: token) }
    }

    private func removeButtons(of message: TelegramClient.Incoming) {
        guard let token = TelegramKeychain.token(), let chatID = settings.chatID else { return }
        Task { try? await TelegramClient.removeButtons(of: message.messageID, in: chatID, token: token) }
    }

    /// A tap on Oui or Non.
    private func handlePermissionButton(_ press: TelegramClient.ButtonPress, answer key: String, code: String,
                                        on message: TelegramClient.Incoming) {
        guard let isYes = ["y": true, "n": false][key] else {
            toast(press, "Bouton inconnu")
            return
        }
        let choice = isYes ? "Oui" : "Non"
        guard let sent = permissionButtons[code],
              Date().timeIntervalSince(sent.sentAt) < T.permissionButtonsMaxAge else {
            permissionButtons[code] = nil
            RemoteLog.write("REFUSÉ  bouton \(choice) expiré ou déjà utilisé")
            toast(press, "✗ Bouton expiré ou déjà utilisé")
            removeButtons(of: message)
            return
        }
        // Locked: the button stays usable once unlocked.
        guard lock.isUnlocked else {
            RemoteLog.write("REFUSÉ  bouton \(choice) verrouillé", project: projectName(of: sent.sessionID))
            toast(press, "🔒 Verrouillé : envoie /unlock, puis touche à nouveau le bouton")
            return
        }
        do {
            let name = try pressKey(isYes, for: sent.sessionID, askedAt: sent.askedAt)
            permissionButtons[code] = nil
            removeButtons(of: message)
            RemoteLog.write("PERMISSION  \(choice)", project: name)
            RemoteLog.notify("Telegram → \(name)", isYes ? "Permission accordée (Oui)" : "Permission refusée (Non)")
            toast(press, isYes ? "✅ Oui envoyé" : "❌ Non envoyé")
            answer(isYes ? "✅ Oui envoyé à <b>\(TelegramClient.escapeHTML(name))</b>"
                         : "❌ Non envoyé à <b>\(TelegramClient.escapeHTML(name))</b>",
                   to: message, about: sent.sessionID)
        } catch let refusal as Refusal {
            if refusal.isFinal {
                permissionButtons[code] = nil
                removeButtons(of: message)
            }
            RemoteLog.write("REFUSÉ  bouton \(choice) : \(refusal.reason)", project: projectName(of: sent.sessionID))
            toast(press, "✗ Refusé")
            answer("✗ Refusé : \(TelegramClient.escapeHTML(refusal.reason))", to: message, about: sent.sessionID)
            noteRefusal()
        } catch {}
    }

    /// Presses "1" (Oui) or Échap (Non) in the session's terminal, after checking that
    /// Claude is still asking that same permission, on screen. Returns the project's name.
    private func pressKey(_ isYes: Bool, for sessionID: String, askedAt: Date) throws -> String {
        guard let file = files[sessionID] else { throw Refusal(reason: "cette session est fermée.", isFinal: true) }
        let folder = URL(fileURLWithPath: file.cwd)
        let name = folder.lastPathComponent
        guard file.status == .waiting, file.pendingPermission?.at == askedAt else {
            throw Refusal(reason: "cette demande de « \(name) » est terminée (déjà répondue ?).", isFinal: true)
        }
        let project = try answerableProject(of: file)
        guard Self.showsPermissionMenu(project) else {
            throw Refusal(reason: "le menu de permission n'est pas à l'écran dans le terminal de « \(name) » (fais défiler le terminal tout en bas sur le Mac, ou réponds depuis le Mac).")
        }
        try countKeyPress()
        // "1" chooses "Yes" right away; Échap cancels (Claude runs nothing and waits for you).
        project.terminal.send(txt: isYes ? "1" : "\u{1b}")
        return name
    }

    /// The session's terminal, if a button's key can go there now: project allowed, in
    /// the Cube Hub, with Claude in the foreground.
    private func answerableProject(of file: SessionFile) throws -> HubProject {
        let folder = URL(fileURLWithPath: file.cwd)
        let name = folder.lastPathComponent
        guard settings.isRemoteAllowed(for: folder) else {
            throw Refusal(reason: "« \(name) » n'accepte pas les commandes (à autoriser sur le Mac : Réglages → Telegram – Commandes).")
        }
        guard let project = hub.project(forTTY: file.tty), project.isRunning else {
            throw Refusal(reason: "« \(name) » ne tourne pas dans le Cube Hub.", isFinal: true)
        }
        guard let pid = file.pid, Self.isInForeground(pid, of: project) else {
            throw Refusal(reason: "Claude n'est pas au premier plan dans le terminal de « \(name) ».")
        }
        return project
    }

    /// A button's key counts in the limit of messages per minute.
    private func countKeyPress() throws {
        let now = Date()
        typedTimes = typedTimes.filter { now.timeIntervalSince($0) < 60 }
        guard typedTimes.count < T.remoteMaxPerMinute else {
            throw Refusal(reason: "trop de messages (\(T.remoteMaxPerMinute) par minute au plus) : réessaie dans un moment.")
        }
        typedTimes.append(now)
    }

    /// The visible screen of the terminal shows Claude's permission menu.
    private static func showsPermissionMenu(_ project: HubProject) -> Bool {
        let screen = screen(of: project)
        return T.permissionPromptMarkers.allSatisfy { marker in screen.contains { $0.contains(marker) } }
    }

    /// The lines of the terminal's visible screen. Cells never written (Claude moves the
    /// cursor over them instead of writing spaces) come as NUL characters: read as spaces.
    private static func screen(of project: HubProject) -> [String] {
        let terminal = project.terminal.getTerminal()
        return (0..<terminal.rows).compactMap {
            terminal.getLine(row: $0)?.translateToString(trimRight: true).replacingOccurrences(of: "\u{0}", with: " ")
        }
    }

    // MARK: - Questions: one button per choice (T6)

    /// "❓ <b>Couleur</b> (1/2) : Quelle couleur préfères-tu ?". With several choices
    /// possible, it says to answer from the Mac (no buttons).
    static func questionText(_ question: SessionFile.Question, index: Int) -> String {
        let item = question.items[index]
        var text = "❓ "
        if let header = item.header, !header.isEmpty { text += "<b>\(TelegramClient.escapeHTML(header))</b> " }
        if question.items.count > 1 { text += "(\(index + 1)/\(question.items.count)) " }
        text += ": " + TelegramClient.escapeHTML(item.question)
        if question.items.contains(where: \.multiSelect) {
            text += "\n<i>Plusieurs réponses possibles : réponds depuis le Mac.</i>"
        }
        return text
    }

    /// The choices written out, for a message without buttons: "• Violet", "• Rose"…
    static func choicesText(_ item: SessionFile.Question.Item) -> String {
        item.options.map { "• " + TelegramClient.escapeHTML($0) }.joined(separator: "\n")
    }

    /// One button per choice of the question at `index` ("1. Violet"…). None when several
    /// choices can be ticked: that is answered on the Mac.
    private func questionButtons(_ question: SessionFile.Question, index: Int,
                                 of sessionID: String) -> [[TelegramClient.Button]]? {
        guard !question.items.contains(where: \.multiSelect), index < question.items.count,
              !question.items[index].options.isEmpty else { return nil }
        let now = Date()
        questionButtons = questionButtons.filter { now.timeIntervalSince($0.value.sentAt) < T.permissionButtonsMaxAge }
        let code = Self.newCode()
        questionButtons[code] = (sessionID, question.at, index, now)
        return question.items[index].options.enumerated().map { number, label in
            let short = label.count > T.questionButtonMaxLength ? label.prefix(T.questionButtonMaxLength - 1) + "…" : label
            return [TelegramClient.Button(text: "\(number + 1). \(short)", data: "q:\(code):\(number)")]
        }
    }

    /// The question of this session to answer now (several are answered one after the other).
    private func questionIndex(of file: SessionFile) -> Int {
        guard let question = file.pendingQuestion, let progress = questionProgress[file.sessionID],
              progress.askedAt == question.at else { return 0 }
        return min(progress.index, question.items.count - 1)
    }

    /// A tap on a choice. With several questions, the next one is sent with its buttons;
    /// after the last one, the answers are validated.
    private func handleQuestionButton(_ press: TelegramClient.ButtonPress, code: String, choice: String,
                                      on message: TelegramClient.Incoming) {
        guard let choice = Int(choice) else {
            toast(press, "Bouton inconnu")
            return
        }
        guard let sent = questionButtons[code],
              Date().timeIntervalSince(sent.sentAt) < T.permissionButtonsMaxAge else {
            questionButtons[code] = nil
            RemoteLog.write("REFUSÉ  choix expiré ou déjà utilisé")
            toast(press, "✗ Bouton expiré ou déjà utilisé")
            removeButtons(of: message)
            return
        }
        // Locked: the buttons stay usable once unlocked.
        guard lock.isUnlocked else {
            RemoteLog.write("REFUSÉ  choix verrouillé", project: projectName(of: sent.sessionID))
            toast(press, "🔒 Verrouillé : envoie /unlock, puis touche à nouveau le bouton")
            return
        }
        let sessionID = sent.sessionID
        do {
            let (name, question) = try choose(choice, for: sessionID, askedAt: sent.askedAt, index: sent.index)
            questionButtons[code] = nil
            removeButtons(of: message)
            let item = question.items[sent.index]
            let label = item.options[choice]
            RemoteLog.write("CHOIX  \(label)", project: name, text: item.question)
            RemoteLog.notify("Telegram → \(name)", "\(item.question) → \(label)")
            toast(press, "✅ \(label)")
            let reply = "✅ <b>\(TelegramClient.escapeHTML(label))</b> envoyé à <b>\(TelegramClient.escapeHTML(name))</b>"
            let next = sent.index + 1
            if next < question.items.count {
                // The terminal is on the next question now: sent with its own buttons.
                questionProgress[sessionID] = (question.at, next)
                let buttons = questionButtons(question, index: next, of: sessionID)
                Task {
                    guard let id = await settings.send(reply + "\n\n" + Self.questionText(question, index: next),
                                                       isHTML: true, replyTo: message.messageID,
                                                       buttons: buttons) else { return }
                    remember(id, for: sessionID)
                }
            } else {
                questionProgress[sessionID] = nil
                if question.items.count > 1 {
                    submit(question, of: sessionID, name: name, reply: reply, to: message)
                } else {
                    answer(reply, to: message, about: sessionID)
                }
            }
        } catch let refusal as Refusal {
            if refusal.isFinal {
                questionButtons[code] = nil
                removeButtons(of: message)
            }
            RemoteLog.write("REFUSÉ  choix : \(refusal.reason)", project: projectName(of: sessionID))
            toast(press, "✗ Refusé")
            answer("✗ Refusé : \(TelegramClient.escapeHTML(refusal.reason))", to: message, about: sessionID)
            noteRefusal()
        } catch {}
    }

    /// Presses the choice's number in the session's terminal ("2" chooses the second choice
    /// right away), after checking that Claude is still asking that same question, on
    /// screen. Returns the project's name and the questions.
    private func choose(_ choice: Int, for sessionID: String, askedAt: Date,
                        index: Int) throws -> (String, SessionFile.Question) {
        guard let file = files[sessionID] else { throw Refusal(reason: "cette session est fermée.", isFinal: true) }
        let name = URL(fileURLWithPath: file.cwd).lastPathComponent
        guard file.status == .waiting, let question = file.pendingQuestion, question.at == askedAt else {
            throw Refusal(reason: "cette question de « \(name) » est terminée (déjà répondue ?).", isFinal: true)
        }
        guard index < question.items.count, choice < question.items[index].options.count else {
            throw Refusal(reason: "choix inconnu.", isFinal: true)
        }
        let project = try answerableProject(of: file)
        guard Self.showsQuestion(question.items[index], choice: choice, in: project) else {
            throw Refusal(reason: "cette question n'est pas à l'écran dans le terminal de « \(name) » (déjà répondue sur le Mac ? Sinon fais défiler le terminal tout en bas, ou réponds depuis le Mac).")
        }
        try countKeyPress()
        project.terminal.send(txt: "\(choice + 1)")
        return (name, question)
    }

    /// The question at the bottom of the terminal (from its title line, "☐ Couleur", to
    /// "Enter to select") is this one, with this choice.
    private static func showsQuestion(_ item: SessionFile.Question.Item, choice: Int, in project: HubProject) -> Bool {
        let screen = screen(of: project)
        guard let end = screen.lastIndex(where: { $0.contains(T.questionPromptMarker) }),
              let start = screen[..<end].lastIndex(where: { $0.contains("☐") || $0.contains("☒") }) else { return false }
        let lines = screen[start...end]
        let question = String(item.question.trimmingCharacters(in: .whitespaces).prefix(T.questionMatchLength))
        let option = "\(choice + 1). " + item.options[choice].trimmingCharacters(in: .whitespaces).prefix(T.questionMatchLength)
        return lines.contains { $0.contains(question) } && lines.contains { $0.contains(option) }
    }

    /// Several questions: once all are answered, the terminal shows a summary to validate
    /// with "1" ("Submit answers"). Pressed as soon as it shows.
    private func submit(_ question: SessionFile.Question, of sessionID: String, name: String, reply: String,
                        to message: TelegramClient.Incoming) {
        Task {
            for _ in 0..<T.questionSubmitTries {
                try? await Task.sleep(for: .seconds(T.questionSubmitDelay))
                guard let file = files[sessionID], file.status == .waiting, file.pendingQuestion?.at == question.at,
                      let project = try? answerableProject(of: file) else { break }
                if Self.screen(of: project).contains(where: { $0.contains(T.questionSubmitMarker) }) {
                    project.terminal.send(txt: "1")
                    RemoteLog.write("RÉPONSES VALIDÉES", project: name)
                    answer(reply + "\n📨 Réponses validées.", to: message, about: sessionID)
                    return
                }
            }
            RemoteLog.write("REFUSÉ  validation des réponses pas à l'écran", project: name)
            answer(reply + "\n✗ L'écran de validation n'est pas apparu : valide tes réponses depuis le Mac.",
                   to: message, about: sessionID)
        }
    }

    private func projectName(of sessionID: String) -> String? {
        files[sessionID].map { URL(fileURLWithPath: $0.cwd).lastPathComponent }
    }

    /// The number of the last message handled, remembered per conversation.
    private var lastHandledMessageID: Int {
        get { UserDefaults.standard.integer(forKey: lastMessageKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastMessageKey) }
    }

    private var lastMessageKey: String { "telegramRemoteLastMessage.\(settings.chatID ?? 0)" }

    /// "45 s", "3 min".
    private static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 120 { return "\(Int(seconds)) s" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        return String(format: "%d h %02d", Int(seconds / 3600), Int(seconds.truncatingRemainder(dividingBy: 3600) / 60))
    }

    /// Checks the code. Your message is removed from the conversation right away, so the
    /// code does not stay there.
    private func unlock(code: String, message: TelegramClient.Incoming) {
        deleteMessage(message)
        switch lock.unlock(with: code) {
        case .unlocked(let until):
            let time = until.formatted(date: .omitted, time: .shortened)
            RemoteLog.write("DÉVERROUILLÉ  jusqu'à \(time)")
            RemoteLog.notify("Telegram : commandes déverrouillées", "Jusqu'à \(time). Si ce n'est pas toi, verrouille depuis le menu du cube.")
            send("🔓 Déverrouillé jusqu'à \(until.formatted(date: .omitted, time: .shortened)). "
                 + "Réponds à une notification pour écrire à sa session. /lock pour reverrouiller.")
            relock?.cancel()
            relock = Task { [weak self] in
                try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
                guard !Task.isCancelled, let self, self.lock.unlockedUntil == until else { return }
                self.lock.lock()
                RemoteLog.write("VERROUILLÉ  fin du temps")
                self.send("🔒 Reverrouillé : les \(Int(T.unlockDuration / 60)) minutes sont écoulées.")
            }
        case .wrong(let triesLeft):
            RemoteLog.write("CODE FAUX  encore \(triesLeft) essai(s)")
            RemoteLog.notify("Telegram : code faux", "Quelqu'un a essayé un code de déverrouillage faux.")
            send("✗ Code faux (encore \(triesLeft) essai\(triesLeft > 1 ? "s" : "")).")
        case .reused:
            RemoteLog.write("CODE DÉJÀ UTILISÉ")
            send("✗ Ce code a déjà servi : attends le suivant (30 s).")
        case .blocked:
            relock?.cancel()
            RemoteLog.write("BLOQUÉ  trop de codes faux, commandes désactivées")
            RemoteLog.notify("Telegram : commandes désactivées", "Trop de codes faux. Réactive-les dans Réglages → Telegram – Commandes.")
            send("⛔ Trop de codes faux : commandes depuis Telegram désactivées. Réactive-les depuis le Mac.")
        case .notSetUp:
            send("✗ Le code de déverrouillage n'est pas configuré sur le Mac.")
        }
    }

    private func deleteMessage(_ message: TelegramClient.Incoming) {
        guard let chatID = settings.chatID, let token = TelegramKeychain.token() else { return }
        Task { try? await TelegramClient.deleteMessage(message.messageID, in: chatID, token: token) }
    }

    /// A message of the bot, not attached to yours (yours, with the code, is removed).
    private func send(_ text: String) {
        Task { await settings.send(text, isHTML: true) }
    }

    /// Sends an answer under your message. A reply to that answer goes to the same session.
    private func answer(_ text: String, to message: TelegramClient.Incoming, about sessionID: String? = nil) {
        Task {
            guard let answerID = await settings.send(text, isHTML: true, replyTo: message.messageID),
                  let sessionID else { return }
            remember(answerID, for: sessionID)
        }
    }

    // MARK: - Typing into the session

    /// Types the text into the session's terminal and presses Entrée. Returns the
    /// project's name.
    private func type(_ text: String, into sessionID: String) throws -> String {
        guard let file = files[sessionID] else { throw Refusal(reason: "cette session est fermée.") }
        let folder = URL(fileURLWithPath: file.cwd)
        let name = folder.lastPathComponent
        guard settings.isRemoteAllowed(for: folder) else {
            throw Refusal(reason: "« \(name) » n'accepte pas les commandes (à autoriser sur le Mac : Réglages → Telegram – Commandes).")
        }
        guard let project = hub.project(forTTY: file.tty), project.isRunning else {
            throw Refusal(reason: "« \(name) » ne tourne pas dans le Cube Hub.")
        }
        guard file.status != .waiting else {
            throw Refusal(reason: file.pendingPermission != nil
                ? "« \(name) » attend ta permission : utilise les boutons Oui / Non sous sa notification (ou /sessions)."
                : file.pendingQuestion != nil
                ? "« \(name) » attend ta réponse à une question : touche un choix sous sa notification (ou /sessions), ou réponds depuis le Mac."
                : "« \(name) » attend ta réponse : réponds depuis le Mac.")
        }
        guard let pid = file.pid, Self.isInForeground(pid, of: project) else {
            throw Refusal(reason: "Claude n'est pas au premier plan dans le terminal de « \(name) ».")
        }
        let text = Self.cleaned(text)
        guard !text.isEmpty else { throw Refusal(reason: "message vide.") }
        guard !text.hasPrefix("!") else { throw Refusal(reason: "les commandes du terminal (« ! ») sont interdites.") }
        guard !text.hasPrefix("/") else {
            throw Refusal(reason: "les commandes de Claude (« / ») sont interdites depuis Telegram.")
        }
        guard !text.hasPrefix("#") else {
            throw Refusal(reason: "les notes de mémoire (« # ») sont interdites depuis Telegram.")
        }
        guard text.count <= T.remoteMaxLength else {
            throw Refusal(reason: "message trop long (\(T.remoteMaxLength) caractères max).")
        }
        let now = Date()
        if let last = lastTyped, last.sessionID == sessionID, last.text == text,
           now.timeIntervalSince(last.date) < T.remoteDuplicateWindow {
            throw Refusal(reason: "ce message vient déjà d'être envoyé à « \(name) ».")
        }
        typedTimes = typedTimes.filter { now.timeIntervalSince($0) < 60 }
        if typedTimes.count >= T.remoteMaxPerMinute, let oldest = typedTimes.first {
            let wait = Int((60 - now.timeIntervalSince(oldest)).rounded(.up))
            throw Refusal(reason: "trop de messages (\(T.remoteMaxPerMinute) par minute au plus) : réessaie dans \(wait) s.")
        }
        typedTimes.append(now)
        lastTyped = (sessionID, text, now)

        // Pasted as one block (a new line stays a new line, it does not send), then Entrée.
        let terminal = project.terminal
        if terminal.getTerminal().bracketedPasteMode {
            terminal.send(txt: "\u{1b}[200~" + text + "\u{1b}[201~")
        } else {
            terminal.send(txt: text.replacingOccurrences(of: "\n", with: " "))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + T.remoteSubmitDelay) { [weak project] in
            project?.terminal.send(txt: "\r")
        }
        return name
    }

    /// The program the terminal's keyboard goes to is this Claude Code process (not the
    /// shell after `exit`, not a program Claude started in the foreground).
    private static func isInForeground(_ pid: Int32, of project: HubProject) -> Bool {
        let master = project.terminal.process.childfd
        guard master >= 0 else { return false }
        return tcgetpgrp(master) == pid && HubWindowController.isClaudeCode(pid)
    }

    /// Without control characters (Échap, Ctrl-C…: they could drive the terminal), with
    /// plain new lines, and without spaces around.
    static func cleaned(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let scalars = lines.unicodeScalars.filter { $0 == "\n" || $0.properties.generalCategory != .control }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
