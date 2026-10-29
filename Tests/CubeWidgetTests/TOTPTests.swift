@testable import CubeWidget
import Foundation
import XCTest

/// The unlock code for Telegram commands (TOTP, RFC 6238).
final class TOTPTests: XCTestCase {
    /// The secret of the RFC's own examples.
    private let secret = Data("12345678901234567890".utf8)

    /// The official examples of RFC 6238 (SHA-1), last 6 digits of their 8-digit codes.
    func testOfficialExamples() {
        let examples: [(TimeInterval, String)] = [
            (59, "287082"),
            (1_111_111_109, "081804"),
            (1_111_111_111, "050471"),
            (1_234_567_890, "005924"),
            (2_000_000_000, "279037"),
            (20_000_000_000, "353130"),
        ]
        for (time, code) in examples {
            let step = TOTP.step(at: Date(timeIntervalSince1970: time))
            XCTAssertEqual(TOTP.code(secret: secret, step: step), code, "at \(time)")
        }
    }

    /// The code before or after (30 s) is accepted, not further.
    func testTolerance() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let step = TOTP.step(at: now)
        let next = TOTP.code(secret: secret, step: step + 1)
        XCTAssertEqual(TOTP.matchingStep(of: next, secret: secret, at: now, tolerance: 1), step + 1)
        let later = TOTP.code(secret: secret, step: step + 2)
        XCTAssertNil(TOTP.matchingStep(of: later, secret: secret, at: now, tolerance: 1))
        XCTAssertNil(TOTP.matchingStep(of: "abcdef", secret: secret, at: now, tolerance: 1))
    }

    func testBase32() {
        XCTAssertEqual(TOTP.base32(secret), "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    }

    func testNewSecretsAreRandom() {
        let a = TOTP.newSecret(), b = TOTP.newSecret()
        XCTAssertEqual(a.count, 20)
        XCTAssertNotEqual(a, b)
    }
}
