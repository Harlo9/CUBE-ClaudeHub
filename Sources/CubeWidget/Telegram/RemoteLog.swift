import AppKit
import UserNotifications

/// Layer 4 of the commands from Telegram: a trace of every message received.
/// - a journal, `~/.cube-widget/remote.log`, one line per message (what came in and what
///   the app did with it; never the unlock code), readable only by you;
/// - a notification on the Mac for what matters (a message typed into a session, an
///   unlock, a wrong code, a message from someone else), to see right away if it was not you.
enum RemoteLog {
    private typealias T = Constants.Telegram

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cube-widget/remote.log")

    private static let queue = DispatchQueue(label: "CubeWidget.remoteLog", qos: .utility)
    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Adds a line: "2026-10-28 22:15:03  ENVOYÉ  cube-widget  « le texte… »".
    static func write(_ event: String, project: String? = nil, text: String? = nil) {
        var line = dateFormat.string(from: Date()) + "  " + event
        if let project { line += "  " + project }
        if let text { line += "  « \(excerpt(text)) »" }
        line += "\n"
        queue.async { append(line) }
    }

    /// Call on `queue` only. Past `remoteLogMaxSize`, the journal becomes `remote.log.1`
    /// (the one before is removed) and a new one starts.
    private static func append(_ line: String) {
        let files = FileManager.default
        try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? files.attributesOfItem(atPath: url.path))?[.size] as? Int, size > T.remoteLogMaxSize {
            let old = url.appendingPathExtension("1")
            try? files.removeItem(at: old)
            try? files.moveItem(at: url, to: old)
        }
        if !files.fileExists(atPath: url.path) {
            files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// On one line, cut after `remoteLogExcerptLength` characters.
    private static func excerpt(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline).joined(separator: " ⏎ ")
        return flat.count > T.remoteLogExcerptLength ? flat.prefix(T.remoteLogExcerptLength) + "…" : flat
    }

    // MARK: - Notifications on the Mac

    /// Asks macOS once whether the app may show notifications (the first time, a window
    /// "Cube Hub souhaite vous envoyer des notifications" appears: answer Autoriser).
    static func requestNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationPresenter.shared
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    /// A notification, shown even while the Cube Hub is in front.
    static func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = excerpt(body)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Without it, macOS hides the app's notifications while the app is in front.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
