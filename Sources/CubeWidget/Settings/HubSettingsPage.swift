import SwiftUI

/// "Cube Hub": the themes of the Hub's list (name, color, order), and a new one.
/// The same themes as in the Hub: a change here shows there right away, and the other way round.
struct HubSettingsPage: View {
    @ObservedObject var themes: HubThemes
    @State private var newName = ""

    var body: some View {
        Form {
            Section {
                if themes.themes.isEmpty {
                    Text("Aucun thème pour l'instant : toutes les sessions sont dans « Sessions ».")
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(themes.themes.enumerated()), id: \.element.id) { index, theme in
                    ThemeRow(themes: themes, theme: theme,
                             isFirst: index == 0, isLast: index == themes.themes.count - 1)
                }
                HStack {
                    TextField("Nouveau thème", text: $newName, prompt: Text("Nom du nouveau thème"))
                        .labelsHidden()
                        .onSubmit(addTheme)
                    Button("Ajouter", action: addTheme)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Thèmes")
            } footer: {
                Text("Pour ranger une session dans un thème : glisse sa carte dans le Cube Hub, ou clic droit sur sa carte → Thème ▸. Supprimer un thème ne ferme aucune session : elles vont dans « Sans thème ».")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func addTheme() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _ = themes.add(named: name)
        newName = ""
    }
}

/// One theme: its color, its name (typed in place), its color menu, ▲ ▼ and delete.
private struct ThemeRow: View {
    @ObservedObject var themes: HubThemes
    let theme: HubTheme
    let isFirst: Bool
    let isLast: Bool

    @State private var name = ""
    @FocusState private var isEditing: Bool

    private typealias H = Constants.Hub

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.color)
                .frame(width: Constants.Settings.themeDotSize, height: Constants.Settings.themeDotSize)
            TextField("Nom", text: $name)
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($isEditing)
                .onSubmit(commit)
                .onChange(of: isEditing) { if !isEditing { commit() } }
            Text(sessionCount)
                .font(.caption).foregroundStyle(.secondary)
            Picker("Couleur", selection: Binding(get: { theme.colorIndex % H.themeColors.count },
                                                 set: { themes.setColor($0, of: theme.id) })) {
                ForEach(H.themeColorNames.indices, id: \.self) { index in
                    Text(H.themeColorNames[index]).tag(index)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Button { themes.move(theme.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(isFirst)
                .help("Monter")
            Button { themes.move(theme.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(isLast)
                .help("Descendre")
            Button(role: .destructive) { themes.delete(theme.id) } label: { Image(systemName: "trash") }
                .help("Supprimer le thème (ses sessions vont dans « Sans thème »)")
        }
        .buttonStyle(.borderless)
        .onAppear { name = theme.name }
        .onChange(of: theme.name) { if !isEditing { name = theme.name } }
    }

    /// "2 projets": the projects remembered in this theme.
    private var sessionCount: String {
        let count = themes.assignment.values.filter { $0 == theme.id }.count
        return count == 0 ? "vide" : "\(count) projet\(count > 1 ? "s" : "")"
    }

    /// Saves the typed name; an empty one puts the old name back.
    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == theme.name {
            name = theme.name
        } else {
            themes.rename(theme.id, to: trimmed)
        }
    }
}
