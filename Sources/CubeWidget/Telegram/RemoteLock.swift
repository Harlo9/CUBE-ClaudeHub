import Foundation

/// The lock of "Commandes depuis Telegram": your replies are typed into Claude only for
/// `unlockDuration` after you send `/unlock` with the six-digit code of your code app.
/// Locked again by `/lock`, when the time is up, when the switch is turned off, and when
/// the app starts (the unlock is only kept in memory).
@MainActor
final class RemoteLock: ObservableObject {
    static let shared = RemoteLock()

    private typealias T = Constants.Telegram

    enum UnlockResult {
        case unlocked(until: Date)
        /// Wrong code; this many tries are left before the commands are turned off.
        case wrong(triesLeft: Int)
        /// Right code, but already used once: wait for the next one.
        case reused
        /// Too many wrong codes: the commands were turned off.
        case blocked
        case notSetUp
    }

    /// When the commands lock again (nil: locked).
    @Published private(set) var unlockedUntil: Date?
    /// A secret is in the keychain (the code is set up).
    @Published private(set) var isSetUp: Bool
    private var failedTries = 0
    private let defaults = UserDefaults.standard
    private static let lastStepKey = "telegramUnlockLastStep"

    private init() {
        isSetUp = TelegramKeychain.unlockSecret() != nil
    }

    var isUnlocked: Bool {
        unlockedUntil.map { $0 > Date() } ?? false
    }

    /// Checks the code of `/unlock`. Each code works once (the period of the last code
    /// used is remembered), and `maxFailedCodes` wrong codes in a row turn the commands off.
    func unlock(with code: String) -> UnlockResult {
        guard let secret = TelegramKeychain.unlockSecret() else { return .notSetUp }
        let code = code.filter(\.isNumber)
        guard let step = TOTP.matchingStep(of: code, secret: secret, at: Date(), tolerance: T.codeTolerance) else {
            failedTries += 1
            guard failedTries < T.maxFailedCodes else {
                failedTries = 0
                lock()
                TelegramSettings.shared.remoteEnabled = false
                return .blocked
            }
            return .wrong(triesLeft: T.maxFailedCodes - failedTries)
        }
        guard step > Int64(defaults.integer(forKey: Self.lastStepKey)) else { return .reused }
        defaults.set(Int(step), forKey: Self.lastStepKey)
        failedTries = 0
        let until = Date().addingTimeInterval(T.unlockDuration)
        unlockedUntil = until
        return .unlocked(until: until)
    }

    func lock() {
        if unlockedUntil != nil { unlockedUntil = nil }
    }

    // MARK: - Setup

    /// Saves a new secret, only if `code` is the current code for it (proof that your code
    /// app has it). Replaces the previous secret: its codes stop working.
    func setUp(secret: Data, code: String) -> Bool {
        guard let step = TOTP.matchingStep(of: code.filter(\.isNumber), secret: secret, at: Date(),
                                           tolerance: T.codeTolerance),
              TelegramKeychain.saveUnlockSecret(secret) else { return false }
        defaults.set(Int(step), forKey: Self.lastStepKey)   // this code is used up
        failedTries = 0
        lock()
        isSetUp = true
        return true
    }
}
