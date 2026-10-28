import AppKit

/// The projects of the Claude Hub, and the one shown.
///
/// The list of folders is remembered: when the app starts again, the projects come
/// back and resume their last conversation (`claude --continue`) when first shown.
@MainActor
final class HubModel: ObservableObject {
    @Published private(set) var projects: [HubProject] = []
    /// What the list shows on the right: a project of the Hub, or a session running
    /// outside (in Terminal).
    enum Selection: Hashable {
        case project(HubProject.ID)
        case session(Session.ID)
    }

    @Published var selection: Selection?

    /// The project shown, if a project of the Hub is selected.
    var selectedID: HubProject.ID? {
        get { if case .project(let id) = selection { id } else { nil } }
        set { selection = newValue.map { .project($0) } }
    }

    /// The order chosen by dragging the cards of the list (folder paths), remembered.
    @Published private(set) var order: [String]
    /// The themes that group the cards of the list.
    let themes = HubThemes()
    /// The Hub window can be seen (not closed, minimized, on another desktop or fully
    /// covered): its cubes only move then.
    @Published var isOnScreen = false

    private static let foldersKey = "hubProjectFolders"
    private static let orderKey = "hubOrder"

    init() {
        order = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        let saved = UserDefaults.standard.stringArray(forKey: Self.foldersKey) ?? []
        projects = saved
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { HubProject(folder: $0, startCommand: "claude --continue") }
        selectedID = projects.first?.id
    }

    var selected: HubProject? { projects.first { $0.id == selectedID } }

    // MARK: - Order of the list

    /// Key of a card in the chosen order: its folder (the order is kept per project).
    nonisolated static func orderKey(for project: HubProject) -> String { project.folder.path }
    nonisolated static func orderKey(for session: Session) -> String { session.folder?.path ?? session.id }

    /// The items in the chosen order. Those never moved keep their own order, at the end.
    func ordered<Item>(_ items: [Item], key: (Item) -> String) -> [Item] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated()
            .sorted { a, b in
                let rankA = rank[key(a.element)] ?? Int.max
                let rankB = rank[key(b.element)] ?? Int.max
                return rankA != rankB ? rankA < rankB : a.offset < b.offset
            }
            .map(\.element)
    }

    var orderedProjects: [HubProject] { ordered(projects, key: Self.orderKey(for:)) }

    // MARK: - Sections (themes)

    /// One card of the list: a project of the Hub, or a session running in Terminal.
    enum Item: Identifiable {
        case project(HubProject)
        case session(Session)

        /// Row ID in the list.
        var id: String {
            switch self {
            case .project(let project): "project-\(project.id)"
            case .session(let session): "session-\(session.id)"
            }
        }

        /// Order key (its folder): the order and the theme are kept per project.
        var key: String {
            switch self {
            case .project(let project): HubModel.orderKey(for: project)
            case .session(let session): HubModel.orderKey(for: session)
            }
        }

        var selection: Selection {
            switch self {
            case .project(let project): .project(project.id)
            case .session(let session): .session(session.id)
            }
        }
    }

    /// A section of the list: a theme, or "Sans thème" (`theme` nil).
    struct Section: Identifiable {
        let theme: HubTheme?
        let items: [Item]
        let isCollapsed: Bool
        var id: String { theme?.id.uuidString ?? "unthemed" }
    }

    /// The list, by theme: each theme in its order (even empty), then "Sans thème" (only
    /// if it has cards, or if there is no theme at all). Cards in the chosen order.
    func sections(outside: [Session]) -> [Section] {
        let items = ordered(projects.map(Item.project) + outside.map(Item.session), key: \.key)
        var sections = themes.themes.map { theme in
            Section(theme: theme, items: items.filter { themes.themeID(forKey: $0.key) == theme.id },
                    isCollapsed: theme.isCollapsed)
        }
        let unthemed = items.filter { themes.themeID(forKey: $0.key) == nil }
        if !unthemed.isEmpty || themes.themes.isEmpty {
            sections.append(Section(theme: nil, items: unthemed, isCollapsed: themes.isUnthemedCollapsed))
        }
        return sections
    }

    /// Saves the order of a section (`keys`: its cards, in their new order).
    func setOrder(_ keys: [String]) {
        order = keys + order.filter { !keys.contains($0) }
        UserDefaults.standard.set(order, forKey: Self.orderKey)
    }

    /// The project whose terminal is this `tty` (where a Claude session runs).
    func project(forTTY tty: String?) -> HubProject? {
        guard let tty else { return nil }
        return projects.first { $0.tty == tty }
    }

    /// The project already open for this folder, if any.
    func project(forFolder folder: URL) -> HubProject? {
        projects.first { $0.folder.standardizedFileURL == folder.standardizedFileURL }
    }

    /// Opens a new project (a new Claude) in a folder, or shows it if already open.
    @discardableResult
    func open(folder: URL, command: String = "claude") -> HubProject {
        if let existing = project(forFolder: folder) {
            selectedID = existing.id
            return existing
        }
        let project = HubProject(folder: folder, startCommand: command)
        projects.append(project)
        selectedID = project.id
        save()
        return project
    }

    /// Resumes a conversation (by its session ID) in the Hub, in a project of its folder.
    @discardableResult
    func resume(sessionID: String, in folder: URL) -> HubProject {
        let command = "claude --resume \(sessionID)"
        if let existing = project(forFolder: folder), !existing.isRunning {
            existing.restart(command: command)
            selectedID = existing.id
            return existing
        }
        let project = HubProject(folder: folder, startCommand: command)
        projects.append(project)
        selectedID = project.id
        save()
        return project
    }

    /// Stops the project's terminal (and the Claude in it) and removes it from the list.
    func close(_ project: HubProject) {
        project.stop()
        let index = projects.firstIndex { $0.id == project.id }
        projects.removeAll { $0.id == project.id }
        if selectedID == project.id, let index {
            selectedID = projects.isEmpty ? nil : projects[min(index, projects.count - 1)].id
        }
        save()
    }

    var hasRunningProjects: Bool { projects.contains { $0.isRunning } }

    private func save() {
        // Each folder once: when the app starts again, a folder resumes its last conversation.
        var folders: [String] = []
        for path in projects.map(\.folder.path) where !folders.contains(path) { folders.append(path) }
        UserDefaults.standard.set(folders, forKey: Self.foldersKey)
    }
}
