import SwiftUI

/// "Général": what shows on the screen, and starting with the Mac.
struct GeneralSettingsPage: View {
    @ObservedObject var widget: WidgetSettings
    /// Read from macOS (not an app setting): refreshed when the page shows and after a change.
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("À l'écran") {
                Toggle(isOn: $widget.isVisible) {
                    SettingLabel("Afficher le widget",
                                 "Les cartes de tes sessions, toujours au-dessus des autres fenêtres. Raccourci \(Constants.Window.toggleHotKeyLabel), depuis n'importe quelle app. Le mini cube reste dans la barre du haut.")
                }
            }
            Section("Démarrage") {
                Toggle(isOn: Binding(get: { launchesAtLogin }, set: { isOn in
                    LaunchAtLogin.set(isOn)
                    launchesAtLogin = LaunchAtLogin.isEnabled
                })) {
                    SettingLabel("Lancer au démarrage du Mac",
                                 "Visible dans Réglages Système → Général → Ouverture. Si le dossier du projet change de place, recoche cette option.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchesAtLogin = LaunchAtLogin.isEnabled }
    }
}
