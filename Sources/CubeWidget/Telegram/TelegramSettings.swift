import Foundation

/// Everything about Telegram notifications, shared by the menu bar, the widget and the
/// setup window (one object, so they always show the same thing). Remembered in the app's
/// settings, except the bot token, which lives in the keychain (`TelegramKeychain`).
@MainActor
final class TelegramSettings: ObservableObject {
    static let shared = TelegramSettings()

    private let defaults = UserDefaults.standard

    /// The general switch: off cuts every message, whatever the projects' settings.
    /// Off until you turn it on.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    /// "Toujours envoyer": messages go even when you are at the Mac.
    @Published var alwaysSend: Bool {
        didSet { defaults.set(alwaysSend, forKey: Keys.alwaysSend) }
    }
    /// The bot's @name, shown in the setup window (nil: no token saved).
    @Published private(set) var botName: String?
    /// Your conversation with the bot, found with `getUpdates`.
    @Published private(set) var chatID: Int64?
    @Published private(set) var chatName: String?
    /// Per project (key: the project's folder path): true = messages on. A project not
    /// in the list yet follows `isOnForNewProjects`.
    @Published private(set) var projects: [String: Bool] {
        didSet { defaults.set(projects, forKey: Keys.projects) }
    }
    /// "Activer par défaut pour les nouveaux projets" (off by default).
    @Published var isOnForNewProjects: Bool {
        didSet { defaults.set(isOnForNewProjects, forKey: Keys.onForNewProjects) }
    }
    /// "Commandes depuis Telegram": your replies to the bot's messages are typed into the
    /// matching Cube Hub session. Off until you turn it on.
    @Published var remoteEnabled: Bool {
        didSet { defaults.set(remoteEnabled, forKey: Keys.remoteEnabled) }
    }
    /// Projects whose session accepts your replies from Telegram (keys: folder paths).
    /// None at first, new projects included: each one is allowed by hand, on the Mac only.
    @Published private(set) var remoteProjects: Set<String> {
        didSet { defaults.set(remoteProjects.sorted(), forKey: Keys.remoteProjects) }
    }
    /// Why the last message could not be sent (shown in the menu), nil once one goes through.
    @Published private(set) var lastError: String?

    private init() {
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        alwaysSend = defaults.bool(forKey: Keys.alwaysSend)
        remoteEnabled = defaults.bool(forKey: Keys.remoteEnabled)
        remoteProjects = Set(defaults.stringArray(forKey: Keys.remoteProjects) ?? [])
        projects = defaults.dictionary(forKey: Keys.projects) as? [String: Bool] ?? [:]
        isOnForNewProjects = defaults.bool(forKey: Keys.onForNewProjects)
        botName = defaults.string(forKey: Keys.botName)
        chatID = (defaults.object(forKey: Keys.chatID) as? NSNumber)?.int64Value
        chatName = defaults.string(forKey: Keys.chatName)
        // The token may have been removed from the keychain by hand.
        if TelegramKeychain.token() == nil { botName = nil }
    }

    /// A token and a conversation: messages can be sent.
    var isConfigured: Bool { botName != nil && chatID != nil }

    // MARK: - Projects

    /// The same folder always gives the same key (no "..", no trailing "/").
    static func key(for folder: URL) -> String {
        folder.standardizedFileURL.path
    }

    func isOn(for folder: URL) -> Bool {
        projects[Self.key(for: folder)] ?? isOnForNewProjects
    }

    func setOn(_ isOn: Bool, for folder: URL) {
        projects[Self.key(for: folder)] = isOn
    }

    func toggle(_ folder: URL) {
        setOn(!isOn(for: folder), for: folder)
    }

    /// Projects seen for the first time join the list "Telegram par projet", on or off
    /// depending on "Activer par défaut pour les nouveaux projets" at that moment.
    func noteProjects(_ folders: [URL]) {
        let new = folders.map(Self.key(for:)).filter { projects[$0] == nil }
        guard !new.isEmpty else { return }
        var updated = projects
        for key in new { updated[key] = isOnForNewProjects }
        projects = updated
    }

    // MARK: - Commands, per project

    func isRemoteAllowed(for folder: URL) -> Bool {
        remoteProjects.contains(Self.key(for: folder))
    }

    func setRemoteAllowed(_ isAllowed: Bool, for folder: URL) {
        if isAllowed {
            remoteProjects.insert(Self.key(for: folder))
        } else {
            remoteProjects.remove(Self.key(for: folder))
        }
    }

    // MARK: - Setup

    /// Checks the token with Telegram, then keeps it in the keychain.
    func saveToken(_ token: String) async throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let bot = try await TelegramClient.bot(token: token)
        guard TelegramKeychain.save(token) else { throw TelegramError.server("trousseau inaccessible") }
        botName = bot.username
        defaults.set(bot.username, forKey: Keys.botName)
        forgetChat()   // a new bot means a new conversation
        lastError = nil
    }

    func deleteToken() {
        TelegramKeychain.delete()
        botName = nil
        defaults.removeObject(forKey: Keys.botName)
        forgetChat()
        lastError = nil
    }

    /// Looks for your message to the bot. Returns true once the conversation is found.
    func detectChat() async throws -> Bool {
        guard let token = TelegramKeychain.token() else { throw TelegramError.badToken }
        guard let chat = try await TelegramClient.latestChat(token: token) else { return false }
        chatID = chat.id
        chatName = chat.name
        defaults.set(NSNumber(value: chat.id), forKey: Keys.chatID)
        defaults.set(chat.name, forKey: Keys.chatName)
        return true
    }

    func forgetChat() {
        chatID = nil
        chatName = nil
        defaults.removeObject(forKey: Keys.chatID)
        defaults.removeObject(forKey: Keys.chatName)
    }

    // MARK: - Sending

    /// Sends a message to your conversation and returns its number, or nil if it failed.
    /// Never throws: a failure is remembered in `lastError` (shown in the menu) and the
    /// app carries on.
    @discardableResult
    func send(_ text: String, isHTML: Bool = false, replyTo: Int? = nil, askReply: String? = nil,
              buttons: [[TelegramClient.Button]]? = nil) async -> Int? {
        guard let chatID, let token = TelegramKeychain.token() else {
            lastError = "Telegram n'est pas configuré"
            return nil
        }
        do {
            let messageID = try await TelegramClient.send(text, to: chatID, token: token, isHTML: isHTML,
                                                          replyTo: replyTo, askReply: askReply, buttons: buttons)
            lastError = nil
            return messageID ?? 0
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private enum Keys {
        static let enabled = "telegramEnabled"
        static let botName = "telegramBotName"
        static let chatID = "telegramChatID"
        static let chatName = "telegramChatName"
        static let projects = "telegramProjects"
        static let onForNewProjects = "telegramOnForNewProjects"
        static let alwaysSend = "telegramAlwaysSend"
        static let remoteEnabled = "telegramRemoteEnabled"
        static let remoteProjects = "telegramRemoteProjects"
    }
}
