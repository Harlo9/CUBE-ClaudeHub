import Foundation
import SessionFile
import XCTest

/// The session files written by cube-hook and read by the app.
final class SessionFileTests: XCTestCase {
    /// A file written before the newer fields existed (answer, permission, question,
    /// last message) is still read: those fields are just missing.
    func testOldFileStillDecodes() throws {
        let json = """
        {
          "version": 1,
          "sessionID": "abc-123",
          "cwd": "/Users/me/Projets/Site",
          "status": "working",
          "startedAt": "2026-10-01T10:00:00Z",
          "updatedAt": "2026-10-01T10:05:00Z",
          "statusChangedAt": "2026-10-01T10:05:00Z",
          "tasks": []
        }
        """
        let file = try SessionFiles.decoder().decode(SessionFile.self, from: Data(json.utf8))
        XCTAssertEqual(file.sessionID, "abc-123")
        XCTAssertEqual(file.status, .working)
        XCTAssertNil(file.lastAnswer)
        XCTAssertNil(file.pendingPermission)
        XCTAssertNil(file.pendingQuestion)
        XCTAssertNil(file.lastPromptAt)
    }

    /// What is written is read back the same.
    func testRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var file = SessionFile(sessionID: "s1", cwd: "/tmp/projet", transcriptPath: nil,
                               status: .waiting, startedAt: now, now: now)
        file.lastPromptAt = now
        file.pendingQuestion = .init(items: [.init(question: "Quelle couleur ?", header: "Couleur",
                                                   options: ["Violet", "Rose"], multiSelect: false)],
                                     at: now)
        let data = try SessionFiles.encoder().encode(file)
        XCTAssertEqual(try SessionFiles.decoder().decode(SessionFile.self, from: data), file)
    }

    func testFileURLUsesTheSessionID() {
        XCTAssertEqual(SessionFiles.url(forSession: "s1").lastPathComponent, "s1.json")
    }
}
