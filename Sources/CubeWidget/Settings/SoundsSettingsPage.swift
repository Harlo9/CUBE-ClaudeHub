import SwiftUI

/// "Sons": all the sounds on or off, and the volume of each one, with ▶ to hear it.
struct SoundsSettingsPage: View {
    @ObservedObject var sounds: SoundSettings

    var body: some View {
        Form {
            Section("Sons") {
                Toggle(isOn: $sounds.isEnabled) {
                    SettingLabel("Sons de l'app",
                                 "Désactivé, le cube ne fait plus aucun bruit. Les boutons ▶ marchent quand même.")
                }
            }
            Section {
                ForEach(SoundPlayer.Sound.allCases, id: \.self) { sound in
                    volumeRow(sound)
                }
            } header: {
                Text("Volume de chaque son")
            } footer: {
                HStack {
                    Text("Par rapport au volume du Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remettre les volumes d'origine") { sounds.resetVolumes() }
                        .disabled(SoundPlayer.Sound.allCases.allSatisfy { sounds.volumes[$0] == $0.defaultVolume })
                }
            }
        }
        .formStyle(.grouped)
    }

    private func volumeRow(_ sound: SoundPlayer.Sound) -> some View {
        let volume = sounds.volumes[sound] ?? sound.defaultVolume
        return LabeledContent {
            HStack(spacing: 8) {
                Slider(value: Binding(get: { Double(volume) },
                                      set: { sounds.setVolume(Float($0), of: sound) }),
                       in: 0...1)
                    .labelsHidden()
                    .frame(width: Constants.Settings.volumeSliderWidth)
                Text("\(Int((volume * 100).rounded())) %")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Button {
                    SoundPlayer.preview(sound, volume: volume)
                } label: {
                    Image(systemName: "play.fill")
                }
                .help("Écouter")   // works even when the sounds are off
            }
        } label: {
            SettingLabel(sound.title, sound.detail)
        }
    }
}
