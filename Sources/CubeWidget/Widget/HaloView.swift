import SwiftUI

/// The halo around the front card.
///
/// It is drawn in three layers: `.glow` (the soft light spilling outside) is placed behind
/// all the cards, so it can never darken the cards below; `.ring` (the entrance ring) sits
/// between the cards below and the front card, so it shows all around the front card;
/// `.line` (the thin bright line) is placed on the front card's outline.
struct HaloView: View {
    enum Mode: Equatable {
        case none
        /// Blue light running around the card.
        case working
        /// Still orange outline.
        case waiting
        /// Still green outline (task completed).
        case completed
    }

    enum Layer {
        case glow
        case ring
        case line
    }

    let mode: Mode
    let layer: Layer
    /// When the project started working: the entrance animation plays from then.
    var entranceStart: Date? = nil

    @Environment(\.widgetScale) private var scale
    /// Set during the entrance, so the frame-by-frame drawing stops right after it.
    @State private var isEntranceRunning = false

    private typealias H = Constants.Halo

    var body: some View {
        ZStack {
            if layer == .ring {
                // Not part of the fade between halos: the ring shows at full strength at once.
                TimelineView(.animation(paused: !entrancePlaying)) { context in
                    Canvas { context2, size in
                        if let t = entranceTime(at: context.date) {
                            drawEntranceRing(in: context2, size: size, time: t)
                        }
                    }
                }
            } else {
                // The entrance (the lit outline gathering into the running light): the
                // TimelineView redraws it every screen refresh, only while it plays.
                TimelineView(.animation(paused: mode != .working || !entrancePlaying)) { context in
                    Canvas { context2, size in
                        drawRunningLight(in: context2, size: size, date: context.date)
                    }
                }
                .opacity(mode == .working && entrancePlaying ? 1 : 0)

                // Then the light runs by itself (Core Animation): the app redraws nothing.
                RunningLightView(isGlow: layer == .glow, isRunning: mode == .working && !entrancePlaying)
                    .opacity(mode == .working && !entrancePlaying ? 1 : 0)

                Canvas { context, size in
                    drawStillOutline(in: context, size: size,
                                     color: Constants.Colors.waiting.opacity(H.waitingOpacity))
                }
                .opacity(mode == .waiting ? 1 : 0)

                Canvas { context, size in
                    drawStillOutline(in: context, size: size,
                                     color: Constants.Colors.completed.opacity(H.completedOpacity))
                }
                .opacity(mode == .completed ? 1 : 0)
            }
        }
        // Extra room around the card so the glow is not cut.
        .padding(-Constants.Window.haloMargin * scale)
        .animation(.easeInOut(duration: H.fadeDuration), value: mode)
        .allowsHitTesting(false)
        .task(id: entranceStart) {
            guard let entranceStart else { return isEntranceRunning = false }
            let remaining = H.entranceDuration + H.entranceGatherDuration - Date().timeIntervalSince(entranceStart)
            guard remaining > 0 else { return isEntranceRunning = false }
            isEntranceRunning = true
            try? await Task.sleep(for: .seconds(remaining + 0.02))
            if !Task.isCancelled { isEntranceRunning = false }
        }
    }

    /// The entrance is playing: from the moment it starts (before the task above has run)
    /// until the task says it is over.
    private var entrancePlaying: Bool { isEntranceRunning || isEntrancePlaying(at: Date()) }

    // MARK: - Drawing

    /// The card's outline, starting at the middle of the top edge and going clockwise.
    /// `inset` moves the line inside the card (half the line width keeps it on the border);
    /// a negative inset moves it outside.
    private func outline(canvasSize: CGSize, inset: CGFloat) -> Path {
        Self.outline(canvasSize: canvasSize, inset: inset, scale: scale)
    }

    /// The card's outline in a halo canvas of `canvasSize` (the card plus the halo margin),
    /// starting at the middle of the top edge and going clockwise (y going down).
    static func outline(canvasSize: CGSize, inset: CGFloat, scale: CGFloat) -> Path {
        let margin = Constants.Window.haloMargin * scale
        let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: margin + inset, dy: margin + inset)
        let r = max(0, min(Constants.FrontCard.cornerRadius * scale - inset, rect.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addRelativeArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                            startAngle: .degrees(-90), delta: .degrees(90))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addRelativeArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                            startAngle: .degrees(0), delta: .degrees(90))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addRelativeArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                            startAngle: .degrees(90), delta: .degrees(90))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addRelativeArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                            startAngle: .degrees(180), delta: .degrees(90))
        path.closeSubpath()
        return path
    }

    private func drawRunningLight(in context: GraphicsContext, size: CGSize, date: Date) {
        let path = outline(canvasSize: size, inset: H.workingLineWidth / 2)
        let color = Constants.Colors.working
        // Position of the head of the light along the outline (0 → 1 = one lap).
        let head = (date.timeIntervalSinceReferenceDate / H.lapDuration).truncatingRemainder(dividingBy: 1)

        // Normal running light: a quarter of the outline, fading behind the head.
        var trailLength = H.trailFraction
        var fadeCurve = 1.6
        var intensity = H.workingMaxOpacity
        if let t = entranceTime(at: date) {
            let impact = H.entranceDuration
            if t < impact {
                // The ring is closing in: the outline lights up just before it lands.
                let rise = max(0, (t - impact * 0.8) / (impact * 0.2))
                if rise == 0 { return }
                (trailLength, fadeCurve, intensity) = (1, 0, H.entranceMaxOpacity * rise)
            } else {
                // Landed: the fully lit outline gathers into the running light.
                let g = easeInOut(min(1, (t - impact) / H.entranceGatherDuration))
                trailLength = 1 + (H.trailFraction - 1) * g
                fadeCurve = 1.6 * g
                intensity = H.entranceMaxOpacity + (H.workingMaxOpacity - H.entranceMaxOpacity) * g
            }
        }

        // The trail is drawn as small pieces that get more transparent away from the head.
        func drawTrail(_ context: GraphicsContext, lineWidth: CGFloat) {
            let pieces = H.trailPieces
            for k in 0..<pieces {
                let end = head - trailLength * Double(k) / Double(pieces)
                let start = head - trailLength * Double(k + 1) / Double(pieces)
                let opacity = intensity * pow(1 - Double(k) / Double(pieces), fadeCurve)
                for (from, to) in wrapped(start, end) {
                    context.stroke(path.trimmedPath(from: from, to: to),
                                   with: .color(color.opacity(opacity)), lineWidth: lineWidth)
                }
            }
        }

        switch layer {
        case .glow:
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: H.workingGlowBlur * scale))
                drawTrail(glow, lineWidth: H.workingGlowWidth * scale)
            }
        case .line:
            drawTrail(context, lineWidth: H.workingLineWidth)
        case .ring:
            break
        }
    }

    private func drawStillOutline(in context: GraphicsContext, size: CGSize, color: Color) {
        switch layer {
        case .glow:
            let path = outline(canvasSize: size, inset: H.waitingLineWidth / 2)
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: H.waitingGlowBlur * scale))
                glow.stroke(path, with: .color(color), lineWidth: H.waitingGlowWidth * scale)
            }
        case .line:
            context.stroke(outline(canvasSize: size, inset: H.waitingLineWidth / 2),
                           with: .color(color), lineWidth: H.waitingLineWidth)
        case .ring:
            break
        }
    }

    // MARK: - Entrance

    /// Time since the entrance started, or nil when no entrance is playing.
    private func entranceTime(at date: Date) -> Double? {
        guard let entranceStart else { return nil }
        let t = date.timeIntervalSince(entranceStart)
        return t >= 0 && t < H.entranceDuration + H.entranceGatherDuration ? t : nil
    }

    private func isEntrancePlaying(at date: Date) -> Bool {
        guard let entranceStart else { return false }
        return date.timeIntervalSince(entranceStart) < H.entranceDuration + H.entranceGatherDuration
    }

    /// A ring larger than the card closes in on it, slowly then faster and faster, and
    /// disappears under the card when it hits it.
    private func drawEntranceRing(in context: GraphicsContext, size: CGSize, time t: Double) {
        let progress = t / H.entranceDuration
        guard progress < 1 else { return }
        let accelerating = pow(progress, 2.2)
        let path = outline(canvasSize: size, inset: -H.entranceInflate * scale * (1 - accelerating))
        // Fades in quickly, gets brighter and thinner as it closes in.
        let opacity = H.entranceMaxOpacity * min(1, progress / 0.2) * (0.6 + 0.4 * accelerating)
        let width = H.entranceLineWidth * scale * (1.8 - 0.8 * accelerating)
        let color = Constants.Colors.working.opacity(opacity)
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: H.entranceGlowBlur * scale))
            glow.stroke(path, with: .color(color), lineWidth: width * 2.5)
        }
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    // MARK: - Helpers

    private func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// Splits a portion of the outline that crosses the starting point into two portions.
    private func wrapped(_ start: Double, _ end: Double) -> [(Double, Double)] {
        var start = start, end = end
        if end < 0 { start += 1; end += 1 }
        if start < 0 { return [(start + 1, 1), (0, end)] }
        return [(start, end)]
    }
}
