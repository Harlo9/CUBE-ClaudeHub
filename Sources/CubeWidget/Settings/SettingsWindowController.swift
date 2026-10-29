import AppKit
import SwiftUI

/// The "Réglages" window (gear of the Cube Hub, ⌘, or "Réglages…" in the menus): every
/// setting of the app in one place, sorted into pages listed on the left, like the Mac's
/// System Settings.
///
/// Like the Hub, the app becomes a regular app while the window is open (Dock icon and
/// menu bar, for ⌘C / ⌘V in its text fields), and the window stays on a normal desktop.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let navigation = SettingsNavigation()
    private let widget: WidgetSettings
    private let themes: HubThemes
    private let onResetWidgetPosition: () -> Void
    /// The app's menu bar while the window is open (the Hub's one).
    private let makeMenu: () -> NSMenu?
    private var window: NSWindow?

    init(widget: WidgetSettings, themes: HubThemes, onResetWidgetPosition: @escaping () -> Void, makeMenu: @escaping () -> NSMenu?) {
        self.widget = widget
        self.themes = themes
        self.onResetWidgetPosition = onResetWidgetPosition
        self.makeMenu = makeMenu
    }

    /// Shows the window, on a given page (else the last one shown).
    func show(_ page: SettingsPage? = nil) {
        if let page { navigation.page = page }
        NSApp.setActivationPolicy(.regular)
        if let menu = makeMenu() { NSApp.mainMenu = menu }
        let window = self.window ?? makeWindow()
        // Once the new activation policy is in place.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Constants.Settings.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Réglages"
        window.appearance = NSAppearance(named: .darkAqua)   // dark, like the Hub
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed]
        window.contentMinSize = Constants.Settings.minimumWindowSize
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(
            navigation: navigation, widget: widget, themes: themes, onResetWidgetPosition: onResetWidgetPosition))
        window.center()
        window.setFrameAutosaveName("Reglages")   // remembers its size and position
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        AppWindows.becomeAccessoryIfNoWindow(besides: window)
    }
}

/// Which page the Réglages window shows (remembered, even after a relaunch).
@MainActor
final class SettingsNavigation: ObservableObject {
    private static let pageKey = "settingsPage"

    @Published var page: SettingsPage {
        didSet { UserDefaults.standard.set(page.rawValue, forKey: Self.pageKey) }
    }

    init() {
        page = UserDefaults.standard.string(forKey: Self.pageKey).flatMap(SettingsPage.init(rawValue:)) ?? .general
    }
}

/// The app's own windows (Cube Hub, Réglages…) share the Dock icon: the app goes back
/// to having none only once the last of them is closed.
enum AppWindows {
    @MainActor
    static func becomeAccessoryIfNoWindow(besides closing: NSWindow?) {
        // Titled windows only: not the widget (a panel without a title bar) nor the menu bar icon.
        let others = NSApp.windows.filter {
            $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel)
        }
        if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
