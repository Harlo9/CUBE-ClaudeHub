import SwiftUI

/// The stack of cards: front card (active project), up to 2 cards below, the halo and the cube.
struct CardStackView: View {
    @ObservedObject var board: SessionBoard
    let cube: CubeAnimator
    let isCollapsed: Bool
    let onToggleCollapsed: () -> Void
    /// Double click on a card: open this session (nil on the "Aucune session" card).
    /// Double click on a card (nil: the "Aucune session" card).
    var onDoubleClick: (Session?) -> Void = { _ in }
    /// The session of the card under the mouse (nil: none), for the right-click menu.
    var onHoverSession: (Session.ID?) -> Void = { _ in }

    @Environment(\.widgetScale) private var scale

    /// Single click waiting to know if a second click follows.
    @State private var pendingClick: Task<Void, Never>?
    @State private var lastClick: (date: Date, location: CGPoint)?

    private typealias Front = Constants.FrontCard

    /// One card of the stack; `session` is nil for the "Aucune session" card.
    private struct CardItem: Identifiable {
        let id: String
        let session: Session?
    }

    var body: some View {
        let others = board.visibleOthers
        let items: [CardItem] = board.active.map { active in
            ([active] + others).map { CardItem(id: $0.id, session: $0) }
        } ?? [CardItem(id: "no-session", session: nil)]
        let front = StackGeometry.rect(for: .front, collapsed: isCollapsed)
        let size = StackGeometry.size(backCount: others.count, collapsed: isCollapsed)
        let cubeLeading = isCollapsed ? (Front.collapsedSide - Front.cubeHeight) / 2 : Front.cubeLeadingPadding

        ZStack(alignment: .topLeading) {
            CubeHalo(cube: cube, layer: .glow)
                .frame(width: front.width * scale, height: front.height * scale)
                .zIndex(0)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let role: CardRole = index == 0 ? .front : .back(index - 1)
                SessionCardView(session: item.session, role: role, isCollapsed: isCollapsed,
                                completedTask: role == .front ? board.activeCelebration?.taskTitle : nil,
                                jumpTrigger: board.cardJumps[item.id] ?? 0)
                    .zIndex(role.zIndex)
            }

            // Above the cards below, under the front card: the entrance ring shows all around.
            CubeHalo(cube: cube, layer: .ring)
                .frame(width: front.width * scale, height: front.height * scale)
                .zIndex(15)

            CubeHalo(cube: cube, layer: .line)
                .frame(width: front.width * scale, height: front.height * scale)
                .zIndex(21)

            CubeView(animator: cube)
                .frame(height: Front.cubeHeight * scale)
                .padding(.leading, cubeLeading * scale)
                .padding(.top, (front.height - Front.cubeHeight) / 2 * scale)
                .zIndex(30)
        }
        .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { location in registerClick(at: location) }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): onHoverSession((backCard(at: location) ?? board.active)?.id)
            case .ended: onHoverSession(nil)
            }
        }
    }

    /// Tells single and double clicks apart with our own (short) delay, instead of the
    /// Mac's 0.5 s: a single click acts as soon as no second click can follow.
    private func registerClick(at location: CGPoint) {
        let now = Date()
        let window = Constants.Window.doubleClickWindow
        if let last = lastClick, now.timeIntervalSince(last.date) < window,
           hypot(location.x - last.location.x, location.y - last.location.y) < 8 {
            pendingClick?.cancel()
            pendingClick = nil
            lastClick = nil
            handleDoubleClick(at: location)
            return
        }
        lastClick = (now, location)
        pendingClick?.cancel()
        pendingClick = Task { @MainActor in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled else { return }
            handleClick(at: location)
        }
    }

    /// One click: on the front card (or the folded cube), folds or unfolds the widget;
    /// on a card below, brings it to the front.
    private func handleClick(at location: CGPoint) {
        guard let back = backCard(at: location) else {
            onToggleCollapsed()
            return
        }
        bringToFront(back)
    }

    /// Double click: opens the card's session in the Cube Hub, like opening an app.
    /// A card below first comes to the front.
    private func handleDoubleClick(at location: CGPoint) {
        let session = backCard(at: location) ?? board.active
        if let back = backCard(at: location) {
            bringToFront(back)
        }
        onDoubleClick(session)
    }

    /// The card below under the click, found from its height in the stack (nil for the
    /// front card, or when the widget is folded).
    private func backCard(at location: CGPoint) -> Session? {
        let y = location.y / scale
        let front = StackGeometry.rect(for: .front, collapsed: isCollapsed)
        guard !isCollapsed, y >= front.maxY else { return nil }
        let index = Int((y - front.maxY) / Constants.BackCard.visibleHeight)
        let others = board.visibleOthers
        return others.indices.contains(index) ? others[index] : nil
    }

    private func bringToFront(_ session: Session) {
        withAnimation(.smooth(duration: Constants.BackCard.swapAnimationDuration)) {
            board.activate(session.id)
        }
    }
}

/// The halo, following what the cube shows right now, so both change together.
private struct CubeHalo: View {
    @ObservedObject var cube: CubeAnimator
    let layer: HaloView.Layer

    var body: some View {
        HaloView(mode: mode, layer: layer, entranceStart: cube.workStartedAt)
    }

    private var mode: HaloView.Mode {
        switch cube.shownMood {
        case .sleeping: .none
        case .working: .working
        case .waiting: .waiting
        case .celebrating, .done: .completed
        }
    }
}
