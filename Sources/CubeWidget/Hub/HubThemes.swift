import SwiftUI

/// A theme of the Claude Hub's list ("Freelance", "Projet perso"…): a named, colored
/// section that groups sessions.
struct HubTheme: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Index in `Constants.Hub.themeColors`.
    var colorIndex: Int
    var isCollapsed = false

    var color: Color {
        let colors = Constants.Hub.themeColors
        return colors[((colorIndex % colors.count) + colors.count) % colors.count]
    }
}

/// The themes, in their order, and the theme of each project (by its folder, like the
/// order of the list). Everything is remembered in the app's settings.
@MainActor
final class HubThemes: ObservableObject {
    @Published private(set) var themes: [HubTheme] {
        didSet { save() }
    }
    /// Order key of a card (its folder path) → its theme. Not in it: "Sans thème".
    @Published private(set) var assignment: [String: UUID] {
        didSet { save() }
    }
    /// The "Sans thème" section, folded or not.
    @Published private(set) var isUnthemedCollapsed: Bool {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let themes = "hubThemes"
        static let assignment = "hubThemeOfProject"
        static let unthemedCollapsed = "hubUnthemedCollapsed"
    }

    init() {
        themes = defaults.data(forKey: Keys.themes)
            .flatMap { try? JSONDecoder().decode([HubTheme].self, from: $0) } ?? []
        let saved = defaults.dictionary(forKey: Keys.assignment) as? [String: String] ?? [:]
        assignment = saved.compactMapValues(UUID.init(uuidString:))
        isUnthemedCollapsed = defaults.bool(forKey: Keys.unthemedCollapsed)
    }

    /// The theme of a card, nil for "Sans thème" (also when its theme was deleted).
    func themeID(forKey key: String) -> UUID? {
        guard let id = assignment[key], themes.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func setTheme(_ id: UUID?, forKey key: String) {
        assignment[key] = id
    }

    /// A new theme, at the bottom, with the next color of the palette.
    @discardableResult
    func add(named name: String) -> UUID {
        let theme = HubTheme(id: UUID(), name: name, colorIndex: themes.count % Constants.Hub.themeColors.count)
        themes.append(theme)
        return theme.id
    }

    func rename(_ id: UUID, to name: String) {
        update(id) { $0.name = name }
    }

    func setColor(_ index: Int, of id: UUID) {
        update(id) { $0.colorIndex = index }
    }

    /// Moves a theme up (-1) or down (+1) in the list.
    func move(_ id: UUID, by step: Int) {
        guard let index = themes.firstIndex(where: { $0.id == id }),
              themes.indices.contains(index + step) else { return }
        themes.swapAt(index, index + step)
    }

    /// Deletes a theme: its sessions go to "Sans thème" (nothing is closed).
    func delete(_ id: UUID) {
        themes.removeAll { $0.id == id }
        assignment = assignment.filter { $0.value != id }
    }

    /// Folds or unfolds a section (nil: "Sans thème").
    func toggleCollapsed(_ id: UUID?) {
        guard let id else {
            isUnthemedCollapsed.toggle()
            return
        }
        update(id) { $0.isCollapsed.toggle() }
    }

    /// Unfolds the section of a card, so it can be seen (e.g. opened from the widget).
    func reveal(key: String) {
        if let id = themeID(forKey: key) {
            if themes.first(where: { $0.id == id })?.isCollapsed == true { update(id) { $0.isCollapsed = false } }
        } else if isUnthemedCollapsed {
            isUnthemedCollapsed = false
        }
    }

    private func update(_ id: UUID, _ change: (inout HubTheme) -> Void) {
        guard let index = themes.firstIndex(where: { $0.id == id }) else { return }
        change(&themes[index])
    }

    private func save() {
        if let data = try? JSONEncoder().encode(themes) { defaults.set(data, forKey: Keys.themes) }
        defaults.set(assignment.mapValues(\.uuidString), forKey: Keys.assignment)
        defaults.set(isUnthemedCollapsed, forKey: Keys.unthemedCollapsed)
    }
}
