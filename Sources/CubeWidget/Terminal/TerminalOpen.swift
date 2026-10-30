import AppKit

/// Opens a new Terminal window in a project's folder, right next to the Hub window
/// (for `git`, `npm`…: Claude is not started there).
///
/// AppleScript again, like `TerminalFocus` (same permission, "Cube Hub souhaite contrôler
/// Terminal"): Terminal opens a new window at its usual size (80 x 24 by default), goes
/// to the folder (`cd`), and the window is moved next to the Hub, level with its top.
/// Run in `osascript`, so the Hub never freezes.
enum TerminalOpen {
    private static let script = """
    on run argv
        set folderPath to item 1 of argv
        set cdLine to "cd " & quoted form of folderPath & " && clear"
        if application "Terminal" is running then
            tell application "Terminal" to do script cdLine
        else
            tell application "Terminal"
                activate
                -- Launching opens its own first window: use it rather than a second one.
                repeat 50 times
                    if (count of windows) > 0 then exit repeat
                    delay 0.1
                end repeat
                do script cdLine in window 1
            end tell
        end if
        tell application "Terminal"
            if (count of argv) is 7 then
                set {hubLeft, hubTop, hubRight, roomLeft, roomRight, gap} to ¬
                    {item 2 of argv as integer, item 3 of argv as integer, item 4 of argv as integer, ¬
                    item 5 of argv as integer, item 6 of argv as integer, item 7 of argv as integer}
                -- Keep Terminal's own size: only the place changes.
                set {l, t, r, b} to bounds of front window
                set {w, h} to {r - l, b - t}
                -- Right against the Hub, or left of it when there is no room, else at the
                -- right edge of the screen.
                set x to hubRight + gap
                if x + w > roomRight then
                    if hubLeft - gap - w >= roomLeft then
                        set x to hubLeft - gap - w
                    else
                        set x to roomRight - w
                    end if
                end if
                set bounds of front window to {x, hubTop, x + w, hubTop + h}
            end if
            activate
        end tell
    end run
    """

    /// - Parameter window: the Hub window, to put the new one next to it.
    static func open(_ folder: URL, besides window: NSWindow?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, folder.path] + place(besides: window).map { String(Int($0.rounded())) }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// What the script needs to place the window (its size is only known once open):
    /// the Hub's left, top and right, the screen's usable left and right, and the gap.
    /// AppleScript measures from the top left of the main screen (macOS from its bottom).
    private static func place(besides window: NSWindow?) -> [CGFloat] {
        guard let window, let screen = window.screen, let main = NSScreen.screens.first else { return [] }
        let hub = window.frame, room = screen.visibleFrame
        return [hub.minX, main.frame.maxY - hub.maxY, hub.maxX, room.minX, room.maxX, Constants.Hub.openTerminalGap]
    }
}
