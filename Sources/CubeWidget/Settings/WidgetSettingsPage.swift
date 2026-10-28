import SwiftUI

/// "Widget": its size, folded or not, and its place on the screen.
struct WidgetSettingsPage: View {
    @ObservedObject var widget: WidgetSettings
    let onResetPosition: () -> Void

    var body: some View {
        Form {
            Section("Apparence") {
                Picker(selection: $widget.scale) {
                    ForEach(Constants.Window.scaleChoices, id: \.self) { choice in
                        Text("\(Int((choice * 100).rounded())) %").tag(choice)
                    }
                } label: {
                    SettingLabel("Taille", "Aussi dans le clic droit sur le widget.")
                }
                Toggle(isOn: Binding(get: { widget.isCollapsed }, set: { isCollapsed in
                    // The same movement as a click on the widget.
                    withAnimation(.smooth(duration: Constants.FrontCard.collapseAnimationDuration, extraBounce: 0.08)) {
                        widget.isCollapsed = isCollapsed
                    }
                })) {
                    SettingLabel("Replié", "Seulement le cube, sans les cartes. Un clic sur le widget le replie ou le déplie aussi.")
                }
            }
            Section("Position") {
                LabeledContent {
                    Button("Remettre en haut à droite", action: onResetPosition)
                } label: {
                    SettingLabel("Place à l'écran",
                                 "Glisse le widget pour le déplacer : l'app retient sa place. Ce bouton le remet en haut à droite de l'écran principal.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
