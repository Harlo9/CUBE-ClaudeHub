import Foundation
import SessionFile

/// Reads the session files written by `cube-hook` in ~/.cube-widget/sessions and reports
/// every change.
///
/// The folder is watched by the system (an event as soon as a file is added, replaced or
/// removed), and also re-read every few seconds, to notice a session whose Claude Code
/// process died without `SessionEnd` (terminal closed): its file is then removed.
/// All the reading happens on a background queue, so it never slows the animations.
final class SessionStore: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        let file: SessionFile
        /// Current context size, read in the conversation file (nil if unknown).
        let contextTokens: Int?
    }

    /// Called on the background queue with the full list, only when something changed.
    /// Set it before `start()`.
    var onChange: (([Snapshot]) -> Void)?

    private typealias C = Constants.Sessions

    // Everything below is only used on `queue`.
    private let queue = DispatchQueue(label: "CubeWidget.sessions", qos: .utility)
    private var folderWatch: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var lastSnapshots: [Snapshot]?
    private var tokenCache: [String: (size: UInt64, modified: Date, tokens: Int?)] = [:]

    /// Reads the sessions right now (used once at launch, before anything is shown).
    func loadNow() -> [Snapshot] {
        queue.sync { reload(notify: false) }
    }

    /// Starts watching the folder.
    func start() {
        queue.async { [self] in
            watchFolder()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + C.refreshInterval, repeating: C.refreshInterval)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                if self.folderWatch == nil { self.watchFolder() }
                self.reload(notify: true)
            }
            timer.resume()
            self.timer = timer
            reload(notify: true)
        }
    }

    /// Reads the folder again right away (when the Mac wakes up: sessions closed during
    /// the sleep are cleaned up without waiting for the next tick).
    func refreshNow() {
        queue.async { [self] in
            if folderWatch == nil { watchFolder() }
            reload(notify: true)
        }
    }

    // MARK: - Folder

    /// Asks the system to tell us when the folder's content changes.
    private func watchFolder() {
        let folder = SessionFiles.sessionsDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // The folder itself was removed or renamed: watch it again on the next tick.
            if source.data.contains(.delete) || source.data.contains(.rename) {
                source.cancel()
                self.folderWatch = nil
            }
            self.reload(notify: true)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        folderWatch = source
    }

    @discardableResult
    private func reload(notify: Bool) -> [Snapshot] {
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(at: SessionFiles.sessionsDirectory,
                                                        includingPropertiesForKeys: nil)) ?? []
        let decoder = SessionFiles.decoder()
        var snapshots: [Snapshot] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let file = try? decoder.decode(SessionFile.self, from: data) else { continue }
            guard isAlive(file) else {
                // Claude Code is gone without saying so: forget this session.
                try? fileManager.removeItem(at: url)
                continue
            }
            snapshots.append(Snapshot(file: file, contextTokens: contextTokens(for: file)))
        }
        snapshots.sort { $0.file.sessionID < $1.file.sessionID }
        if notify, snapshots != lastSnapshots {
            onChange?(snapshots)
        }
        lastSnapshots = snapshots
        return snapshots
    }

    /// The Claude Code process still exists. Without a known PID, a session is kept
    /// until it has been silent for a long time.
    private func isAlive(_ file: SessionFile) -> Bool {
        guard let pid = file.pid else {
            return Date().timeIntervalSince(file.updatedAt) < C.forgetSilentSessionAfter
        }
        // Signal 0 sends nothing: it only checks that the process exists.
        return kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Tokens

    /// Context size of the session, re-read only when the conversation file changed.
    private func contextTokens(for file: SessionFile) -> Int? {
        guard let path = file.transcriptPath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        if let cached = tokenCache[path], cached.size == size, cached.modified == modified {
            return cached.tokens
        }
        // If the last answer cannot be read, keep the previous count.
        let tokens = Self.readContextTokens(path: path, size: size) ?? tokenCache[path]?.tokens
        tokenCache[path] = (size, modified, tokens)
        return tokens
    }

    /// Reads the end of the conversation file and finds Claude's last answer (not one
    /// of a subagent). Its `usage` gives the size of the context sent to Claude:
    /// new tokens + tokens written to the cache + tokens read from the cache.
    private static func readContextTokens(path: String, size: UInt64) -> Int? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let start = size > C.transcriptTailBytes ? size - C.transcriptTailBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }

        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            // Quick filter before decoding the JSON of the line.
            guard line.count > 20, line.range(of: Data("\"assistant\"".utf8)) != nil,
                  let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  entry["type"] as? String == "assistant",
                  entry["isSidechain"] as? Bool != true,
                  let usage = (entry["message"] as? [String: Any])?["usage"] as? [String: Any]
            else { continue }
            let parts = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            return parts.reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
        }
        return nil
    }
}
