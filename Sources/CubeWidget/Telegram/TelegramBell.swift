import SwiftUI

/// The small bell on a card: full = Telegram messages on for this project, crossed out =
/// off. A click switches. On: white. Off: discreet dark gray, lit only under the mouse.
struct TelegramBell: View {
    let folder: URL
    var size: CGFloat = Constants.Telegram.bellSize
    @ObservedObject private var settings = TelegramSettings.shared
    @State private var isHovered = false

    var body: some View {
        let isOn = settings.isOn(for: folder)
        Button {
            settings.toggle(folder)
        } label: {
            Image(systemName: isOn ? "bell.fill" : "bell.slash")
                .font(.system(size: size))
                .foregroundStyle(isOn ? Constants.Telegram.bellOnColor
                                 : isHovered ? Constants.Telegram.bellHoverColor : Constants.Telegram.bellColor)
                .frame(width: size * Constants.Telegram.bellHitScale, height: size * Constants.Telegram.bellHitScale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: isOn)
        .help(helpText(isOn))
    }

    private func helpText(_ isOn: Bool) -> String {
        guard isOn else { return "Notifications Telegram désactivées pour ce projet (clic pour activer)" }
        return settings.isEnabled
            ? "Notifications Telegram activées pour ce projet (clic pour désactiver)"
            : "Activées pour ce projet, mais coupées dans le menu Telegram de la barre du haut"
    }
}

/// Just before the bell, while "Commandes depuis Telegram" is on: may your replies from
/// Telegram be typed into this project's session? On: white arrow. Off: discreet dark
/// gray, lit only under the mouse (like the bell). A click switches.
struct TelegramReplyToggle: View {
    let folder: URL
    var size: CGFloat = Constants.Telegram.bellSize
    @ObservedObject private var settings = TelegramSettings.shared
    @State private var isHovered = false

    var body: some View {
        if settings.remoteEnabled {
            let isOn = settings.isRemoteAllowed(for: folder)
            Button {
                settings.setRemoteAllowed(!isOn, for: folder)
            } label: {
                Image(systemName: isOn ? "arrowshape.turn.up.left.fill" : "arrowshape.turn.up.left")
                    .font(.system(size: size * 0.9))
                    .foregroundStyle(isOn ? Constants.Telegram.bellOnColor
                                     : isHovered ? Constants.Telegram.bellHoverColor : Constants.Telegram.bellColor)
                    .frame(width: size * Constants.Telegram.bellHitScale, height: size * Constants.Telegram.bellHitScale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.2), value: isOn)
            .help(isOn ? "Tes réponses depuis Telegram sont acceptées pour ce projet (clic pour refuser)"
                       : "Réponses depuis Telegram refusées pour ce projet (clic pour les accepter)")
        }
    }
}

/// "Commandes Telegram", checked or not, for a Hub project's right-click menu: this
/// project accepts your replies from Telegram, or not.
struct TelegramRemoteMenuItem: View {
    let folder: URL
    @ObservedObject private var settings = TelegramSettings.shared

    var body: some View {
        let isAllowed = settings.isRemoteAllowed(for: folder)
        Button(isAllowed ? "✓ Commandes Telegram" : "Commandes Telegram") {
            settings.setRemoteAllowed(!isAllowed, for: folder)
        }
    }
}

/// "Notifications Telegram", checked or not, for a card's right-click menu.
struct TelegramMenuItem: View {
    let folder: URL
    /// Added to the title when the menu is not attached to one card only (the widget's).
    var projectName: String? = nil
    @ObservedObject private var settings = TelegramSettings.shared

    var body: some View {
        let title = "Notifications Telegram" + (projectName.map { " pour « \($0) »" } ?? "")
        Button(settings.isOn(for: folder) ? "✓ \(title)" : title) {
            settings.toggle(folder)
        }
    }
}
