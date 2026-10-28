import Foundation

/// Turns Claude's answer into a few very short bullet points for the "Réponse terminée"
/// Telegram message, with a small Claude model (`claude -p`, Haiku by default).
///
/// The summary runs without tools, without hooks (no fake session appears in the widget)
/// and without saving the conversation (it never mixes with `claude --continue` in your
/// projects), in a folder of its own (no project CLAUDE.md is read). It uses a little
/// of your Claude subscription, so it only runs when a message is actually sent.
enum AnswerSummary {
    private typealias T = Constants.Telegram

    /// "• …" lines, or nil if it failed (Claude not found, too slow, odd answer).
    static func bullets(of answer: String) async -> String? {
        guard let claude = claudeExecutable else { return nil }
        let prompt = T.summaryPrompt + "\n\nRéponse :\n" + answer
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run(claude, input: prompt).flatMap(cleaned))
            }
        }
    }

    /// Where Claude Code is installed (the app does not get your shell's PATH).
    private static var claudeExecutable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    /// Runs `claude -p` with the prompt on stdin; nil on failure or after `summaryTimeout`.
    private static func run(_ claude: URL, input: String) -> String? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cube-widget-summary")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = claude
        process.arguments = ["-p", "--model", T.summaryModel, "--no-session-persistence",
                             "--tools", "", "--settings", #"{"disableAllHooks": true}"#]
        process.currentDirectoryURL = folder
        // Only the basics: the app may have been started from a Claude session, whose
        // variables would make this one think it runs inside it.
        let inherited = ProcessInfo.processInfo.environment
        process.environment = inherited.filter { ["HOME", "USER", "LOGNAME", "PATH", "LANG", "TMPDIR", "SHELL"].contains($0.key) }
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()

        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + T.summaryTimeout, execute: timeout)
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return String(data: output, encoding: .utf8)
    }

    /// Keeps only the bullet lines ("•", "-" or "*"), written "• …", at most `summaryMaxBullets`.
    private static func cleaned(_ output: String) -> String? {
        let bullets = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("•") || $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            .map { "• " + $0.drop { "•-* ".contains($0) }.replacingOccurrences(of: "**", with: "") }
            .prefix(T.summaryMaxBullets)
        return bullets.isEmpty ? nil : bullets.joined(separator: "\n")
    }
}
