import AppKit
import Combine
import SwiftUI

/// The Cube Hub window.
///
/// The app normally has no Dock icon (it is an "accessory"). While the Hub is open it
/// becomes a normal app: Dock icon, ⌘Tab, and a menu bar with Copy / Paste, which the
/// terminal needs for ⌘C / ⌘V. Closing the window only hides it: the terminals (and
/// the Claude sessions in them) keep running.
@MainActor
final class HubWindowController: NSObject, NSWindowDelegate {
    let hub = HubModel()
    private let board: SessionBoard
    private var window: NSWindow?
    private var observers: Set<AnyCancellable> = []
    /// Opens the Réglages window (the gear, ⌘,).
    var onOpenSettings: (() -> Void)?

    init(board: SessionBoard) {
        self.board = board
        super.init()
        // Choosing a session in the list brings its card to the front of the widget
        // (not the selection restored at launch).
        hub.$selection
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] selection in
                // After the list's own update, which is changing the selection right now.
                DispatchQueue.main.async { self?.bringToFront(selection) }
            }
            .store(in: &observers)
    }

    private func bringToFront(_ selection: HubModel.Selection?) {
        let id: Session.ID?
        switch selection {
        case .session(let sessionID):
            id = sessionID
        case .project(let projectID):
            id = board.session(onTTY: hub.projects.first { $0.id == projectID }?.tty)?.id
        case nil:
            id = nil
        }
        guard let id else { return }
        withAnimation(.smooth(duration: Constants.BackCard.swapAnimationDuration)) {
            board.activate(id)
        }
    }

    /// Shows the Hub, on a given project if any.
    func show(project: HubProject? = nil) {
        if let project {
            hub.selectedID = project.id
        } else if hub.selection == nil, let active = board.active {
            // Nothing chosen yet: the widget's front card.
            hub.selection = hub.project(forTTY: active.tty).map { .project($0.id) } ?? .session(active.id)
        }
        revealSelection()
        // Opens like any app: CubeWidget first becomes a regular app (Dock icon, menu bar),
        // then comes to the front. As a widget-only ("accessory") app, macOS would let the
        // window float over the app you are in, even a full-screen one; as a regular app,
        // the window stays on a normal desktop and macOS takes you there.
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = HubMenu.make(target: self)
        let window = self.window ?? makeWindow()
        // Once the new activation policy is in place.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Shows a session from the widget in the Hub: its terminal if it runs in the Hub,
    /// otherwise its page with "Afficher dans Terminal" / "Ramener dans le Hub".
    /// Without a session, simply opens the Hub.
    func open(_ session: Session?) {
        if let project = hub.project(forTTY: session?.tty) {
            show(project: project)
        } else {
            if let session { hub.selection = .session(session.id) }
            show()
        }
    }

    /// Moves a session running in Terminal into the Hub: Claude is closed there (like
    /// quitting it, Terminal goes back to its prompt), then the same conversation resumes
    /// here. Only once Claude has finished its answer, so no work is cut off.
    func bringIntoHub(_ session: Session) {
        guard session.status == .done, let pid = session.pid, let folder = session.folder,
              session.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              Self.isClaudeCode(pid), kill(pid, SIGTERM) == 0 else { return }
        Task { @MainActor in
            // Wait for Claude to quit (at most 3 s), so both never write the same conversation.
            for _ in 0..<30 where kill(pid, 0) == 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            hub.resume(sessionID: session.id, in: folder)
            show()
        }
    }

    /// The process is still Claude Code (its program is in `…/claude/versions/`), not
    /// another process that got the same number since.
    static func isClaudeCode(_ pid: Int32) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return String(cString: buffer).contains("/claude/versions/")
    }

    /// Asks for a folder, then opens a new project with Claude in it.
    @objc func newProject() {
        show()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Lancer Claude ici"
        panel.message = "Choisis le dossier du projet"
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            MainActor.assumeIsolated { _ = self?.hub.open(folder: folder) }
        }
    }

    @objc func closeSelectedProject() {
        if let project = hub.selected { hub.close(project) }
    }

    @objc func selectNextProject() { moveSelection(by: 1) }
    @objc func selectPreviousProject() { moveSelection(by: -1) }

    /// Goes through the list in its order, theme by theme, skipping folded themes.
    private func moveSelection(by step: Int) {
        let items = sections().filter { !$0.isCollapsed }.flatMap(\.items).map(\.selection)
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0 == hub.selection } ?? 0
        hub.selection = items[(index + step + items.count) % items.count]
    }

    private func sections() -> [HubModel.Section] {
        hub.sections(outside: board.sessions.filter { hub.project(forTTY: $0.tty) == nil })
    }

    /// Unfolds the theme of the selected card, so it is visible in the list.
    private func revealSelection() {
        guard let selection = hub.selection,
              let item = sections().flatMap(\.items).first(where: { $0.selection == selection }) else { return }
        hub.themes.reveal(key: item.key)
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Constants.Hub.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Cube Hub"
        window.appearance = NSAppearance(named: .darkAqua)   // black design, even in light mode
        window.isReleasedWhenClosed = false
        // A normal app window: on one desktop, and it can go full screen itself.
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.delegate = self
        window.contentView = NSHostingView(rootView: HubView(
            hub: hub, board: board,
            onNewProject: { [weak self] in self?.newProject() },
            onBringIntoHub: { [weak self] session in self?.bringIntoHub(session) },
            onOpenSettings: { [weak self] in self?.openSettings() }))
        window.center()
        window.setFrameAutosaveName("ClaudeHub")   // remembers its size and position (old name kept, so the saved frame stays)
        self.window = window
        return window
    }

    /// macOS tells when the window starts or stops being visible on screen.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        hub.isOnScreen = window?.occlusionState.contains(.visible) ?? false
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a widget-only app (no Dock icon, no menu bar), unless Réglages is open.
        AppWindows.becomeAccessoryIfNoWindow(besides: window)
    }

    @objc func openSettings() {
        onOpenSettings?()
    }
}

/// The menu bar shown while the Hub is open.
enum HubMenu {
    @MainActor
    static func make(target: HubWindowController) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "Cube Hub")
        app.addItem(item("Réglages…", #selector(HubWindowController.openSettings), ",", target))
        app.addItem(.separator())
        app.addItem(withTitle: "Masquer Cube Hub", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quitter Cube Hub", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, to: main)

        let file = NSMenu(title: "Projet")
        file.addItem(item("Nouveau projet…", #selector(HubWindowController.newProject), "n", target))
        file.addItem(item("Fermer le projet", #selector(HubWindowController.closeSelectedProject), "w",
                          target, modifiers: [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("Projet suivant", #selector(HubWindowController.selectNextProject), "]", target))
        file.addItem(item("Projet précédent", #selector(HubWindowController.selectPreviousProject), "[", target))
        add(file, to: main)

        // The terminal answers these through the "responder chain" (the view with the focus).
        let edit = NSMenu(title: "Édition")
        edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)

        let window = NSMenu(title: "Fenêtre")
        window.addItem(withTitle: "Fermer la fenêtre", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Réduire", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        add(window, to: main)

        return main
    }

    private static func add(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }

    @MainActor
    private static func item(_ title: String, _ action: Selector, _ key: String, _ target: AnyObject,
                             modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
