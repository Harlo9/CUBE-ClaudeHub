import SwiftUI

/// The pages of the Réglages window, in the order of the list on the left.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, widget, sounds, hub
    case telegramConnection, telegramNotifications, telegramCommands

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Général"
        case .widget: "Widget"
        case .sounds: "Sons"
        case .hub: "Claude Hub"
        case .telegramConnection: "Connexion"
        case .telegramNotifications: "Notifications"
        case .telegramCommands: "Commandes"
        }
    }

    /// The window's title: the page's name, with its group ("Telegram – Connexion").
    var windowTitle: String {
        switch self {
        case .telegramConnection, .telegramNotifications, .telegramCommands: "Telegram – \(title)"
        default: title
        }
    }

    /// Its icon (an SF Symbol, drawn white on a small colored square).
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .widget: "rectangle.stack.fill"
        case .sounds: "speaker.wave.2.fill"
        case .hub: "rectangle.split.2x1.fill"
        case .telegramConnection: "paperplane.fill"
        case .telegramNotifications: "bell.badge.fill"
        case .telegramCommands: "lock.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: Constants.Settings.generalColor
        case .widget: Constants.Settings.widgetColor
        case .sounds: Constants.Settings.soundsColor
        case .hub: Constants.Settings.hubColor
        case .telegramConnection: Constants.Settings.telegramConnectionColor
        case .telegramNotifications: Constants.Settings.telegramNotificationsColor
        case .telegramCommands: Constants.Settings.telegramCommandsColor
        }
    }

    /// The list on the left, in groups (a group without a name has no title).
    static let groups: [(name: String?, pages: [SettingsPage])] = [
        (nil, [.general, .widget, .sounds, .hub]),
        ("Telegram", [.telegramConnection, .telegramNotifications, .telegramCommands]),
    ]
}

/// The list of pages on the left, the chosen page on the right.
struct SettingsView: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var widget: WidgetSettings
    let themes: HubThemes
    let onResetWidgetPosition: () -> Void
    private let telegram = TelegramSettings.shared
    private let lock = RemoteLock.shared
    private let sounds = SoundSettings.shared

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { navigation.page }, set: { if let page = $0 { navigation.page = page } })) {
                ForEach(SettingsPage.groups.indices, id: \.self) { index in
                    let group = SettingsPage.groups[index]
                    Section {
                        ForEach(group.pages) { page in
                            SettingsPageLabel(page: page).tag(page)
                        }
                    } header: {
                        if let name = group.name { Text(name) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(Constants.Settings.sidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            page(navigation.page)
                .navigationTitle(navigation.page.windowTitle)
        }
    }

    @ViewBuilder
    private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralSettingsPage(widget: widget)
        case .widget: WidgetSettingsPage(widget: widget, onResetPosition: onResetWidgetPosition)
        case .sounds: SoundsSettingsPage(sounds: sounds)
        case .hub: HubSettingsPage(themes: themes)
        case .telegramConnection: TelegramConnectionPage(settings: telegram)
        case .telegramNotifications: TelegramNotificationsPage(settings: telegram, onConfigure: openConnection)
        case .telegramCommands: TelegramCommandsPage(settings: telegram, lock: lock, onConfigure: openConnection)
        }
    }

    private func openConnection() {
        navigation.page = .telegramConnection
    }
}

/// A page's name with its icon: a white symbol on a small rounded square of its color,
/// like in the Mac's System Settings.
struct SettingsPageLabel: View {
    let page: SettingsPage

    var body: some View {
        Label {
            Text(page.title)
        } icon: {
            Image(systemName: page.symbol)
                .font(.system(size: Constants.Settings.iconSymbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Constants.Settings.iconSize, height: Constants.Settings.iconSize)
                .background(page.color.gradient,
                            in: RoundedRectangle(cornerRadius: Constants.Settings.iconCornerRadius, style: .continuous))
        }
    }
}

/// A setting's name with its explanation in gray below, as shown in every row.
struct SettingLabel: View {
    let title: String
    let detail: String?

    init(_ title: String, _ detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
