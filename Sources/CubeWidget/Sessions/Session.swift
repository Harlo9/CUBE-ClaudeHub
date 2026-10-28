import Foundation

/// What a Claude Code session is doing right now.
enum SessionStatus: Equatable {
    case working
    /// Claude needs you: permission, question, plan to approve.
    case waiting
    /// Claude finished its answer: your turn, nothing urgent.
    case done

    /// Label shown on the front card.
    var longLabel: String {
        switch self {
        case .working: "bosse"
        case .waiting: "attend ta réponse"
        case .done: "terminé"
        }
    }

    /// Label shown on the small cards below.
    var shortLabel: String {
        switch self {
        case .working: "bosse"
        case .waiting: "attend"
        case .done: "terminé"
        }
    }
}

/// One Claude Code session, as displayed by the widget.
struct Session: Identifiable, Equatable {
    let id: String
    /// Name of the folder the session runs in (last component of `cwd`).
    var projectName: String
    var status: SessionStatus
    var startedAt: Date
    /// Current context size, in tokens.
    var contextTokens: Int
    /// Task currently in progress (or the last one created), if any.
    var currentTask: String?
    /// Last time the status changed (used to order the cards below).
    var statusChangedAt = Date()
    /// Terminal of the session, e.g. `/dev/ttys009` (to bring its Terminal tab forward).
    var tty: String? = nil
    /// Folder the session runs in (its `cwd`).
    var folder: URL? = nil
    /// Process of Claude Code (to close it in Terminal before resuming it in the Hub).
    var pid: Int32? = nil
}

extension Session {
    /// Fake sessions used until the real data is wired (step 5).
    static let previews: [Session] = [
        Session(id: "preview-1", projectName: "mission-azo", status: .working,
                startedAt: Date().addingTimeInterval(-34 * 60), contextTokens: 210_000,
                currentTask: "Créer le parseur de factures OCR à partir des PDF scannés"),
        Session(id: "preview-2", projectName: "safarifocus", status: .waiting,
                startedAt: Date().addingTimeInterval(-12 * 60), contextTokens: 48_000,
                currentTask: "Corriger le bug du mode focus"),
        Session(id: "preview-3", projectName: "cube-widget", status: .working,
                startedAt: Date().addingTimeInterval(-95 * 60), contextTokens: 132_000,
                currentTask: nil),
        Session(id: "preview-4", projectName: "notes-perso", status: .working,
                startedAt: Date().addingTimeInterval(-5 * 60), contextTokens: 9_000,
                currentTask: "Ranger les notes"),
    ]
}

// MARK: - Formatting

enum SessionFormat {
    /// "12 min", "1 h 05".
    static func duration(since start: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    /// "850 tokens", "210k tokens", "1,2M tokens".
    static func tokens(_ count: Int) -> String {
        switch count {
        case ..<1_000: "\(count) tokens"
        case ..<1_000_000: "\(count / 1_000)k tokens"
        default: String(format: "%.1fM tokens", Double(count) / 1_000_000)
            .replacingOccurrences(of: ".", with: ",")
        }
    }
}
