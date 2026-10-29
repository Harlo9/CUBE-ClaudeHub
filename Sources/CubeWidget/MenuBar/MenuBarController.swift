import AppKit
import Combine

/// The icon in the menu bar (an `NSStatusItem`: a small spot next to the clock where an
/// app shows an image and a menu): the mini cube, and on click the list of all the
/// sessions, plus the app's options.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let board: SessionBoard
    /// A session chosen in the menu: it comes to the front and opens in the Hub.
    private let onChoose: (Session) -> Void
    private let onOpenHub: () -> Void
    private let widget: WidgetSettings
    /// Opens the Réglages window, on a given page if any.
    private let onOpenSettings: (SettingsPage?) -> Void
    private let miniCube: MenuBarCube
    private let telegram = TelegramSettings.shared
    private var moodObserver: AnyCancellable?

    init(board: SessionBoard, cube: CubeAnimator,
         widget: WidgetSettings,
         onChoose: @escaping (Session) -> Void, onOpenHub: @escaping () -> Void,
         onOpenSettings: @escaping (SettingsPage?) -> Void) {
        self.board = board
        self.widget = widget
        self.onOpenSettings = onOpenSettings
        self.onChoose = onChoose
        self.onOpenHub = onOpenHub
        miniCube = MenuBarCube(button: item.button)
        super.init()
        item.button?.toolTip = "Cube Hub"
        // The mini cube shows what the widget's cube shows, at the same moment.
        moodObserver = cube.$shownMood
            .removeDuplicates()
            .sink { [weak self] mood in self?.miniCube.show(mood) }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // MARK: - Menu

    /// The menu is rebuilt each time it opens, so the list of sessions is always up to date.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if board.sessions.isEmpty {
            let empty = NSMenuItem(title: "Aucune session", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for session in board.sessions {
                let line = NSMenuItem(title: session.projectName, action: #selector(chooseSession(_:)), keyEquivalent: "")
                line.target = self
                line.representedObject = session.id
                line.attributedTitle = Self.title(for: session)
                line.state = session.id == board.active?.id ? .on : .off
                menu.addItem(line)
            }
        }
        menu.addItem(.separator())
        let hub = NSMenuItem(title: "Ouvrir le Cube Hub", action: #selector(openHub), keyEquivalent: "")
        hub.target = self
        menu.addItem(hub)
        let widget = NSMenuItem(title: "Afficher le widget", action: #selector(toggleWidget), keyEquivalent: "w")
        widget.keyEquivalentModifierMask = [.control, .option]   // only shown: the global ⌃⌥W does the work
        widget.target = self
        widget.state = self.widget.isVisible ? .on : .off
        menu.addItem(widget)
        let login = NSMenuItem(title: "Lancer au démarrage du Mac", action: #selector(toggleLaunchAtLogin),
                               keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        let settings = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(telegramItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter Cube Hub", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    /// "● name   status": the dot and the status in the session's color.
    private static func title(for session: Session) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let color = NSColor(session.status.color)
        let title = NSMutableAttributedString(string: "● ", attributes: [.font: font, .foregroundColor: color])
        title.append(NSAttributedString(string: session.projectName, attributes: [.font: font]))
        title.append(NSAttributedString(string: "   \(session.status.longLabel)",
                                        attributes: [.font: font, .foregroundColor: color]))
        return title
    }

    /// "Telegram ▸": the general switch, the setup window, and the last sending error.
    private func telegramItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Telegram")
        let enabled = NSMenuItem(title: "Notifications Telegram", action: #selector(toggleTelegram), keyEquivalent: "")
        enabled.target = self
        enabled.state = telegram.isEnabled ? .on : .off
        submenu.addItem(enabled)
        let always = NSMenuItem(title: "Toujours envoyer (même si je suis devant le Mac)",
                                action: #selector(toggleTelegramAlwaysSend), keyEquivalent: "")
        always.target = self
        always.state = telegram.alwaysSend ? .on : .off
        submenu.addItem(always)
        let byDefault = NSMenuItem(title: "Activer par défaut pour les nouveaux projets",
                                   action: #selector(toggleTelegramByDefault), keyEquivalent: "")
        byDefault.target = self
        byDefault.state = telegram.isOnForNewProjects ? .on : .off
        submenu.addItem(byDefault)
        let remote = NSMenuItem(title: "Commandes depuis Telegram (répondre à une notification)",
                                action: #selector(toggleTelegramRemote), keyEquivalent: "")
        remote.target = self
        remote.state = telegram.remoteEnabled ? .on : .off
        submenu.addItem(remote)
        let lock = RemoteLock.shared
        if telegram.remoteEnabled, let until = lock.unlockedUntil, lock.isUnlocked {
            submenu.addItem(disabledLine("🔓 Déverrouillé jusqu'à \(until.formatted(date: .omitted, time: .shortened))"))
            let lockNow = NSMenuItem(title: "Verrouiller maintenant", action: #selector(lockRemote), keyEquivalent: "")
            lockNow.target = self
            submenu.addItem(lockNow)
        } else if telegram.remoteEnabled {
            submenu.addItem(disabledLine("🔒 Verrouillé (envoie /unlock et le code)"))
        }
        let code = NSMenuItem(title: "Code de déverrouillage…", action: #selector(openCodeSetup), keyEquivalent: "")
        code.target = self
        submenu.addItem(code)
        submenu.addItem(.separator())

        // Every known project, with its check box (same setting as the bells on the cards).
        submenu.addItem(NSMenuItem.sectionHeader(title: "Telegram par projet"))
        let projects = telegram.projects.keys
            .map { URL(fileURLWithPath: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if projects.isEmpty {
            submenu.addItem(disabledLine("Aucun projet pour l'instant"))
        }
        for folder in projects {
            let line = NSMenuItem(title: folder.lastPathComponent, action: #selector(toggleTelegramProject(_:)),
                                  keyEquivalent: "")
            line.target = self
            line.representedObject = folder
            line.state = telegram.isOn(for: folder) ? .on : .off
            line.toolTip = folder.path
            submenu.addItem(line)
        }
        submenu.addItem(.separator())
        let setup = NSMenuItem(title: "Configurer Telegram…", action: #selector(openTelegramSetup), keyEquivalent: "")
        setup.target = self
        submenu.addItem(setup)
        if !telegram.isConfigured {
            submenu.addItem(disabledLine("Pas encore configuré"))
        } else if let error = telegram.lastError {
            submenu.addItem(disabledLine("⚠︎ Dernier envoi échoué : \(error)"))
        }

        let item = NSMenuItem(title: telegram.lastError == nil ? "Telegram" : "Telegram ⚠︎", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func disabledLine(_ title: String) -> NSMenuItem {
        let line = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        line.isEnabled = false
        return line
    }

    @objc private func toggleTelegram() {
        telegram.isEnabled.toggle()
    }

    @objc private func toggleTelegramAlwaysSend() {
        telegram.alwaysSend.toggle()
    }

    /// Without a code set up, the commands cannot be turned on: the page where the code
    /// is set up opens instead.
    @objc private func toggleTelegramRemote() {
        guard telegram.remoteEnabled || RemoteLock.shared.isSetUp else {
            onOpenSettings(.telegramCommands)
            return
        }
        telegram.remoteEnabled.toggle()
    }

    @objc private func lockRemote() {
        RemoteLock.shared.lock()
    }

    @objc private func openCodeSetup() {
        onOpenSettings(.telegramCommands)
    }

    @objc private func toggleTelegramByDefault() {
        telegram.isOnForNewProjects.toggle()
    }

    @objc private func toggleTelegramProject(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        telegram.toggle(folder)
    }

    @objc private func openTelegramSetup() {
        onOpenSettings(.telegramConnection)
    }

    @objc private func chooseSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let session = board.sessions.first(where: { $0.id == id }) else { return }
        onChoose(session)
    }

    @objc private func openHub() {
        onOpenHub()
    }

    @objc private func toggleWidget() {
        widget.isVisible.toggle()
    }

    @objc private func openSettings() {
        onOpenSettings(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
    }
}
