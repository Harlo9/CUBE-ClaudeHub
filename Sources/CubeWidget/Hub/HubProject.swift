import AppKit
import SwiftTerm

/// One project of the Claude Hub: a folder and its own terminal, where Claude runs.
///
/// The terminal stays alive when another project is shown (only its view is swapped),
/// so Claude keeps working in the background.
@MainActor
final class HubProject: ObservableObject, Identifiable {
    let id = UUID()
    let folder: URL
    let terminal: LocalProcessTerminalView
    /// Terminal device of this project (e.g. `/dev/ttys012`), known once started. The
    /// Claude session running in it reports the same `tty`: that is how the widget's
    /// cards and the Hub's projects are matched.
    @Published private(set) var tty: String?
    @Published private(set) var isRunning = false
    /// Command typed in the terminal when it starts (`claude`, `claude --continue`…).
    private let startCommand: String
    /// The terminal was started at least once.
    @Published private(set) var hasBeenStarted = false
    private let delegate = TerminalDelegate()

    var name: String { folder.lastPathComponent }

    init(folder: URL, startCommand: String) {
        self.folder = folder
        self.startCommand = startCommand
        terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        terminal.font = NSFont.monospacedSystemFont(ofSize: Constants.Hub.fontSize, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(Constants.Colors.cardBackground)
        terminal.nativeForegroundColor = NSColor(white: 0.9, alpha: 1)
        terminal.optionAsMetaKey = false   // keep ⌥ for typing characters like @ or |
        terminal.processDelegate = delegate
        delegate.onExit = { [weak self] in
            MainActor.assumeIsolated {
                self?.isRunning = false
                self?.tty = nil
            }
        }
    }

    /// Starts the shell then Claude, the first time the terminal is shown (it then has
    /// its real size, so Claude draws itself at the right width).
    func startIfNeeded() {
        guard !hasBeenStarted else { return }
        hasBeenStarted = true
        start(command: startCommand)
    }

    /// Starts again after the shell was closed (`exit`), resuming the last conversation
    /// (or running another command, like `claude --resume <id>`).
    func restart(command: String = "claude --continue") {
        guard !isRunning else { return }
        if hasBeenStarted { terminal.getTerminal().resetToInitialState() }
        hasBeenStarted = true
        start(command: command)
    }

    func stop() {
        guard isRunning else { return }
        terminal.terminate()
    }

    private func start(command: String) {
        // Your usual shell, as a login shell ("-zsh"): it reads your settings (.zprofile,
        // .zshrc), so `claude` and your PATH are found like in Terminal.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        for key in ["PATH", "SHELL", "TMPDIR"] {
            if let value = ProcessInfo.processInfo.environment[key] { environment.append("\(key)=\(value)") }
        }
        environment.append("TERM_PROGRAM=CubeWidget")
        terminal.startProcess(executable: shell, args: [], environment: environment,
                              execName: "-" + (shell as NSString).lastPathComponent,
                              currentDirectory: folder.path)
        isRunning = true
        let master = terminal.process.childfd
        if master >= 0, let name = ptsname(master) {
            tty = String(cString: name)
        }
        terminal.send(txt: command + "\r")
    }
}

/// Receives the terminal's events (the shell ended, the title changed…).
private final class TerminalDelegate: LocalProcessTerminalViewDelegate {
    var onExit: (() -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.onExit?() }
    }
}
