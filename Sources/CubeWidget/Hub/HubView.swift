import SwiftUI

/// The Claude Hub window: on the left, every Claude session as a small card with its ice
/// cube (the Hub's projects, then the sessions running in Terminal, like the widget's
/// cards); on the right, the selected session: its cube and details above its terminal.
struct HubView: View {
    @ObservedObject var hub: HubModel
    @ObservedObject var board: SessionBoard
    let onNewProject: () -> Void
    let onBringIntoHub: (Session) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        NavigationSplitView {
            HubSidebar(hub: hub, themes: hub.themes, board: board, onNewProject: onNewProject, onBringIntoHub: onBringIntoHub)
                .navigationSplitViewColumnWidth(min: 220, ideal: Constants.Hub.sidebarWidth, max: 360)
                .toolbar {
                    ToolbarItem {
                        Button(action: onNewProject) {
                            Label("Nouvelle session", systemImage: "plus")
                        }
                        .help("Nouvelle session Claude (⌘N)")
                    }
                }
        } detail: {
            detail
                .navigationTitle("Claude Hub")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: onOpenSettings) {
                            Label("Réglages", systemImage: "gearshape")
                        }
                        .help("Réglages (⌘,)")
                    }
                }
        }
        // The cubes stand still while the window cannot be seen.
        .environment(\.hubCubesMove, hub.isOnScreen)
    }

    @ViewBuilder
    private var detail: some View {
        switch hub.selection {
        case .project:
            if let project = hub.selected {
                ProjectTerminal(project: project, session: board.session(onTTY: project.tty))
            }
        case .session(let id):
            if let session = board.sessions.first(where: { $0.id == id }) {
                OutsideSessionView(session: session, onBringIntoHub: onBringIntoHub)
            } else {
                HubEmptyPage(text: "Cette session est fermée.", onNewProject: onNewProject)
            }
        case nil:
            HubEmptyPage(text: "Choisis une session dans la liste, ou ouvre un dossier pour y lancer Claude.",
                         onNewProject: onNewProject)
        }
    }
}

// MARK: - The list on the left

/// The list of sessions, grouped by theme: a small black card each, the selected one lit
/// in its state's color. Cards can be dragged up or down to change the order, within
/// their theme or into another one.
struct HubSidebar: View {
    @ObservedObject var hub: HubModel
    @ObservedObject var themes: HubThemes
    @ObservedObject var board: SessionBoard
    let onNewProject: () -> Void
    let onBringIntoHub: (Session) -> Void

    /// The card being dragged, if any.
    @State private var drag: Drag?
    /// The card just dropped, still lifted (above the others) while it settles.
    @State private var lifted: String?
    /// The themes' panels as they were when the card was dropped, kept while it settles
    /// (the list's new measures arrive a moment later).
    @State private var settlingPanels: [ThemePanelPlace]?
    /// Where every card, section title and "Vide" line sits in the list (measured), to
    /// know which place the dragged card is over.
    @State private var rowFrames: [String: CGRect] = [:]
    /// The theme whose name is being typed, right in the list, if any.
    @State private var themeEdit: ThemeEdit?
    @State private var themeName = ""
    @FocusState private var isNameFocused: Bool

    private static let space = "hubList"

    private enum ThemeEdit: Equatable {
        /// A new theme; the card it was asked from (its order key), to put it in.
        case new(assignKey: String?)
        case rename(UUID)
    }

    private struct Drag: Equatable {
        let rowID: String
        /// The list when the drag started.
        let layout: DragLayout
        /// How far it moved, up or down.
        var translation: CGFloat
    }

    /// What the list shows, top to bottom. A single list (not one per section), so that a
    /// card moved to another theme stays the same card on screen and slides to its place.
    private enum ListElement: Identifiable {
        case header(HubModel.Section)
        /// "Vide": an open theme without cards.
        case empty(HubModel.Section)
        /// A card; on its theme's panel or not ("Sans thème").
        case row(HubModel.Item, isThemed: Bool)
        /// The name of a new theme, being typed.
        case newThemeField

        var id: String {
            switch self {
            case .header(let section): "header-\(section.id)"
            case .empty(let section): "empty-\(section.id)"
            case .row(let item, _): item.id
            case .newThemeField: "newThemeField"
            }
        }
    }

    /// Sessions of the widget that do not run in the Hub (in Terminal, mostly), in the
    /// chosen order.
    private var outsideSessions: [Session] {
        hub.ordered(board.sessions.filter { hub.project(forTTY: $0.tty) == nil },
                    key: HubModel.orderKey(for:))
    }

    var body: some View {
        let sections = hub.sections(outside: outsideSessions)
        let positions = Self.positions(in: sections)
        let layout = DragLayout(sections: sections)
        let dropTarget = drag.flatMap(dropTargetID(of:))
        let panels = drag == nil ? settlingPanels ?? self.panels(in: layout) : self.panels(in: drag?.layout ?? layout)
        let themed = Set(sections.filter { $0.theme != nil }.map(\.id))
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Hub.rowSpacing) {
                if themes.themes.isEmpty, sections.allSatisfy({ $0.items.isEmpty }) {
                    if case .new = themeEdit { themeNameField(color: newThemeColor) }
                } else {
                    ForEach(elements(of: sections, themed: themed)) { element in
                        switch element {
                        case .header(let section):
                            Group {
                                if let theme = section.theme, themeEdit == .rename(theme.id) {
                                    themeNameField(color: theme.color)
                                } else {
                                    sectionHeader(section, isDropTarget: dropTarget == section.id)
                                }
                            }
                            .measured(element.id, in: Self.space)
                            .makingRoom(shift(for: element.id))
                        case .empty(let section):
                            Text("Vide · glisse une session ici")
                                .font(.system(size: Constants.Hub.rowDetailFontSize))
                                .foregroundStyle(Constants.Colors.secondaryText.opacity(0.6))
                                .padding(.leading, Self.cardLeading + 4
                                         + (themed.contains(section.id) ? Constants.Hub.themePanelInset : 0))
                                .measured(element.id, in: Self.space)
                                .makingRoom(shift(for: element.id))
                                .transition(.opacity)
                        case .row(let item, let isThemed):
                            reorderable(row(for: item), rowID: item.id, layout: layout,
                                        position: positions[item.id] ?? 0,
                                        inset: isThemed ? Constants.Hub.themePanelInset : 0)
                                .transition(.opacity)
                        case .newThemeField:
                            themeNameField(color: newThemeColor)
                        }
                    }
                }
                NewSessionCard(action: onNewProject)
                    .padding(.leading, Self.cardLeading)
                    .padding(.top, Constants.Hub.newSessionCardTopPadding)
            }
            .padding(Constants.Hub.sidebarPadding)
            // Each open theme's cards sit on a panel tinted with its color, under its tab.
            .background(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(panels) { panel in
                        ThemePanel(color: panel.color, isLit: dropTarget == panel.id)
                            .frame(height: panel.height)
                            .offset(y: panel.top)
                            .transaction(value: [panel.top, panel.height]) { transaction in
                                if transaction.animation == nil {
                                    transaction.animation = .smooth(duration: drag == nil
                                        ? Constants.Hub.themeAnimationDuration
                                        : Constants.Hub.reorderAnimationDuration)
                                }
                            }
                            .transition(.opacity)
                    }
                }
                .padding(.leading, Constants.Hub.sidebarPadding + Self.cardLeading)
                .padding(.trailing, Constants.Hub.sidebarPadding)
            }
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
        }
        // Always visible at the bottom of the list, even when it scrolls.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AddThemeButton { startThemeEdit(.new(assignKey: nil)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Hub.sidebarBackground)
        // Right click on the empty part of the list.
        .contextMenu {
            Button("Nouvelle session…", action: onNewProject)
            Button("Nouveau thème…") { startThemeEdit(.new(assignKey: nil)) }
        }
    }

    /// Each section's title, then its cards (or "Vide") if it is open. A new theme's name
    /// is typed just above "Sans thème" (at the end if there is none).
    private func elements(of sections: [HubModel.Section], themed: Set<String>) -> [ListElement] {
        var isNewTheme = false
        if case .new = themeEdit { isNewTheme = true }
        var elements: [ListElement] = []
        for section in sections {
            if section.theme == nil, isNewTheme { elements.append(.newThemeField) }
            elements.append(.header(section))
            guard !section.isCollapsed else { continue }
            if section.items.isEmpty {
                elements.append(.empty(section))
            }
            elements += section.items.map { ListElement.row($0, isThemed: themed.contains(section.id)) }
        }
        if !sections.contains(where: { $0.theme == nil }), isNewTheme { elements.append(.newThemeField) }
        return elements
    }

    /// Place numbers (1, 2, 3…) of the cards shown, over the whole list.
    private static func positions(in sections: [HubModel.Section]) -> [String: Int] {
        var positions: [String: Int] = [:]
        for item in sections.filter({ !$0.isCollapsed }).flatMap(\.items) {
            positions[item.id] = positions.count + 1
        }
        return positions
    }

    /// Where the cards start, after their place number.
    private static var cardLeading: CGFloat { Constants.Hub.positionWidth + Constants.Hub.positionToCardSpacing }

    // MARK: Cards

    @ViewBuilder
    private func row(for item: HubModel.Item) -> some View {
        switch item {
        case .project(let project):
            HubProjectRow(project: project, session: board.session(onTTY: project.tty),
                          isSelected: hub.selection == .project(project.id))
                .onTapGesture { hub.selectedID = project.id }
                .contextMenu {
                    Button("Nouvelle session…", action: onNewProject)
                    Divider()
                    themeMenu(for: item.key)
                    TelegramMenuItem(folder: project.folder)
                    TelegramRemoteMenuItem(folder: project.folder)
                    Divider()
                    Button("Fermer « \(project.name) »") { hub.close(project) }
                }
        case .session(let session):
            HubRow(name: session.projectName, session: session, folder: session.folder,
                   fallbackLabel: "", isSelected: hub.selection == .session(session.id), isInTerminal: true)
                .onTapGesture { hub.selection = .session(session.id) }
                .contextMenu {
                    Button("Nouvelle session…", action: onNewProject)
                    Divider()
                    Button("Ramener dans le Hub") { onBringIntoHub(session) }
                        .disabled(!OutsideSessionView.canBring(session))
                    Button("Afficher dans Terminal") {
                        if let tty = session.tty { TerminalFocus.focus(tty: tty) }
                    }
                    Divider()
                    themeMenu(for: item.key)
                    if let folder = session.folder {
                        TelegramMenuItem(folder: folder)
                    }
                }
        }
    }

    /// "Thème ▸": the themes (the card's own checked), "Sans thème", "Nouveau thème…".
    private func themeMenu(for key: String) -> some View {
        let current = themes.themeID(forKey: key)
        return Menu("Thème") {
            ForEach(themes.themes) { theme in
                Button(current == theme.id ? "✓ \(theme.name)" : theme.name) { setTheme(theme.id, forKey: key) }
            }
            Button(current == nil ? "✓ Sans thème" : "Sans thème") { setTheme(nil, forKey: key) }
            Divider()
            Button("Nouveau thème…") { startThemeEdit(.new(assignKey: key)) }
        }
    }

    private func setTheme(_ id: UUID?, forKey key: String) {
        withAnimation(.smooth(duration: Constants.Hub.themeAnimationDuration)) {
            themes.setTheme(id, forKey: key)
        }
    }

    // MARK: Naming a theme

    /// The color a new theme will get (the next one of the palette).
    private var newThemeColor: Color {
        Constants.Hub.themeColors[themes.themes.count % Constants.Hub.themeColors.count]
    }

    /// Shows the name field in the list (instead of a dialog window, which could block
    /// the whole app). Done once the right-click menu has closed.
    private func startThemeEdit(_ edit: ThemeEdit) {
        DispatchQueue.main.async {
            if case .rename(let id) = edit {
                themeName = themes.themes.first(where: { $0.id == id })?.name ?? ""
            } else {
                themeName = ""
            }
            withAnimation(.smooth(duration: Constants.Hub.themeAnimationDuration)) { themeEdit = edit }
        }
    }

    /// Return, or a click elsewhere: creates or renames the theme (nothing if the name is empty).
    private func commitThemeEdit() {
        guard let edit = themeEdit else { return }
        let name = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.smooth(duration: Constants.Hub.themeAnimationDuration)) {
            themeEdit = nil
            guard !name.isEmpty else { return }
            switch edit {
            case .new(let key):
                let id = themes.add(named: name)
                if let key { themes.setTheme(id, forKey: key) }
            case .rename(let id):
                themes.rename(id, to: name)
            }
        }
    }

    /// The field where a theme's name is typed, in place of its title. Return confirms,
    /// Escape cancels.
    private func themeNameField(color: Color) -> some View {
        let edit = themeEdit
        let shape = RoundedRectangle(cornerRadius: Constants.Hub.themeFieldCornerRadius, style: .continuous)
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: Constants.Hub.themeDotSize, height: Constants.Hub.themeDotSize)
            TextField("Nom du thème (Freelance, Projet perso…)", text: $themeName)
                .textFieldStyle(.plain)
                .font(.system(size: Constants.Hub.themeFieldFontSize, weight: .semibold))
                .foregroundStyle(Constants.Colors.primaryText)
                .focused($isNameFocused)
                .onSubmit(commitThemeEdit)
                .onExitCommand {
                    withAnimation(.smooth(duration: Constants.Hub.themeAnimationDuration)) { themeEdit = nil }
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(shape.fill(Constants.Hub.rowHoverBackground))
        .overlay(shape.strokeBorder(color.opacity(0.6), lineWidth: 1))
        .padding(.top, Constants.Hub.themeHeaderTopPadding)
        .padding(.leading, Self.cardLeading)
        .transition(.opacity)
        .onAppear { DispatchQueue.main.async { isNameFocused = true } }
        // Clicking elsewhere confirms, like Return.
        .onChange(of: isNameFocused) { _, focused in
            if !focused, themeEdit == edit { commitThemeEdit() }
        }
    }

    // MARK: Section titles

    /// A section's title: color dot, name, number of cards, arrow. A theme's title is a
    /// tab tinted with its color, on top of its cards' panel (like a binder divider); "Sans
    /// thème" stays a plain gray title. A click folds or unfolds it; a right click offers
    /// the theme's options. Lit while a card from another section would be dropped in it.
    private func sectionHeader(_ section: HubModel.Section, isDropTarget: Bool) -> some View {
        let title = section.theme?.name ?? (themes.themes.isEmpty ? "Sessions" : "Sans thème")
        let label = HStack(spacing: 6) {
            if let theme = section.theme {
                Circle()
                    .fill(theme.color)
                    .frame(width: Constants.Hub.themeDotSize, height: Constants.Hub.themeDotSize)
            }
            Text(title.uppercased())
                .font(.system(size: Constants.Hub.sectionTitleFontSize, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(section.theme?.color
                    ?? (isDropTarget ? Constants.Colors.primaryText : Constants.Colors.secondaryText))
                .lineLimit(1)
            Text("\(section.items.count)")
                .font(.system(size: Constants.Hub.sectionTitleFontSize, weight: .medium).monospacedDigit())
                .foregroundStyle(Constants.Colors.secondaryText.opacity(0.55))
            if section.theme == nil { Spacer(minLength: 0) }
            Image(systemName: "chevron.down")
                .font(.system(size: Constants.Hub.sectionTitleFontSize - 1, weight: .semibold))
                .foregroundStyle(Constants.Colors.secondaryText.opacity(0.7))
                .rotationEffect(.degrees(section.isCollapsed ? -90 : 0))
        }
        return Group {
            if let theme = section.theme {
                HStack(spacing: 0) {
                    label
                        .padding(.horizontal, Constants.Hub.themeTabHorizontalPadding)
                        .padding(.vertical, Constants.Hub.themeTabVerticalPadding)
                        .background(ThemeTab(color: theme.color, isOpen: !section.isCollapsed, isLit: isDropTarget))
                    Spacer(minLength: 0)
                }
            } else {
                label
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.Hub.themeFieldCornerRadius, style: .continuous)
                            .fill(Constants.Colors.primaryText.opacity(isDropTarget ? Constants.Hub.dropTargetOpacity : 0))
                            .padding(.vertical, -Constants.Hub.dropTargetVerticalPadding)
                    )
                    .animation(.easeOut(duration: 0.15), value: isDropTarget)
            }
        }
        .padding(.top, Constants.Hub.themeHeaderTopPadding)
        .padding(.leading, Self.cardLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.smooth(duration: Constants.Hub.themeAnimationDuration)) {
                themes.toggleCollapsed(section.theme?.id)
            }
        }
        .contextMenu {
            if let theme = section.theme {
                Button("Renommer…") { startThemeEdit(.rename(theme.id)) }
                Menu("Couleur") {
                    ForEach(Constants.Hub.themeColorNames.indices, id: \.self) { index in
                        let name = Constants.Hub.themeColorNames[index]
                        Button(theme.colorIndex == index ? "✓ \(name)" : name) { themes.setColor(index, of: theme.id) }
                    }
                }
                Button("Monter") { move(theme.id, by: -1) }
                    .disabled(themes.themes.first?.id == theme.id)
                Button("Descendre") { move(theme.id, by: 1) }
                    .disabled(themes.themes.last?.id == theme.id)
                Divider()
                Button("Supprimer le thème") {
                    withAnimation(.smooth(duration: Constants.Hub.themeAnimationDuration)) { themes.delete(theme.id) }
                }
            } else {
                Button("Nouveau thème…") { startThemeEdit(.new(assignKey: nil)) }
            }
        }
    }

    private func move(_ id: UUID, by step: Int) {
        withAnimation(.smooth(duration: Constants.Hub.themeAnimationDuration)) {
            themes.move(id, by: step)
        }
    }

    // MARK: Changing the order by dragging

    /// A card with its place number on its left (the number stays in place), which can
    /// be dragged up or down, within its section or into another one. The card follows
    /// the mouse exactly and only vertically; everything below or above it (cards,
    /// section titles) slides away to make room; once released, it settles into its new
    /// place.
    private func reorderable(_ card: some View, rowID: String, layout: DragLayout, position: Int,
                             inset: CGFloat) -> some View {
        let isLifted = drag?.rowID == rowID || lifted == rowID
        return HStack(spacing: Constants.Hub.positionToCardSpacing) {
            Text("\(position)")
                .font(.system(size: Constants.Hub.positionFontSize, weight: .medium).monospacedDigit())
                .foregroundStyle(Constants.Colors.secondaryText.opacity(Constants.Hub.positionOpacity))
                .frame(width: Constants.Hub.positionWidth, alignment: .trailing)
            card
                .padding(.horizontal, inset)
                .scaleEffect(isLifted ? Constants.Hub.dragScale : 1)
                .shadow(color: .black.opacity(isLifted ? Constants.Hub.dragShadowOpacity : 0),
                        radius: Constants.Hub.dragShadowRadius, y: 4)
                .animation(.easeOut(duration: 0.15), value: isLifted)
                .makingRoom(shift(for: rowID))
                .offset(y: drag?.rowID == rowID ? drag?.translation ?? 0 : 0)
                .gesture(dragGesture(rowID: rowID, layout: layout))
        }
        .zIndex(isLifted ? 1 : 0)
        .measured(rowID, in: Self.space)
    }

    private func dragGesture(rowID: String, layout: DragLayout) -> some Gesture {
        DragGesture(minimumDistance: Constants.Hub.dragStartDistance, coordinateSpace: .named(Self.space))
            .onChanged { value in
                var current = drag ?? Drag(rowID: rowID, layout: layout, translation: 0)
                guard current.rowID == rowID else { return }
                current.translation = clamped(value.translation.height, for: current)
                drag = current   // no animation: the card stays exactly under the mouse
            }
            .onEnded { _ in
                guard let current = drag, current.rowID == rowID else { return }
                drop(current)
            }
    }

    /// Where the dragged card's top sits if it is put after the first `count` other
    /// places of the list (titles, "Vide" lines, cards), once they have made room for it.
    private func top(after count: Int, in drag: Drag) -> CGFloat? {
        let places = drag.layout.places
        guard let from = drag.layout.index(of: drag.rowID), count >= 1, count < places.count,
              let dragged = rowFrames[drag.rowID] else { return nil }
        let previous = count - 1 < from ? count - 1 : count
        guard let frame = rowFrames[places[previous].id] else { return nil }
        let slot = dragged.height + Constants.Hub.rowSpacing
        return frame.maxY - (previous > from ? slot : 0) + Constants.Hub.rowSpacing
    }

    /// The card stays within the list: no higher than the first section's first place,
    /// no lower than after the last title or card.
    private func clamped(_ translation: CGFloat, for drag: Drag) -> CGFloat {
        guard let frame = rowFrames[drag.rowID],
              let highest = top(after: 1, in: drag),
              let lowest = top(after: drag.layout.places.count - 1, in: drag) else { return 0 }
        return min(max(translation, highest - frame.minY), lowest - frame.minY)
    }

    /// How many other places come before the dragged card: the place nearest to where
    /// it is (it takes a card's place once it has gone halfway past it).
    private func insertion(of drag: Drag) -> Int? {
        guard let frame = rowFrames[drag.rowID], drag.layout.places.count > 1 else { return nil }
        let top = frame.minY + drag.translation
        return (1..<drag.layout.places.count).min { a, b in
            abs((self.top(after: a, in: drag) ?? .infinity) - top) < abs((self.top(after: b, in: drag) ?? .infinity) - top)
        }
    }

    /// The section the dragged card would be dropped in, and its place there. Just
    /// under a title: first card of that section (last, if the section is folded: the
    /// card goes in, hidden with the others).
    private func destination(of drag: Drag) -> (section: Int, index: Int)? {
        guard let count = insertion(of: drag), let from = drag.layout.index(of: drag.rowID) else { return nil }
        let previous = drag.layout.places[count - 1 < from ? count - 1 : count]
        let section = drag.layout.sections[previous.section]
        let cards = section.cardIDs.filter { $0 != drag.rowID }
        switch previous.kind {
        case .header: return (previous.section, section.isCollapsed ? cards.count : 0)
        case .empty: return (previous.section, 0)
        case .card: return (previous.section, (cards.firstIndex(of: previous.id) ?? cards.count - 1) + 1)
        }
    }

    /// The section whose title lights up: the one the card would be dropped in, if it is
    /// not its own.
    private func dropTargetID(of drag: Drag) -> String? {
        guard let destination = destination(of: drag),
              let from = drag.layout.sections.firstIndex(where: { $0.cardIDs.contains(drag.rowID) }),
              destination.section != from else { return nil }
        return drag.layout.sections[destination.section].id
    }

    /// How much a place that is not dragged moves to make room: by the dragged card's height.
    private func shift(for id: String) -> CGFloat {
        guard let drag, id != drag.rowID,
              let count = insertion(of: drag),
              let from = drag.layout.index(of: drag.rowID),
              let index = drag.layout.index(of: id),
              let frame = rowFrames[drag.rowID] else { return 0 }
        let slot = frame.height + Constants.Hub.rowSpacing
        let other = index > from ? index - 1 : index
        if index > from, other < count { return -slot }
        if index < from, other >= count { return slot }
        return 0
    }

    /// The tinted panel behind each open theme's cards: from under its tab to below its
    /// last card. While a card is dragged, it follows the places that make room, and
    /// stretches to hold the gap where the card would be dropped.
    private func panels(in layout: DragLayout) -> [ThemePanelPlace] {
        let destination = drag.flatMap(destination(of:))
        return layout.sections.indices.compactMap { number in
            let section = layout.sections[number]
            let headerID = "header-\(section.id)"
            guard !section.isCollapsed, let themeID = section.themeID,
                  let theme = themes.themes.first(where: { $0.id == themeID }),
                  let header = rowFrames[headerID] else { return nil }
            let top = header.maxY + shift(for: headerID)
            var bottom = top
            for place in layout.places where place.section == number && place.kind != .header && place.id != drag?.rowID {
                if let frame = rowFrames[place.id] { bottom = max(bottom, frame.maxY + shift(for: place.id)) }
            }
            if let drag, destination?.section == number, let count = insertion(of: drag),
               let gap = self.top(after: count, in: drag), let dragged = rowFrames[drag.rowID] {
                bottom = max(bottom, gap + dragged.height)
            }
            return ThemePanelPlace(id: section.id, color: theme.color, top: top,
                                   height: bottom - top + Constants.Hub.themePanelBottomPadding)
        }
    }

    /// Saves the new order (and the new theme, if it changed section). The list moves to
    /// its new layout in the same movement as the card settling into its place: the cards
    /// that made room stay still, the dragged card slides from the mouse to its place.
    private func drop(_ drag: Drag) {
        let sections = drag.layout.sections
        guard let destination = destination(of: drag),
              let from = sections.firstIndex(where: { $0.cardIDs.contains(drag.rowID) }),
              let index = sections[from].cardIDs.firstIndex(of: drag.rowID) else {
            withAnimation(.smooth(duration: Constants.Hub.settleDuration)) { self.drag = nil }
            return
        }
        let key = sections[from].orderKeys[index]
        let target = sections[destination.section]
        var keys = target.orderKeys.filter { $0 != key }
        keys.insert(key, at: min(destination.index, keys.count))
        lifted = drag.rowID
        settlingPanels = panels(in: drag.layout)
        withAnimation(.smooth(duration: Constants.Hub.settleDuration)) {
            if destination.section != from {
                themes.setTheme(target.themeID, forKey: key)
            }
            hub.setOrder(keys)
            self.drag = nil
        } completion: {
            if lifted == drag.rowID {
                lifted = nil
                settlingPanels = nil
            }
        }
    }
}

/// The list as a drag sees it: every place (section titles, "Vide" lines, cards) from top
/// to bottom, and the sections a card can be dropped in.
private struct DragLayout: Equatable {
    struct Place: Equatable {
        enum Kind: Equatable { case header, empty, card }
        let id: String
        let kind: Kind
        /// Index of its section.
        let section: Int
    }

    struct Section: Equatable {
        let id: String
        let themeID: UUID?
        /// Its cards (row IDs and order keys), in the order shown, even when folded.
        let cardIDs: [String]
        let orderKeys: [String]
        let isCollapsed: Bool
    }

    private(set) var places: [Place] = []
    private(set) var sections: [Section] = []

    init(sections: [HubModel.Section]) {
        for (number, section) in sections.enumerated() {
            self.sections.append(Section(id: section.id, themeID: section.theme?.id,
                                         cardIDs: section.items.map(\.id), orderKeys: section.items.map(\.key),
                                         isCollapsed: section.isCollapsed))
            places.append(Place(id: "header-\(section.id)", kind: .header, section: number))
            guard !section.isCollapsed else { continue }
            if section.items.isEmpty {
                places.append(Place(id: "empty-\(section.id)", kind: .empty, section: number))
            }
            places += section.items.map { Place(id: $0.id, kind: .card, section: number) }
        }
    }

    func index(of id: String) -> Int? {
        places.firstIndex { $0.id == id }
    }
}

/// Where a theme's panel sits in the list (its section's ID).
private struct ThemePanelPlace: Identifiable, Equatable {
    let id: String
    let color: Color
    let top: CGFloat
    let height: CGFloat
}

/// A theme's title background: a tab tinted with its color, open at the bottom onto its
/// cards' panel (closed all around when the theme is folded).
private struct ThemeTab: View {
    let color: Color
    let isOpen: Bool
    let isLit: Bool

    var body: some View {
        let radius = Constants.Hub.themeTabCornerRadius
        let bottom = isOpen ? 0 : radius
        let shape = UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: radius,
                                           style: .continuous)
        shape
            .fill(color.opacity(Constants.Hub.themeTabOpacity + (isLit ? Constants.Hub.dropTargetOpacity : 0)))
            .overlay(
                shape
                    .strokeBorder(color.opacity(Constants.Hub.themeOutlineOpacity), lineWidth: 1)
                    // Open tab: no line at the bottom, the panel's own line runs under it.
                    .mask(alignment: .top) { Rectangle().padding(.bottom, isOpen ? 1 : 0) }
            )
            .animation(.easeOut(duration: 0.15), value: isLit)
    }
}

/// The panel behind an open theme's cards: tinted with its color, with a thin outline;
/// square at the top left, where its tab sits.
private struct ThemePanel: View {
    let color: Color
    let isLit: Bool

    var body: some View {
        let radius = Constants.Hub.themePanelCornerRadius
        let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: radius, topTrailingRadius: radius,
                                           style: .continuous)
        shape
            .fill(color.opacity(Constants.Hub.themePanelOpacity + (isLit ? Constants.Hub.dropTargetOpacity / 2 : 0)))
            .overlay(shape.strokeBorder(color.opacity(Constants.Hub.themeOutlineOpacity), lineWidth: 1))
            .animation(.easeOut(duration: 0.15), value: isLit)
    }
}

private extension View {
    /// Records where this place sits in the list, before any move.
    func measured(_ id: String, in space: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: RowFrames.self, value: [id: proxy.frame(in: .named(space))])
        })
    }

    /// Moves a place of the list to make room for the dragged card: smoothly while the
    /// card is dragged, and in the same movement as the rest of the list when it is dropped.
    func makingRoom(_ shift: CGFloat) -> some View {
        offset(y: shift)
            .transaction(value: shift) { transaction in
                if transaction.animation == nil {
                    transaction.animation = .smooth(duration: Constants.Hub.reorderAnimationDuration)
                }
            }
    }
}

/// "+ Thème", at the bottom of the list: creates a new theme. Discreet gray, lit
/// under the mouse.
private struct AddThemeButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label("Thème", systemImage: "plus")
                .font(.system(size: Constants.Hub.addThemeFontSize, weight: .medium))
                .foregroundStyle(isHovered ? Constants.Colors.primaryText : Constants.Colors.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isHovered ? Constants.Hub.rowHoverBackground : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("Créer un nouveau thème pour ranger les sessions")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.Hub.sidebarPadding)
        .padding(.vertical, 8)
        .background(Constants.Hub.sidebarBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Constants.Colors.cardBorder.opacity(0.5)).frame(height: 1)
        }
    }
}

/// The dashed card at the bottom of the list: a new Claude session (asks for a folder).
/// Lit under the mouse.
private struct NewSessionCard: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let dash = StrokeStyle(lineWidth: Constants.Hub.newSessionCardDashWidth,
                               dash: Constants.Hub.newSessionCardDash)
        let shape = RoundedRectangle(cornerRadius: Constants.Hub.rowCornerRadius, style: .continuous)
        let color = isHovered ? Constants.Colors.primaryText : Constants.Colors.secondaryText
        HStack(spacing: 10) {
            // Where the cube would be: a dashed square with a "+".
            RoundedRectangle(cornerRadius: Constants.Hub.newSessionCubeCornerRadius, style: .continuous)
                .strokeBorder(style: dash)
                .overlay(Image(systemName: "plus").font(.system(size: Constants.Hub.rowNameFontSize, weight: .medium)))
                .frame(width: Constants.Hub.newSessionCubeSize, height: Constants.Hub.newSessionCubeSize)
                .frame(width: Constants.Hub.rowCubeSize, height: Constants.Hub.rowCubeSize)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nouveau cube")
                    .font(.system(size: Constants.Hub.rowNameFontSize, weight: .semibold))
                Text("Choisir un dossier pour y lancer Claude")
                    .font(.system(size: Constants.Hub.rowDetailFontSize))
                    .opacity(0.75)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color.opacity(isHovered ? 1 : Constants.Hub.newSessionCardOpacity))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(shape.fill(isHovered ? Constants.Hub.rowHoverBackground : .clear))
        .overlay(shape.strokeBorder(color.opacity(isHovered ? 0.7 : Constants.Hub.newSessionCardOpacity), style: dash))
        .contentShape(shape)
        .onTapGesture(perform: action)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("Nouvelle session Claude (⌘N)")
    }
}

/// The measured frames of the list's cards, by row ID.
private struct RowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A project of the Hub in the list: its Claude session, or the state of its terminal.
private struct HubProjectRow: View {
    @ObservedObject var project: HubProject
    let session: Session?
    let isSelected: Bool

    var body: some View {
        HubRow(name: project.name, session: session, folder: project.folder,
               fallbackLabel: project.isRunning ? "terminal ouvert" : "fermé", isSelected: isSelected)
    }
}

/// One card of the list: the cube, the name, the status (and duration), the task.
private struct HubRow: View {
    let name: String
    let session: Session?
    /// The project's folder, for its Telegram bell.
    let folder: URL?
    /// Shown instead of the status when there is no Claude session.
    let fallbackLabel: String
    let isSelected: Bool
    /// The session runs in Terminal (not in the Hub): a small "Terminal" tag.
    var isInTerminal = false
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Constants.Hub.rowCornerRadius, style: .continuous)
        let accent = session?.status.color ?? Color.white.opacity(0.35)
        HStack(spacing: 10) {
            HubCube(mood: .init(session?.status), size: Constants.Hub.rowCubeSize,
                    phase: Double(abs(name.hashValue % 1000)) / 100)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: Constants.Hub.rowNameFontSize, weight: .semibold))
                        .foregroundStyle(Constants.Colors.primaryText)
                    if isInTerminal {
                        Text("Terminal")
                            .font(.system(size: Constants.Hub.terminalTagFontSize, weight: .medium))
                            .foregroundStyle(Constants.Colors.secondaryText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().strokeBorder(Constants.Colors.cardBorder, lineWidth: 1))
                            .fixedSize()
                    }
                }
                HubStatusLine(session: session, fallbackLabel: fallbackLabel,
                              fontSize: Constants.Hub.rowDetailFontSize, showsTokens: false)
                if let task = session?.currentTask {
                    Text(task)
                        .font(.system(size: Constants.Hub.rowDetailFontSize))
                        .foregroundStyle(Constants.Colors.secondaryText)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
            if let folder {
                HStack(spacing: Constants.Telegram.remoteIconSpacing) {
                    TelegramReplyToggle(folder: folder)
                    TelegramBell(folder: folder)
                }
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(shape.fill(isSelected ? Constants.Hub.rowSelectedBackground
                               : isHovered ? Constants.Hub.rowHoverBackground
                               : Constants.Colors.cardBackground))
        .overlay(shape.strokeBorder(isSelected ? accent.opacity(0.85) : Constants.Colors.cardBorder,
                                    lineWidth: Constants.FrontCard.borderWidth))
        .shadow(color: isSelected ? accent.opacity(Constants.Hub.selectedGlowOpacity) : .clear,
                radius: Constants.Hub.selectedGlowRadius)
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: Constants.Halo.fadeDuration), value: isSelected)
    }
}

/// "bosse · 34 min · 210k tokens", the status in its color, the rest in gray.
private struct HubStatusLine: View {
    let session: Session?
    let fallbackLabel: String
    let fontSize: CGFloat
    let showsTokens: Bool

    var body: some View {
        TimelineView(.everyMinute) { _ in
            line.font(.system(size: fontSize))
        }
    }

    private var line: Text {
        guard let session else {
            return Text(fallbackLabel).foregroundColor(Constants.Colors.secondaryText)
        }
        var details = "  ·  \(SessionFormat.duration(since: session.startedAt))"
        if showsTokens { details += "  ·  \(SessionFormat.tokens(session.contextTokens))" }
        return Text(session.status.longLabel).foregroundColor(session.status.color)
            + Text(details).foregroundColor(Constants.Colors.secondaryText)
    }
}

// MARK: - The right side

/// The band above a terminal: the session's cube, name, status and current task, with
/// a thin line in its state's color.
struct HubSessionHeader: View {
    let name: String
    let session: Session?
    let fallbackLabel: String

    var body: some View {
        HStack(spacing: 14) {
            HubCube(mood: .init(session?.status), size: Constants.Hub.headerCubeSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: Constants.Hub.headerNameFontSize, weight: .bold))
                    .foregroundStyle(Constants.Colors.primaryText)
                HubStatusLine(session: session, fallbackLabel: fallbackLabel,
                              fontSize: Constants.Hub.headerDetailFontSize, showsTokens: true)
                if let task = session?.currentTask {
                    Text(task)
                        .font(.system(size: Constants.Hub.headerDetailFontSize))
                        .foregroundStyle(Constants.Colors.secondaryText)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Constants.Colors.cardBackground)
        .overlay(alignment: .bottom) {
            let accent = session?.status.color ?? Constants.Colors.cardBorder
            LinearGradient(colors: [accent.opacity(0.7), Constants.Colors.cardBorder.opacity(0.6)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .animation(.easeOut(duration: Constants.Halo.fadeDuration), value: session?.status)
        }
    }
}

/// A project's terminal, under its header; a button to start it again once closed.
private struct ProjectTerminal: View {
    @ObservedObject var project: HubProject
    let session: Session?

    var body: some View {
        VStack(spacing: 0) {
            HubSessionHeader(name: project.name, session: session,
                             fallbackLabel: project.isRunning ? "terminal ouvert" : "terminal fermé")
            TerminalHost(project: project)
                .overlay {
                    if !project.isRunning, project.tty == nil, project.hasBeenStarted {
                        VStack(spacing: 12) {
                            HubCube(mood: .asleep, size: 70)
                            Text("Le terminal de ce projet est fermé.")
                                .foregroundStyle(Constants.Colors.primaryText)
                            Button("Relancer Claude (reprend la conversation)") { project.restart() }
                                .controlSize(.large)
                        }
                        .padding(24)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
        }
        .background(Constants.Colors.cardBackground)
    }
}

/// A session running in Terminal: it cannot be shown here (Terminal owns it), but it
/// can be brought into the Hub once Claude has finished its answer.
struct OutsideSessionView: View {
    let session: Session
    let onBringIntoHub: (Session) -> Void

    static func canBring(_ session: Session) -> Bool {
        session.status == .done && session.pid != nil && session.folder != nil
    }

    var body: some View {
        VStack(spacing: 10) {
            HubCube(mood: .init(session.status), size: Constants.Hub.bigCubeSize)
                .padding(.bottom, 8)
            Text(session.projectName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Constants.Colors.primaryText)
            HubStatusLine(session: session, fallbackLabel: "", fontSize: 13, showsTokens: true)
            if let task = session.currentTask {
                Text(task)
                    .font(.system(size: 13))
                    .foregroundStyle(Constants.Colors.secondaryText)
                    .lineLimit(1)
            }
            Text("Cette session tourne dans Terminal.")
                .font(.system(size: 13))
                .foregroundStyle(Constants.Colors.secondaryText)
                .padding(.top, 14)
            HStack(spacing: 10) {
                Button("Afficher dans Terminal") {
                    if let tty = session.tty { TerminalFocus.focus(tty: tty) }
                }
                .disabled(session.tty == nil)
                Button("Ramener dans le Hub") { onBringIntoHub(session) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!Self.canBring(session))
            }
            .controlSize(.large)
            .padding(.top, 4)
            Text(Self.canBring(session)
                 ? "Claude sera fermé dans Terminal, puis la conversation reprendra ici."
                 : "Possible quand Claude a fini de répondre (statut « terminé »).")
                .font(.caption)
                .foregroundStyle(Constants.Colors.secondaryText)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Colors.cardBackground)
    }
}

/// Nothing selected (or the session closed): a sleeping cube.
private struct HubEmptyPage: View {
    let text: String
    let onNewProject: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HubCube(mood: .asleep, size: Constants.Hub.bigCubeSize)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Constants.Colors.secondaryText)
                .multilineTextAlignment(.center)
            Button("Nouvelle session…", action: onNewProject)
                .controlSize(.large)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Colors.cardBackground)
    }
}

/// Shows the terminal view of the selected project. The terminal views are kept by the
/// projects: switching only swaps which one is shown, so nothing is restarted.
private struct TerminalHost: NSViewRepresentable {
    let project: HubProject

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.show(project)
    }
}

final class TerminalContainerView: NSView {
    private var project: HubProject?

    @MainActor
    func show(_ newProject: HubProject) {
        guard newProject !== project else { return }
        project?.terminal.removeFromSuperview()
        project = newProject
        let terminal = newProject.terminal
        terminal.frame = terminalFrame
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
        needsLayout = true
        window?.makeFirstResponder(terminal)
    }

    override func layout() {
        super.layout()
        guard let project, bounds.width > 0, bounds.height > 0 else { return }
        project.terminal.frame = terminalFrame
        // Started here, once the terminal has its real size.
        MainActor.assumeIsolated { project.startIfNeeded() }
    }

    private var terminalFrame: NSRect {
        bounds.insetBy(dx: Constants.Hub.terminalPadding, dy: Constants.Hub.terminalPadding / 2)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let terminal = project?.terminal { window?.makeFirstResponder(terminal) }
    }
}
