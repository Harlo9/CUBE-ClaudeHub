import CryptoKit
import Foundation
import Security

/// Six-digit codes that change every 30 seconds (TOTP, RFC 6238), the same as bank or
/// Google two-factor codes. The app and your code app (Passwords on the iPhone, Google
/// Authenticator…) share a secret; each computes the code from that secret and the time.
enum TOTP {
    /// Seconds per code.
    static let period: TimeInterval = 30
    static let digits = 6

    /// A new random secret (20 bytes, the usual size for these codes).
    static func newSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            // Never a weak secret: fall back to CryptoKit's own random generator.
            return SymmetricKey(size: .init(bitCount: 160)).withUnsafeBytes { Data($0) }
        }
        return Data(bytes)
    }

    /// Number of the 30-second period a moment falls in.
    static func step(at date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / period).rounded(.down))
    }

    /// The code of one period ("042317").
    static func code(secret: Data, step: Int64) -> String {
        var counter = UInt64(bitPattern: step).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let hash = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
        // "Dynamic truncation": 4 bytes picked by the last byte, without the sign bit.
        let offset = Int(hash[hash.count - 1] & 0x0f)
        let number = (UInt32(hash[offset] & 0x7f) << 24) | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8) | UInt32(hash[offset + 3])
        let code = String(number % 1_000_000)
        return String(repeating: "0", count: digits - code.count) + code
    }

    /// The period whose code this is, around `date` (`tolerance` periods before or after,
    /// for a phone whose clock is a little off), or nil if it matches none.
    static func matchingStep(of code: String, secret: Data, at date: Date, tolerance: Int) -> Int64? {
        let now = step(at: date)
        // Every period is checked, whatever matches, so the time taken tells nothing.
        var found: Int64?
        for step in (now - Int64(tolerance))...(now + Int64(tolerance)) where isEqual(Self.code(secret: secret, step: step), code) {
            found = step
        }
        return found
    }

    /// Compares two codes in a time that does not depend on where they differ.
    private static func isEqual(_ a: String, _ b: String) -> Bool {
        let a = Array(a.utf8), b = Array(b.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// The secret written for typing by hand (Base32: letters A–Z and digits 2–7).
    static func base32(_ data: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var result = ""
        var buffer = 0, bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                result.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 { result.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return result
    }

    /// What the QR code contains: the address code apps understand ("otpauth://…").
    static func setupURL(secret: Data) -> String {
        "otpauth://totp/CubeWidget:Telegram?secret=\(base32(secret))&issuer=CubeWidget"
            + "&algorithm=SHA1&digits=\(digits)&period=\(Int(period))"
    }
}
