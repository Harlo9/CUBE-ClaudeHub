import Foundation

/// What the hook knows about one Claude Code session. It is written by `cube-hook` in
/// `~/.cube-widget/sessions/<session_id>.json` and read by the app.
public struct SessionFile: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// Claude is working.
        case working
        /// Claude needs you: a permission to give, a question, a plan to approve.
        case waiting
        /// Claude finished its answer (or the session just opened): your turn, nothing urgent.
        case done
    }

    /// One task of Claude Code's task list.
    public struct Task: Codable, Equatable, Sendable {
        public var id: String
        public var subject: String
        /// `pending`, `in_progress` or `completed`.
        public var status: String

        public init(id: String, subject: String, status: String) {
            self.id = id
            self.subject = subject
            self.status = status
        }
    }

    /// The last task marked as completed, with when it happened (the app shows the
    /// "task completed" state when this changes).
    public struct CompletedTask: Codable, Equatable, Sendable {
        public var id: String
        public var subject: String
        public var at: Date

        public init(id: String, subject: String, at: Date) {
            self.id = id
            self.subject = subject
            self.at = at
        }
    }

    /// The end of Claude's last answer (`Stop`): when, and its beginning (up to 4,000
    /// characters, summarized in the "Réponse terminée" Telegram message).
    public struct Answer: Codable, Equatable, Sendable {
        public var excerpt: String
        public var at: Date

        public init(excerpt: String, at: Date) {
            self.excerpt = excerpt
            self.at = at
        }
    }

    /// A permission Claude is asking for (`PermissionRequest`), until the session moves on:
    /// the tool, what it would do (a command, a file…), and when it was asked.
    public struct Permission: Codable, Equatable, Sendable {
        public var tool: String
        public var detail: String
        public var description: String?
        public var at: Date

        public init(tool: String, detail: String, description: String?, at: Date) {
            self.tool = tool
            self.detail = detail
            self.description = description
            self.at = at
        }
    }

    /// The questions Claude is asking you (`AskUserQuestion`, one to four of them), until
    /// the session moves on: each one with its choices, and when they were asked.
    public struct Question: Codable, Equatable, Sendable {
        public struct Item: Codable, Equatable, Sendable {
            public var question: String
            /// Short label, e.g. "Couleur".
            public var header: String?
            /// The choices' labels, in order (chosen in the terminal with "1", "2"…).
            public var options: [String]
            /// Several choices can be ticked.
            public var multiSelect: Bool

            public init(question: String, header: String?, options: [String], multiSelect: Bool) {
                self.question = question
                self.header = header
                self.options = options
                self.multiSelect = multiSelect
            }
        }

        public var items: [Item]
        public var at: Date

        public init(items: [Item], at: Date) {
            self.items = items
            self.at = at
        }
    }

    /// Version of this format, in case it changes later.
    public var version = 1
    public var sessionID: String
    /// Folder the session runs in; its last component is the project name.
    public var cwd: String
    /// Conversation file, where the token counts are.
    public var transcriptPath: String?
    public var status: Status
    public var startedAt: Date
    /// Last hook event received.
    public var updatedAt: Date
    /// Last time `status` changed.
    public var statusChangedAt: Date
    /// PID of the Claude Code process (to notice when it dies without `SessionEnd`).
    public var pid: Int32?
    /// Terminal of the session, e.g. `/dev/ttys009` (to bring its Terminal tab forward).
    public var tty: String?
    /// Tasks in creation order.
    public var tasks: [Task]
    public var lastCompletedTask: CompletedTask?
    /// Missing in files written before it existed (read as nil).
    public var lastAnswer: Answer?
    /// Missing in files written before it existed (read as nil).
    public var pendingPermission: Permission?
    /// Missing in files written before it existed (read as nil).
    public var pendingQuestion: Question?
    /// Last message you sent (`UserPromptSubmit`): its card comes to the front of the
    /// widget. Missing in files written before it existed (read as nil).
    public var lastPromptAt: Date?

    public init(sessionID: String, cwd: String, transcriptPath: String?, status: Status,
                startedAt: Date, now: Date) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = now
        self.statusChangedAt = now
        self.tasks = []
    }
}

/// Where the session files live, and how they are encoded.
public enum SessionFiles {
    /// `~/.cube-widget` (the `CUBE_WIDGET_DIR` environment variable replaces it, for tests).
    public static var baseDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["CUBE_WIDGET_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cube-widget")
    }

    public static var sessionsDirectory: URL { baseDirectory.appendingPathComponent("sessions") }

    public static func url(forSession id: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(id).json")
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
