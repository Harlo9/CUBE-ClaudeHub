import Foundation
import SessionFile
import XCTest

/// Runs the real cube-hook program with fake Claude Code events, in a temporary folder
/// (`CUBE_WIDGET_DIR`), and checks the session file it writes.
final class CubeHookTests: XCTestCase {
    private var directory: URL!
    private let sessionID = "test-session"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cube-hook-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.isExecutableFile(atPath: Self.hookURL.path) else {
            // On GitHub (`CI` is set there), a missing program is a failure, not a skip.
            if ProcessInfo.processInfo.environment["CI"] != nil { throw MissingHook() }
            throw XCTSkip("cube-hook is not built (run `swift build` first)")
        }
    }

    private struct MissingHook: Error {}

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The test bundle sits next to the built programs (`.build/<configuration>/`).
    private static var hookURL: URL {
        Bundle(for: CubeHookTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("cube-hook")
    }

    // MARK: - Helpers

    /// Sends one event to cube-hook, as Claude Code does, and returns its exit code.
    @discardableResult
    private func send(_ event: [String: Any]) throws -> Int32 {
        var event = event
        event["session_id"] = event["session_id"] ?? sessionID
        event["cwd"] = event["cwd"] ?? "/tmp/projet-test"
        return try run(input: JSONSerialization.data(withJSONObject: event))
    }

    private func run(input: Data) throws -> Int32 {
        let process = Process()
        process.executableURL = Self.hookURL
        process.environment = ["CUBE_WIDGET_DIR": directory.path]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        // It must never print anything: some events add stdout to Claude's context.
        XCTAssertTrue(stdout.fileHandleForReading.readDataToEndOfFile().isEmpty, "cube-hook printed something")
        return process.terminationStatus
    }

    private var fileURL: URL {
        directory.appendingPathComponent("sessions/\(sessionID).json")
    }

    private func session() throws -> SessionFile {
        try SessionFiles.decoder().decode(SessionFile.self, from: Data(contentsOf: fileURL))
    }

    // MARK: - Status

    func testStatusFollowsTheEvents() throws {
        try send(["hook_event_name": "SessionStart", "source": "startup"])
        XCTAssertEqual(try session().status, .done)
        XCTAssertEqual(try session().cwd, "/tmp/projet-test")

        try send(["hook_event_name": "UserPromptSubmit", "prompt": "Salut"])
        XCTAssertEqual(try session().status, .working)

        try send(["hook_event_name": "Notification", "notification_type": "permission_prompt"])
        XCTAssertEqual(try session().status, .waiting)

        try send(["hook_event_name": "PostToolUse", "tool_name": "Bash"])
        XCTAssertEqual(try session().status, .working)

        try send(["hook_event_name": "Stop", "last_assistant_message": "  C'est fait.  "])
        let done = try session()
        XCTAssertEqual(done.status, .done)
        XCTAssertEqual(done.lastAnswer?.excerpt, "C'est fait.")
    }

    /// `idle_prompt` (a minute after an answer) changes nothing.
    func testIdlePromptChangesNothing() throws {
        try send(["hook_event_name": "Stop", "last_assistant_message": "Fini"])
        try send(["hook_event_name": "Notification", "notification_type": "idle_prompt"])
        XCTAssertEqual(try session().status, .done)
    }

    func testPlanToApproveWaits() throws {
        try send(["hook_event_name": "PreToolUse", "tool_name": "ExitPlanMode"])
        XCTAssertEqual(try session().status, .waiting)
    }

    // MARK: - Your messages

    func testMessageRecordsItsTime() throws {
        try send(["hook_event_name": "SessionStart"])
        XCTAssertNil(try session().lastPromptAt)
        try send(["hook_event_name": "UserPromptSubmit", "prompt": "Salut"])
        XCTAssertNotNil(try session().lastPromptAt)
    }

    /// Claude working again by itself (a tool) is not a message from you.
    func testToolUseIsNotAMessage() throws {
        try send(["hook_event_name": "PreToolUse", "tool_name": "Bash"])
        XCTAssertNil(try session().lastPromptAt)
    }

    // MARK: - Permissions and questions (Telegram)

    func testPermissionIsKeptUntilTheSessionMovesOn() throws {
        try send(["hook_event_name": "PermissionRequest", "tool_name": "Bash",
                  "tool_input": ["command": "touch notes.txt", "description": "Créer le fichier"]])
        let waiting = try session()
        XCTAssertEqual(waiting.status, .waiting)
        XCTAssertEqual(waiting.pendingPermission?.tool, "Bash")
        XCTAssertEqual(waiting.pendingPermission?.detail, "touch notes.txt")
        XCTAssertEqual(waiting.pendingPermission?.description, "Créer le fichier")

        try send(["hook_event_name": "PostToolUse", "tool_name": "Bash"])
        XCTAssertNil(try session().pendingPermission)
    }

    /// A question also comes as a permission request: it is never kept as a permission
    /// (no Oui / Non buttons on a question).
    func testQuestionIsKeptAsAQuestion() throws {
        let input: [String: Any] = ["questions": [[
            "question": "Quelle couleur ?", "header": "Couleur", "multiSelect": false,
            "options": [["label": "Violet", "description": "Doux"], ["label": "Rose", "description": "Vif"]],
        ]]]
        try send(["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "tool_input": input])
        try send(["hook_event_name": "PermissionRequest", "tool_name": "AskUserQuestion", "tool_input": input])
        let waiting = try session()
        XCTAssertEqual(waiting.status, .waiting)
        XCTAssertNil(waiting.pendingPermission)
        let item = try XCTUnwrap(waiting.pendingQuestion?.items.first)
        XCTAssertEqual(item.question, "Quelle couleur ?")
        XCTAssertEqual(item.header, "Couleur")
        XCTAssertEqual(item.options, ["Violet", "Rose"])
        XCTAssertFalse(item.multiSelect)

        try send(["hook_event_name": "PostToolUse", "tool_name": "AskUserQuestion"])
        XCTAssertNil(try session().pendingQuestion)
    }

    // MARK: - Tasks

    func testTasksAndCompletion() throws {
        try send(["hook_event_name": "TaskCreated", "task_id": "1", "task_subject": "Écrire les tests"])
        try send(["hook_event_name": "PostToolUse", "tool_name": "TaskUpdate",
                  "tool_input": ["taskId": "1", "status": "in_progress"],
                  "tool_response": ["statusChange": ["from": "pending", "to": "in_progress"]]])
        XCTAssertEqual(try session().tasks.first?.status, "in_progress")

        try send(["hook_event_name": "TaskCompleted", "task_id": "1", "task_subject": "Écrire les tests"])
        XCTAssertEqual(try session().lastCompletedTask?.subject, "Écrire les tests")
    }

    // MARK: - End and bad input

    func testSessionEndRemovesTheFile() throws {
        try send(["hook_event_name": "SessionStart"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        try send(["hook_event_name": "SessionEnd", "reason": "prompt_input_exit"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// Anything it does not understand is ignored, and it always exits with 0 (2 would
    /// block Claude Code).
    func testBadInputIsIgnored() throws {
        XCTAssertEqual(try run(input: Data("pas du JSON".utf8)), 0)
        XCTAssertEqual(try run(input: Data()), 0)
        // A session ID that could escape the folder is refused.
        XCTAssertEqual(try send(["hook_event_name": "SessionStart", "session_id": "../evil"]), 0)
        let written = (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("sessions").path)) ?? []
        XCTAssertTrue(written.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("evil.json").path))
    }
}
