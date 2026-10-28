import Foundation

/// Brings a session's Terminal tab to the front.
///
/// Uses AppleScript (the macOS language that lets an app drive another one): Terminal
/// goes through its windows and tabs, selects the one whose terminal device (`tty`)
/// matches, and comes to the front. The script runs in `osascript`, a separate small
/// program, so the widget never freezes while Terminal answers (or while macOS asks
/// for the permission, the first time).
enum TerminalFocus {
    private static let script = """
    on run argv
        set targetTTY to item 1 of argv
        if application "Terminal" is not running then return "not running"
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is targetTTY then
                        if miniaturized of w then set miniaturized of w to false
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "not found"
    end run
    """

    /// - Parameter tty: e.g. `/dev/ttys009`. Does nothing if no Terminal tab has it
    ///   (the session may run in another app, like VS Code).
    static func focus(tty: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, tty]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
