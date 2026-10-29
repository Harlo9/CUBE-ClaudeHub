@testable import CubeWidget
import Foundation
import SessionFile
import XCTest

/// The order of the widget's cards: which session is in front, which ones below.
@MainActor
final class SessionBoardTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// Sounds the board asked for (none really plays in the tests).
    private var sounds: [SoundPlayer.Sound] = []

    private func makeBoard() -> SessionBoard {
        let board = SessionBoard()
        board.cueActiveSound = { [weak self] sound in self?.sounds.append(sound) }
        return board
    }

    /// A session as read from its file. `minute` sets when it last moved.
    private func snapshot(_ id: String, _ status: SessionFile.Status, minute: Double,
                          prompt: Double? = nil) -> SessionStore.Snapshot {
        let at = start.addingTimeInterval(minute * 60)
        var file = SessionFile(sessionID: id, cwd: "/tmp/\(id)", transcriptPath: nil,
                               status: status, startedAt: start, now: at)
        file.lastPromptAt = prompt.map { start.addingTimeInterval($0 * 60) }
        return SessionStore.Snapshot(file: file, contextTokens: nil)
    }

    private func ids(_ board: SessionBoard) -> [String] { board.sessions.map(\.id) }

    // MARK: - At launch

    func testLaunchShowsTheLatestActivityInFront() {
        let board = makeBoard()
        board.applyRealSessions([snapshot("a", .done, minute: 1), snapshot("b", .done, minute: 5)])
        XCTAssertEqual(board.active?.id, "b")
        XCTAssertTrue(sounds.isEmpty, "sessions already open make no sound at launch")
    }

    /// Messages sent before the app started do not change the front card.
    func testOldMessagesChangeNothingAtLaunch() {
        let board = makeBoard()
        board.applyRealSessions([snapshot("a", .working, minute: 1, prompt: 1),
                                 snapshot("b", .done, minute: 5)])
        XCTAssertEqual(board.active?.id, "b")
    }

    // MARK: - Cards below

    func testWaitingSessionsComeFirstBelow() {
        let board = makeBoard()
        board.applyRealSessions([snapshot("front", .working, minute: 10),
                                 snapshot("recent", .done, minute: 8),
                                 snapshot("waiting", .waiting, minute: 2)])
        XCTAssertEqual(ids(board), ["front", "waiting", "recent"])
    }

    func testActiveSessionEndingBringsTheNextCard() {
        let board = makeBoard()
        board.applyRealSessions([snapshot("a", .working, minute: 10), snapshot("b", .done, minute: 5),
                                 snapshot("c", .done, minute: 1)])
        XCTAssertEqual(board.active?.id, "a")
        board.applyRealSessions([snapshot("b", .done, minute: 5), snapshot("c", .done, minute: 1)])
        XCTAssertEqual(board.active?.id, "b")
    }

    func testActivateBringsACardToTheFront() {
        let board = makeBoard()
        board.applyRealSessions([snapshot("a", .working, minute: 10), snapshot("b", .done, minute: 5)])
        board.activate("b")
        XCTAssertEqual(ids(board), ["b", "a"])
    }

    // MARK: - Following your messages

    func testMessageBringsItsSessionToTheFront() {
        let board = makeBoard()
        board.applyRealSessions([snapshot("a", .done, minute: 10), snapshot("b", .done, minute: 5)])
        XCTAssertEqual(board.active?.id, "a")

        board.applyRealSessions([snapshot("a", .done, minute: 10), snapshot("b", .working, minute: 11, prompt: 11)])
        XCTAssertEqual(board.active?.id, "b")
        // It starts like the active project you answer: entrance with the "bosse" sound.
        XCTAssertEqual(sounds, [.working])
    }

    /// The same message is followed once: choosing another card afterwards sticks.
    func testSameMessageIsFollowedOnce() {
        let board = makeBoard()
        board.applyRealSessions([snapshot("a", .done, minute: 10), snapshot("b", .done, minute: 5)])
        let afterMessage = [snapshot("a", .done, minute: 10), snapshot("b", .working, minute: 11, prompt: 11)]
        board.applyRealSessions(afterMessage)
        board.activate("a")
        board.applyRealSessions(afterMessage)
        XCTAssertEqual(board.active?.id, "a")
    }

    /// With messages to two sessions at once, the latest one wins.
    func testLatestMessageWins() {
        let board = makeBoard()
        board.applyRealSessions([snapshot("a", .done, minute: 10), snapshot("b", .done, minute: 5),
                                 snapshot("c", .done, minute: 1)])
        board.applyRealSessions([snapshot("a", .done, minute: 10),
                                 snapshot("b", .working, minute: 12, prompt: 12),
                                 snapshot("c", .working, minute: 11, prompt: 11)])
        XCTAssertEqual(board.active?.id, "b")
    }

    /// Claude working again by itself (no message from you) keeps the front card.
    func testWorkWithoutMessageKeepsTheFrontCard() {
        let board = makeBoard()
        board.applyRealSessions([snapshot("a", .done, minute: 10), snapshot("b", .done, minute: 5)])
        board.applyRealSessions([snapshot("a", .done, minute: 10), snapshot("b", .working, minute: 11)])
        XCTAssertEqual(board.active?.id, "a")
    }

    // MARK: - The cube

    func testCubeMood() {
        let board = makeBoard()
        XCTAssertEqual(board.cubeMood, .sleeping)
        board.applyRealSessions([snapshot("a", .waiting, minute: 1)])
        XCTAssertEqual(board.cubeMood, .waiting)
        board.applyRealSessions([snapshot("a", .working, minute: 2)])
        XCTAssertEqual(board.cubeMood, .working)
    }
}
