import AppKit
import Combine
import SwiftUI

/// Creates the widget panel, puts the SwiftUI content in it and remembers its position.
///
/// The window always has the size of the largest possible stack (front card + 2 cards
/// below + halo margin): only the cards animate inside it. Resizing the window while
/// SwiftUI animates made the content jump. Outside the cards, the window lets clicks
/// go through to the windows below (see `updateClickThrough`).
@MainActor
final class WidgetWindowController {
    private let panel = WidgetPanel()
    private let settings = WidgetSettings()
    private let board = SessionBoard()
    private let store = SessionStore()
    private let cube: CubeAnimator
    private let hubController: HubWindowController
    private var menuBar: MenuBarController?
    private var hotKey: WidgetHotKey?
    private var settingsWindow: SettingsWindowController!
    private let telegramNotifier = TelegramNotifier()
    private let telegramRemote: TelegramRemote
    private var observers: Set<AnyCancellable> = []
    private var moveObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []

    /// The position is saved as the window's top-left corner.
    private static let topLeftKey = "widgetTopLeft"

    init() {
        // Real sessions are read first, so the cube does not fall asleep and wake up at launch.
        let initial = store.loadNow()
        board.applyRealSessions(initial)
        cube = CubeAnimator(mood: board.cubeMood)
        hubController = HubWindowController(board: board, widget: settings)
        telegramRemote = TelegramRemote(hub: hubController.hub)
        settingsWindow = SettingsWindowController(
            widget: settings,
            themes: hubController.hub.themes,
            onResetWidgetPosition: { [weak self] in self?.moveToDefaultSpot() },
            makeMenu: { [weak hubController] in hubController.map(HubMenu.make(target:)) })
        hubController.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }

        let hostingView = FirstClickHostingView(rootView: WidgetRootView(
            settings: settings, board: board, cube: cube,
            onOpenSession: { [weak hubController] session in hubController?.open(session) },
            onOpenHub: { [weak hubController] in hubController?.show() },
            onNewSession: { [weak hubController] in hubController?.newProject() },
            onOpenSettings: { [weak settingsWindow] in settingsWindow?.show() }))
        hostingView.sizingOptions = []   // the window size is set by `windowSize` only
        panel.contentView = hostingView
        panel.setContentSize(windowSize(scale: settings.scale))
        restorePosition()

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePosition() }
        }

        // What is already there at launch sends no Telegram message.
        telegramNotifier.process(initial.map(\.file))
        telegramRemote.update(initial.map(\.file))
        // A reply to a message about a session goes to that session.
        telegramNotifier.buttons = { [weak telegramRemote] file in
            telegramRemote?.buttons(for: file)
        }
        telegramNotifier.onSent = { [weak telegramRemote] messageID, sessionID in
            telegramRemote?.remember(messageID, for: sessionID)
        }

        // Every change of the session files reaches the board on the main thread.
        store.onChange = { [weak self, weak board] snapshots in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    board?.applyRealSessions(snapshots)
                    self?.telegramNotifier.process(snapshots.map(\.file))
                    self?.telegramRemote.update(snapshots.map(\.file))
                }
            }
        }
        store.start()

        // When the Mac wakes up, the sessions are read again right away, and the widget
        // comes back on a screen if its display is gone (e.g. external display unplugged
        // during the sleep).
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.store.refreshNow()
                    self?.keepOnScreen()
                }
            }
            .store(in: &observers)
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.keepOnScreen() } }
            .store(in: &observers)

        // Every project seen (open sessions, Hub projects) joins the list "Telegram par projet".
        board.$sessions
            .sink { sessions in TelegramSettings.shared.noteProjects(sessions.compactMap(\.folder)) }
            .store(in: &observers)
        hubController.hub.$projects
            .sink { projects in TelegramSettings.shared.noteProjects(projects.map(\.folder)) }
            .store(in: &observers)

        // The icon in the menu bar: choosing a session there brings it to the front and
        // opens it in the Hub, like the widget's right-click menu.
        menuBar = MenuBarController(
            board: board, cube: cube,
            widget: settings,
            onChoose: { [weak self] session in
                guard let self else { return }
                withAnimation(.smooth(duration: Constants.BackCard.swapAnimationDuration)) {
                    self.board.activate(session.id)
                }
                self.hubController.open(session)
            },
            onOpenHub: { [weak hubController] in hubController?.show() },
            onOpenSettings: { [weak settingsWindow] page in settingsWindow?.show(page) })

        // ⌃⌥W, from any app: same setting as "Afficher le widget".
        hotKey = WidgetHotKey { [weak self] in self?.settings.isVisible.toggle() }

        // "Afficher le widget" (menu bar icon or Réglages): shows or hides the panel.
        settings.$isVisible
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] visible in
                if visible { self?.panel.orderFrontRegardless() } else { self?.panel.orderOut(nil) }
            }
            .store(in: &observers)

        // Sounds of the active project play with the matching cube animation.
        board.cueActiveSound = { [weak self] sound in self?.cube.cue(sound) }

        // The cube follows the active project.
        board.objectWillChange
            .sink { [weak self] _ in
                // `objectWillChange` fires just before the change: read the new state on the next turn.
                DispatchQueue.main.async { self.map { $0.cube.mood = $0.board.cubeMood } }
            }
            .store(in: &observers)

        // Where the mouse is, compared to the cube's center (for the "task completed" eyes).
        // Reading the mouse position needs no permission.
        cube.mouseOffset = { [weak self] in
            guard let self else { return nil }
            let front = Constants.FrontCard.self
            let scale = self.settings.scale
            let cardHeight = self.settings.isCollapsed ? front.collapsedSide : front.height
            let leading = self.settings.isCollapsed ? (front.collapsedSide - front.cubeHeight) / 2 : front.cubeLeadingPadding
            // Cube center, from the window's top-left corner, in points at 100 %.
            let centerX = Constants.Window.haloMargin + leading + front.cubeHeight * FrameLibrary.aspectRatio / 2
            let centerY = Constants.Window.haloMargin + cardHeight / 2
            let mouse = NSEvent.mouseLocation   // screen coordinates: y goes up
            return CGVector(dx: mouse.x - (self.panel.frame.minX + centerX * scale),
                            dy: mouse.y - (self.panel.frame.maxY - centerY * scale))
        }

        // The window size only depends on the widget size setting (never animated).
        settings.$scale
            .dropFirst()
            .sink { [weak self] scale in
                guard let self else { return }
                self.setSizeKeepingTopLeft(self.windowSize(scale: scale))
            }
            .store(in: &observers)

        // Follow the mouse to know when the window must catch clicks.
        // A "global" monitor sees the mouse over other apps, a "local" one over this app.
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateClickThrough() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.updateClickThrough() }
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
        panel.acceptsMouseMovedEvents = true
        updateClickThrough()
    }

    /// Shows the widget, unless it was hidden ("Afficher le widget", remembered even
    /// after a relaunch).
    func show() {
        if settings.isVisible { panel.orderFrontRegardless() }
    }

    /// Claude sessions running in the Hub's terminals (they stop when the app quits).
    var hasRunningHubProjects: Bool { hubController.hub.hasRunningProjects }

    // MARK: - Size

    /// Size of the largest possible stack, plus the halo margin all around.
    private func windowSize(scale: Double) -> NSSize {
        let margin = Constants.Window.haloMargin
        let stack = StackGeometry.size(backCount: Constants.BackCard.maxCount, collapsed: false)
        return NSSize(width: (stack.width + 2 * margin) * scale, height: (stack.height + 2 * margin) * scale)
    }

    /// Size and position change in a single step: changing the size alone keeps the
    /// bottom-left corner fixed, which would make the widget jump for one frame.
    private func setSizeKeepingTopLeft(_ size: NSSize) {
        let frame = panel.frame
        guard frame.size != size else { return }
        let newFrame = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(newFrame, display: true, animate: false)
    }

    // MARK: - Clicks

    /// The window catches clicks only when the mouse is over the cards. Elsewhere (empty,
    /// transparent part of the window) clicks go through to the windows below.
    private func updateClickThrough() {
        let scale = settings.scale
        let margin = Constants.Window.haloMargin * scale
        let stack = StackGeometry.size(backCount: board.visibleOthers.count, collapsed: settings.isCollapsed)
        let frame = panel.frame
        // Screen coordinates start at the bottom-left; the cards start at the window's top-left.
        let cards = NSRect(x: frame.minX + margin,
                           y: frame.maxY - margin - stack.height * scale,
                           width: stack.width * scale,
                           height: stack.height * scale)
        let ignore = !cards.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents != ignore {
            panel.ignoresMouseEvents = ignore
        }
    }

    // MARK: - Position

    private func savePosition() {
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: Self.topLeftKey)
    }

    private func restorePosition() {
        if let saved = UserDefaults.standard.string(forKey: Self.topLeftKey) {
            let topLeft = NSPointFromString(saved)
            // Ignore the saved spot if it is no longer on any screen (e.g. external display unplugged).
            if Self.isOnScreen(topLeft) {
                panel.setFrameTopLeftPoint(topLeft)
                return
            }
        }
        moveToDefaultSpot()
    }

    /// Screens changed (display unplugged, Mac woken up): puts the widget back in its
    /// default spot if its top-left corner is no longer on any screen.
    private func keepOnScreen() {
        guard !Self.isOnScreen(NSPoint(x: panel.frame.minX, y: panel.frame.maxY)) else { return }
        moveToDefaultSpot()
    }

    /// The top-right corner of the main screen.
    private func moveToDefaultSpot() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let inset = Constants.Window.defaultScreenInset
        panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - panel.frame.width - inset, y: screen.maxY - inset))
    }

    private static func isOnScreen(_ point: NSPoint) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(point) }
    }
}

/// Hosting view that reacts to the very first click, even though the panel never
/// becomes the active window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Everything drawn inside the panel.
struct WidgetRootView: View {
    @ObservedObject var settings: WidgetSettings
    let board: SessionBoard
    let cube: CubeAnimator
    let onOpenSession: (Session?) -> Void
    let onOpenHub: () -> Void
    /// Asks for a folder and starts Claude there, in the Cube Hub.
    let onNewSession: () -> Void
    let onOpenSettings: () -> Void
    /// The card under the mouse: a right click on it offers its Telegram setting.
    @State private var hoveredSessionID: Session.ID?

    var body: some View {
        CardStackView(board: board, cube: cube, isCollapsed: settings.isCollapsed,
                      onToggleCollapsed: toggleCollapsed, onDoubleClick: onOpenSession,
                      onHoverSession: { id in if hoveredSessionID != id { hoveredSessionID = id } })
            .padding(Constants.Window.haloMargin * settings.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.widgetScale, settings.scale)
            .contextMenu {
                if let session = board.sessions.first(where: { $0.id == hoveredSessionID }),
                   let folder = session.folder {
                    TelegramMenuItem(folder: folder, projectName: session.projectName)
                    Divider()
                }
                SessionsMenuSection(board: board, onChoose: choose)
                Button("Nouvelle session…") { onNewSession() }
                Button("Ouvrir le Cube Hub") { onOpenHub() }
                Divider()
                Button(settings.isCollapsed ? "Déplier" : "Replier") { toggleCollapsed() }
                Picker("Taille du widget", selection: $settings.scale) {
                    ForEach(Constants.Window.scaleChoices, id: \.self) { choice in
                        Text("\(Int((choice * 100).rounded())) %").tag(choice)
                    }
                }
                Button("Réglages…") { onOpenSettings() }
                Divider()
                Menu("Debug") {
                    Button("Vraies sessions") { debug { board.showRealSessions() } }
                    Section("Démo · projet actif") {
                        Button("Aucune session") { debug { board.debugSetActiveStatus(nil) } }
                        Button("Bosse") { debug { board.debugSetActiveStatus(.working) } }
                        Button("Attend ta réponse") { debug { board.debugSetActiveStatus(.waiting) } }
                        Button("Réponse terminée") { debug { board.debugFinishAnswer() } }
                        Button("Tâche terminée") { debug { board.debugCompleteTask() } }
                    }
                    Section("Démo · cartes du dessous") {
                        Button("Une carte passe en attente") { debug { board.debugBackCardStartsWaiting() } }
                        ForEach(0...3, id: \.self) { count in
                            Button(count == 3 ? "3 (une reste cachée)" : "\(count)") {
                                debug { board.debugSetBackCount(count) }
                            }
                        }
                    }
                }
                Divider()
                Button("Quitter Cube Hub") { NSApp.terminate(nil) }
            }
    }

    /// A session chosen in the menu comes to the front and opens, like a double click on its card.
    private func choose(_ session: Session) {
        withAnimation(.smooth(duration: Constants.BackCard.swapAnimationDuration)) {
            board.activate(session.id)
        }
        onOpenSession(session)
    }

    private func toggleCollapsed() {
        withAnimation(.smooth(duration: Constants.FrontCard.collapseAnimationDuration, extraBounce: 0.08)) {
            settings.isCollapsed.toggle()
        }
    }

    private func debug(_ change: () -> Void) {
        withAnimation(.smooth(duration: Constants.BackCard.swapAnimationDuration), change)
    }
}

/// The open sessions in the widget's menu, the front one checked. Observes the board on
/// its own, so the list is always up to date without redrawing the whole widget.
private struct SessionsMenuSection: View {
    @ObservedObject var board: SessionBoard
    let onChoose: (Session) -> Void

    var body: some View {
        if !board.sessions.isEmpty {
            Section("Sessions") {
                // Plain buttons (not toggles): a toggle bound to an action may be set by
                // SwiftUI itself when its label changes, which would open the Hub alone.
                ForEach(board.sessions) { session in
                    let mark = session.id == board.active?.id ? "✓ " : ""
                    Button("\(mark)\(session.projectName) — \(session.status.longLabel)") {
                        onChoose(session)
                    }
                }
            }
        }
    }
}
