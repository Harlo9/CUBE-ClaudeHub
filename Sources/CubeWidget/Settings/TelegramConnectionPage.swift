import SwiftUI

/// "Telegram – Connexion": three steps, the bot's token, your conversation with the bot,
/// and a test message.
struct TelegramConnectionPage: View {
    @ObservedObject var settings: TelegramSettings

    @State private var token = ""
    @State private var isChangingToken = false
    @State private var isCheckingToken = false
    @State private var tokenError: String?
    @State private var chatError: String?
    @State private var testResult: (ok: Bool, text: String)?
    @State private var isSendingTest = false

    var body: some View {
        Form {
            botStep
            chatStep
            testStep
        }
        .formStyle(.grouped)
    }

    // MARK: 1. The bot

    private var botStep: some View {
        Section("1. Ton bot") {
            if let botName = settings.botName, !isChangingToken {
                LabeledContent {
                    HStack {
                        Button("Changer") { isChangingToken = true }
                        Button("Supprimer", role: .destructive) { settings.deleteToken() }
                    }
                } label: {
                    SettingStatus(ok: true, "@\(botName)", "Le token est rangé dans le trousseau de ton Mac.")
                }
            } else {
                Text("Dans Telegram, écris à @BotFather, envoie /newbot et suis ses questions. Il te donne un token : colle-le ici.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    SecureField("Token du bot", text: $token, prompt: Text("123456:ABC…"))
                        .labelsHidden()
                        .onSubmit(saveToken)
                    if isCheckingToken { ProgressView().controlSize(.small) }
                    Button("Enregistrer", action: saveToken)
                        .disabled(token.isEmpty || isCheckingToken)
                    if isChangingToken {
                        Button("Annuler") { isChangingToken = false; token = "" }
                    }
                }
                if let tokenError { SettingStatus(ok: false, tokenError) }
            }
        }
    }

    private func saveToken() {
        guard !token.isEmpty, !isCheckingToken else { return }
        isCheckingToken = true
        tokenError = nil
        Task {
            do {
                try await settings.saveToken(token)
                token = ""   // not kept on screen nor in memory longer than needed
                isChangingToken = false
            } catch {
                tokenError = error.localizedDescription
            }
            isCheckingToken = false
        }
    }

    // MARK: 2. Your conversation

    private var chatStep: some View {
        Section("2. Ta conversation avec le bot") {
            if settings.botName == nil {
                Text("D'abord le token du bot.").foregroundStyle(.tertiary)
            } else if let chatName = settings.chatName, settings.chatID != nil {
                LabeledContent {
                    Button("Changer") { settings.forgetChat() }
                } label: {
                    SettingStatus(ok: true, "Conversation avec \(chatName)", "Les messages arrivent dans cette conversation.")
                }
            } else {
                Text("Envoie un message à ton bot dans Telegram (par exemple « bonjour ») : l'app trouve ta conversation toute seule.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("En attente de ton message…")
                    Spacer()
                    if let botName = settings.botName, let url = URL(string: "https://t.me/\(botName)") {
                        Link("Ouvrir @\(botName)", destination: url)
                    }
                }
                if let chatError { SettingStatus(ok: false, chatError) }
            }
        }
        // Asks Telegram every few seconds while the conversation is not found.
        .task(id: settings.botName.map { "\($0)/\(settings.chatID == nil)" }) {
            while settings.botName != nil, settings.chatID == nil, !Task.isCancelled {
                do {
                    _ = try await settings.detectChat()
                    chatError = nil
                } catch {
                    chatError = error.localizedDescription
                }
                try? await Task.sleep(for: .seconds(Constants.Telegram.chatPollInterval))
            }
        }
    }

    // MARK: 3. Test

    private var testStep: some View {
        Section {
            LabeledContent {
                HStack {
                    if isSendingTest { ProgressView().controlSize(.small) }
                    Button("Envoyer un test", action: sendTest)
                        .disabled(!settings.isConfigured || isSendingTest)
                }
            } label: {
                if let testResult {
                    SettingStatus(ok: testResult.ok, testResult.text)
                } else {
                    SettingLabel("Message de test", "Vérifie que les messages arrivent bien sur ton téléphone.")
                }
            }
            if let error = settings.lastError, testResult == nil {
                SettingStatus(ok: false, "Dernier envoi échoué : \(error)")
            }
        } header: {
            Text("3. Essai")
        }
    }

    private func sendTest() {
        isSendingTest = true
        testResult = nil
        Task {
            let ok = await settings.send("🧊 Cube Hub : les notifications Telegram fonctionnent !") != nil
            testResult = ok ? (true, "Message envoyé") : (false, settings.lastError ?? "échec")
            isSendingTest = false
        }
    }
}

/// A result: a green check (done) or an orange warning, with an explanation below.
struct SettingStatus: View {
    let ok: Bool
    let title: String
    let detail: String?

    init(ok: Bool, _ title: String, _ detail: String? = nil) {
        self.ok = ok
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Constants.Colors.completed : Constants.Colors.waiting)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Shown at the top of a Telegram page while the bot or the conversation is missing.
struct TelegramNotConfiguredSection: View {
    let onConfigure: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Button("Configurer", action: onConfigure)
            } label: {
                SettingStatus(ok: false, "Telegram n'est pas encore configuré",
                              "Il faut d'abord ton bot et ta conversation (page Connexion).")
            }
        }
    }
}
