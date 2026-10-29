import SwiftUI

/// "Telegram – Notifications": the general switch, when messages go, and the list of
/// projects with their switch (the same setting as the bells on the cards).
struct TelegramNotificationsPage: View {
    @ObservedObject var settings: TelegramSettings
    let onConfigure: () -> Void

    var body: some View {
        Form {
            if !settings.isConfigured { TelegramNotConfiguredSection(onConfigure: onConfigure) }
            Section("Envoi") {
                Toggle(isOn: $settings.isEnabled) {
                    SettingLabel("Notifications Telegram",
                                 "Coupe tous les messages d'un coup, quels que soient les réglages des projets.")
                }
                Toggle(isOn: $settings.alwaysSend) {
                    SettingLabel("Toujours envoyer",
                                 "Même si tu es devant le Mac. Sinon, seulement après \(Int(Constants.Telegram.awayDelay / 60)) minutes sans souris ni clavier.")
                }
                if let error = settings.lastError {
                    SettingStatus(ok: false, "Dernier envoi échoué : \(error)")
                }
            }
            Section("Messages envoyés") {
                messageRow("✅", "Tâche finie", "Une tâche de la liste de Claude est terminée.")
                messageRow("⏳", "Attend ta réponse", "Claude te pose une question ou demande une permission.")
                messageRow("💬", "Réponse terminée", "Claude a fini de répondre, résumé en quelques puces.")
            }
            Section {
                Toggle(isOn: $settings.isOnForNewProjects) {
                    SettingLabel("Activer pour les nouveaux projets",
                                 "Un projet vu pour la première fois est activé ou non selon cette case.")
                }
                if projects.isEmpty {
                    Text("Aucun projet pour l'instant.").foregroundStyle(.tertiary)
                }
                ForEach(projects, id: \.self) { folder in
                    Toggle(isOn: Binding(get: { settings.isOn(for: folder) },
                                         set: { settings.setOn($0, for: folder) })) {
                        SettingLabel(folder.lastPathComponent, folder.path)
                    }
                }
            } header: {
                Text("Par projet")
            } footer: {
                Text("Même réglage que la cloche sur les cartes du widget et du Cube Hub.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Every known project, by name.
    private var projects: [URL] {
        settings.projects.keys
            .map { URL(fileURLWithPath: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func messageRow(_ emoji: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(emoji)
            SettingLabel(title, detail)
        }
    }
}
