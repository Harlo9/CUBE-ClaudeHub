import Foundation
import Security

/// The Telegram secrets, kept in the macOS keychain (the system's safe for passwords),
/// never in the code, a file or the app's settings. Only this app can read them back:
/// the bot token, and the secret of the unlock codes ("Commandes depuis Telegram").
enum TelegramKeychain {
    private static let service = "com.cubewidget.telegram"
    private static let tokenAccount = "bot-token"
    private static let unlockAccount = "unlock-secret"

    /// The saved token, or nil if there is none.
    static func token() -> String? {
        read(tokenAccount).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Saves the token, replacing the previous one. Returns false if the keychain refused.
    @discardableResult
    static func save(_ token: String) -> Bool {
        write(Data(token.utf8), to: tokenAccount)
    }

    static func delete() {
        remove(tokenAccount)
    }

    /// The secret shared with your code app (TOTP), or nil if it is not set up.
    static func unlockSecret() -> Data? {
        read(unlockAccount)
    }

    @discardableResult
    static func saveUnlockSecret(_ secret: Data) -> Bool {
        write(secret, to: unlockAccount)
    }

    static func deleteUnlockSecret() {
        remove(unlockAccount)
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func write(_ data: Data, to account: String) -> Bool {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query(account)
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func remove(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
