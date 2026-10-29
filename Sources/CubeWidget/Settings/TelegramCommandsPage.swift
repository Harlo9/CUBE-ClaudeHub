import CoreImage.CIFilterBuiltins
import SwiftUI

/// "Telegram – Commandes": the switch, the lock (unlocked until when), the unlock code
/// (set up with a QR code scanned by your code app), and how to use it.
struct TelegramCommandsPage: View {
    @ObservedObject var settings: TelegramSettings
    @ObservedObject var lock: RemoteLock
    let onConfigure: () -> Void

    /// A new secret being set up, shown until it is confirmed (then it only lives in the keychain).
    @State private var secret: Data?
    @State private var code = ""
    @State private var codeError: String?

    private typealias T = Constants.Telegram

    var body: some View {
        Form {
            if !settings.isConfigured { TelegramNotConfiguredSection(onConfigure: onConfigure) }
            Section("Commandes") {
                Toggle(isOn: $settings.remoteEnabled) {
                    SettingLabel("Commandes depuis Telegram",
                                 lock.isSetUp
                                    ? "Tes réponses aux notifications sont tapées dans la session. Désactivé, l'app ne lit aucun message de Telegram."
                                    : "Configure d'abord le code de déverrouillage, plus bas.")
                }
                .disabled(!lock.isSetUp && !settings.remoteEnabled)
                if settings.remoteEnabled { lockRow }
            }
            projectsSection
            Section("Journal") {
                LabeledContent {
                    Button("Ouvrir le journal") { NSWorkspace.shared.open(RemoteLog.url) }
                        .disabled(!FileManager.default.fileExists(atPath: RemoteLog.url.path))
                } label: {
                    SettingLabel("Journal des commandes",
                                 "Chaque message reçu est noté dans ~/.cube-widget/remote.log (jamais le code). Les messages envoyés à une session, les déverrouillages et les codes faux s'affichent aussi en notification sur le Mac.")
                }
            }
            codeSection
            Section("Mode d'emploi") {
                usageRow("1", "/unlock", "puis le code de ton app (ou /unlock 123456 d'un coup) : déverrouillé \(Int(T.unlockDuration / 60)) minutes. Ton message avec le code est effacé.")
                usageRow("2", "Réponds à une notification", "(glisse-la vers la gauche) : ton texte est envoyé à sa session.")
                usageRow("3", "/sessions", "tes sessions et leur état : réponds à l'une d'elles pour lui écrire.")
                usageRow("4", "/lock", "reverrouille tout de suite. /aide rappelle tout ça.")
            }
        }
        .formStyle(.grouped)
        // Not set up yet: a new secret, made when the page shows (saved once confirmed).
        .onAppear { if !lock.isSetUp, secret == nil { secret = TOTP.newSecret() } }
    }

    // MARK: Allowed projects

    private var projectsSection: some View {
        Section {
            if projects.isEmpty {
                Text("Aucun projet pour l'instant.").foregroundStyle(.tertiary)
            }
            ForEach(projects, id: \.self) { folder in
                Toggle(isOn: Binding(get: { settings.isRemoteAllowed(for: folder) },
                                     set: { settings.setRemoteAllowed($0, for: folder) })) {
                    SettingLabel(folder.lastPathComponent, folder.path)
                }
            }
        } header: {
            Text("Projets autorisés")
        } footer: {
            Text("Seuls ces projets acceptent tes réponses depuis Telegram. Tous sont refusés au départ, nouveaux projets compris. Aussi dans le Cube Hub : clic droit sur un projet → Commandes Telegram.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Every known project (the same list as the notifications), by name.
    private var projects: [URL] {
        settings.projects.keys
            .map { URL(fileURLWithPath: $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: The lock

    @ViewBuilder
    private var lockRow: some View {
        if let until = lock.unlockedUntil, lock.isUnlocked {
            LabeledContent {
                Button("Verrouiller maintenant") { lock.lock() }
            } label: {
                SettingLabel("🔓 Déverrouillé jusqu'à \(until.formatted(date: .omitted, time: .shortened))",
                             "Se reverrouille tout seul à la fin, ou avec /lock.")
            }
        } else {
            SettingLabel("🔒 Verrouillé", "Envoie /unlock suivi du code pour écrire à tes sessions.")
        }
    }

    // MARK: The unlock code

    @ViewBuilder
    private var codeSection: some View {
        if let secret {
            Section("Code de déverrouillage") {
                Text("1. Scanne ce QR code avec l'appareil photo de l'iPhone (il l'ajoute à l'app Mots de passe) ou avec une app de codes (Google Authenticator…).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    if let image = Self.qrCode(TOTP.setupURL(secret: secret)) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: T.codeQRSize, height: T.codeQRSize)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                }
                Text("Ou tape cette clé à la main : \(Self.grouped(TOTP.base32(secret)))")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent {
                    HStack {
                        TextField("Code", text: $code, prompt: Text("123456"))
                            .labelsHidden()
                            .font(.body.monospacedDigit())
                            .frame(width: 90)
                            .onSubmit { confirm(secret) }
                        Button("Valider") { confirm(secret) }
                            .disabled(code.filter(\.isNumber).count != TOTP.digits)
                        if lock.isSetUp {
                            Button("Annuler") { self.secret = nil; code = ""; codeError = nil }
                        }
                    }
                } label: {
                    SettingLabel("2. Le code à 6 chiffres affiché",
                                 lock.isSetUp ? "Valider remplace l'ancien code : supprime l'ancien « Cube Hub » (ou « CubeWidget ») de ton app." : nil)
                }
                if let codeError { SettingStatus(ok: false, codeError) }
            }
        } else if lock.isSetUp {
            Section("Code de déverrouillage") {
                LabeledContent {
                    Button("Réinitialiser…") { secret = TOTP.newSecret() }
                } label: {
                    SettingStatus(ok: true, "Code configuré",
                                  "Le secret est rangé dans le trousseau de ton Mac. Réinitialiser en crée un nouveau.")
                }
            }
        }
    }

    private func confirm(_ secret: Data) {
        guard lock.setUp(secret: secret, code: code) else {
            codeError = "Code faux : vérifie que c'est bien celui de « Cube Hub », puis réessaie."
            return
        }
        self.secret = nil   // no longer shown
        code = ""
        codeError = nil
    }

    private func usageRow(_ number: String, _ command: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            (Text(command).fontWeight(.semibold) + Text(" " + detail).foregroundColor(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "ABCD EFGH …": easier to type.
    private static func grouped(_ key: String) -> String {
        stride(from: 0, to: key.count, by: 4).map {
            let start = key.index(key.startIndex, offsetBy: $0)
            return String(key[start..<(key.index(start, offsetBy: 4, limitedBy: key.endIndex) ?? key.endIndex)])
        }.joined(separator: " ")
    }

    /// The QR code, drawn by macOS (Core Image), one pixel per square.
    private static func qrCode(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
