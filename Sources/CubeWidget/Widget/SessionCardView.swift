import SwiftUI

/// One card of the stack. The same card changes shape with its role, so when a card below
/// comes to the front it smoothly grows into the big card (and the old front card shrinks
/// into its place). The cube is not part of the card: it is drawn once, on top of the stack.
struct SessionCardView: View {
    /// `nil` = no session at all ("Aucune session" card).
    let session: Session?
    let role: CardRole
    let isCollapsed: Bool
    /// Task just completed, shown in green with a ✓ instead of the current task.
    var completedTask: String? = nil
    /// Changes each time this card (below) must jump: its project started waiting.
    var jumpTrigger = 0

    @Environment(\.widgetScale) private var scale

    private typealias Front = Constants.FrontCard
    private typealias Back = Constants.BackCard

    var body: some View {
        let rect = StackGeometry.rect(for: role, collapsed: isCollapsed)
        let shape = RoundedRectangle(cornerRadius: Front.cornerRadius * scale, style: .circular)
        let jumpDepth = Back.jumpDepth * scale   // read here: the animation closure cannot read `scale`

        Color.clear
            .frame(width: rect.width * scale, height: rect.height * scale)
            .overlay(alignment: .topLeading) {
                frontContent
                    .modifier(ContentFade(isVisible: role == .front && !isCollapsed))
            }
            .overlay(alignment: .bottom) {
                backContent
                    .modifier(ContentFade(isVisible: role.isBack))
            }
            .background(CardBackground())
            .clipShape(shape)
            .opacity(role.isBack && isCollapsed ? 0 : 1)
            // Bounce down and back, with a little rebound.
            .keyframeAnimator(initialValue: 0.0, trigger: jumpTrigger) { content, depth in
                content.offset(y: depth * jumpDepth)
            } keyframes: { _ in
                SpringKeyframe(1, duration: Back.jumpDuration * 0.3)
                SpringKeyframe(0, duration: Back.jumpDuration * 0.7, spring: .bouncy)
            }
            .offset(y: rect.minY * scale)
    }

    // MARK: - Front card content

    /// Text of the big card. It always keeps its full size; the card clips it while morphing.
    private var frontContent: some View {
        let cubeSpace = Front.cubeLeadingPadding + Front.cubeHeight * FrameLibrary.aspectRatio + Front.cubeToTextSpacing
        return HStack(spacing: 0) {
            Color.clear.frame(width: cubeSpace * scale)   // room for the cube, drawn on top of the stack
            frontText
            Spacer(minLength: 0)
        }
        .padding(.trailing, Front.trailingPadding * scale)
        .frame(width: Front.width * scale, height: Front.height * scale, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let folder = session?.folder {
                HStack(spacing: Constants.Telegram.remoteIconSpacing * scale) {
                    TelegramReplyToggle(folder: folder, size: Constants.Telegram.bellSize * scale)
                    TelegramBell(folder: folder, size: Constants.Telegram.bellSize * scale)
                }
                    .padding(.top, Constants.Telegram.frontBellTopInset * scale)
                    .padding(.trailing, Constants.Telegram.frontBellTrailingInset * scale)
            }
        }
    }

    @ViewBuilder
    private var frontText: some View {
        if let session {
            VStack(alignment: .leading, spacing: Front.lineSpacing * scale) {
                Text(session.projectName)
                    .font(.system(size: Front.projectNameFontSize * scale, weight: .bold))
                    .foregroundStyle(Constants.Colors.primaryText)
                    // Keeps a long name from running under the bell.
                    .padding(.trailing, session.folder == nil ? 0
                             : Constants.Telegram.bellSize * Constants.Telegram.bellHitScale * scale)

                if let completedTask {
                    Text("✓ \(completedTask.isEmpty ? "Terminé" : completedTask)")
                        .font(.system(size: Front.taskFontSize * scale))
                        .foregroundStyle(Constants.Colors.completed)
                        .transition(.opacity)
                } else if let task = session.currentTask {
                    Text(task)
                        .font(.system(size: Front.taskFontSize * scale))
                        .foregroundStyle(Constants.Colors.primaryText)
                        .transition(.opacity)
                }

                // Redrawn every minute, for the session duration.
                TimelineView(.everyMinute) { _ in
                    statusLine(session)
                        .font(.system(size: Front.statusFontSize * scale))
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
        } else {
            Text("Aucune session")
                .font(.system(size: Front.projectNameFontSize * scale, weight: .semibold))
                .foregroundStyle(Constants.Colors.secondaryText)
        }
    }

    /// "bosse · 34 min · 210k tokens", with the status in its color.
    private func statusLine(_ session: Session) -> Text {
        let details = "  ·  \(SessionFormat.duration(since: session.startedAt))  ·  \(SessionFormat.tokens(session.contextTokens))"
        return Text(session.status.longLabel).foregroundStyle(session.status.color)
            + Text(details).foregroundStyle(Constants.Colors.secondaryText)
    }

    // MARK: - Card below content

    /// One line in the visible band: colored dot, project name, status.
    @ViewBuilder
    private var backContent: some View {
        if let session {
            HStack(spacing: Back.dotToNameSpacing * scale) {
                Circle()
                    .fill(session.status.color)
                    .frame(width: Back.dotSize * scale, height: Back.dotSize * scale)
                    .keyframeAnimator(initialValue: 1.0, trigger: jumpTrigger) { dot, size in
                        dot.scaleEffect(size)
                    } keyframes: { _ in
                        SpringKeyframe(Back.jumpDotScale, duration: Back.jumpDuration * 0.3)
                        SpringKeyframe(1, duration: Back.jumpDuration * 0.7)
                    }
                Text(session.projectName)
                    .fontWeight(.semibold)
                    .foregroundStyle(Constants.Colors.backCardName)
                Spacer(minLength: 8 * scale)
                HStack(spacing: Constants.Telegram.backBellToStatusSpacing * scale) {
                    if let folder = session.folder {
                        TelegramReplyToggle(folder: folder, size: Constants.Telegram.backBellSize * scale)
                        TelegramBell(folder: folder, size: Constants.Telegram.backBellSize * scale)
                    }
                    Text(session.status.shortLabel)
                        .foregroundStyle(session.status.color)
                }
            }
            .font(.system(size: Back.fontSize * scale))
            .lineLimit(1)
            .padding(.horizontal, Back.horizontalPadding * scale)
            .frame(width: Front.width * scale, height: Back.visibleHeight * scale)
        }
    }
}

/// The text of a card that changes shape: the leaving text disappears quickly, the
/// arriving text appears once the card has (almost) taken its new shape, so the two
/// never mix in the middle of the move.
private struct ContentFade: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        let back = Constants.BackCard.self
        content
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)   // a hidden bell cannot be clicked
            .animation(isVisible
                       ? .easeOut(duration: back.contentFadeInDuration).delay(back.contentFadeInDelay)
                       : .easeIn(duration: back.contentFadeOutDuration),
                       value: isVisible)
    }
}

extension SessionStatus {
    var color: Color {
        switch self {
        case .working: Constants.Colors.working
        case .waiting: Constants.Colors.waiting
        case .done: Constants.Colors.completed
        }
    }
}
