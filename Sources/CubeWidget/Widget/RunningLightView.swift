import AppKit
import SwiftUI

/// The blue light running around the front card ("bosse"), animated by Core Animation:
/// the app describes the movement once (one lap every `lapDuration`, forever) and macOS
/// plays it, so the app redraws nothing while it runs. Same look as the frame-by-frame
/// drawing of `HaloView` (same outline, trail and pieces), and in step with it, so the
/// entrance hands over to it without a jump.
struct RunningLightView: NSViewRepresentable {
    /// The soft glow spilling outside (`true`), or the thin line on the outline.
    let isGlow: Bool
    /// The light runs; otherwise its animation is removed (nothing left to play).
    let isRunning: Bool

    @Environment(\.widgetScale) private var scale

    func makeNSView(context: Context) -> RunningLightNSView { RunningLightNSView() }

    func updateNSView(_ view: RunningLightNSView, context: Context) {
        view.configure(isGlow: isGlow, scale: scale, isRunning: isRunning)
    }
}

final class RunningLightNSView: NSView {
    private typealias H = Constants.Halo

    /// Holds the pieces of the trail (and the blur, for the glow).
    private let container = CALayer()
    private var pieces: [CAShapeLayer] = []
    private var isGlow: Bool?
    private var scale: CGFloat = 1
    private var isRunning = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Needed for the glow's blur (a Core Image filter on a layer).
        layerUsesCoreImageFilters = true
        layer?.addSublayer(container)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Purely decorative: clicks go through.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(isGlow: Bool, scale: CGFloat, isRunning: Bool) {
        if self.isGlow != isGlow || self.scale != scale {
            self.isGlow = isGlow
            self.scale = scale
            buildPieces()
        }
        if isRunning != self.isRunning {
            self.isRunning = isRunning
            isRunning ? startAnimations() : pieces.forEach { $0.removeAllAnimations() }
        }
    }

    override func layout() {
        super.layout()
        updatePaths()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let backingScale = window?.backingScaleFactor ?? 2
        pieces.forEach { $0.contentsScale = backingScale }
    }

    // MARK: - Layers

    private func buildPieces() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pieces.forEach { $0.removeFromSuperlayer() }
        let glow = isGlow ?? false
        let color = NSColor(Constants.Colors.working)
        let count = H.trailPieces
        pieces = (0..<count).map { k in
            let piece = CAShapeLayer()
            piece.fillColor = nil
            piece.lineWidth = glow ? H.workingGlowWidth * scale : H.workingLineWidth
            // Same fading as the frame-by-frame trail: more transparent away from the head.
            let opacity = H.workingMaxOpacity * pow(1 - Double(k) / Double(count), 1.6)
            piece.strokeColor = color.withAlphaComponent(color.alphaComponent * opacity).cgColor
            // Nothing shown when the animation is removed.
            piece.strokeStart = 0
            piece.strokeEnd = 0
            piece.contentsScale = window?.backingScaleFactor ?? 2
            container.addSublayer(piece)
            return piece
        }
        container.filters = glow
            ? [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: H.workingGlowBlur * scale])].compactMap { $0 }
            : nil
        CATransaction.commit()
        updatePaths()
        if isRunning { startAnimations() }
    }

    /// The outline, twice in a row: the light moves along the second lap, with its trail
    /// reaching back into the first one, so it never has to jump from the end to the start.
    private func updatePaths() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        let lap = HaloView.outline(canvasSize: bounds.size, inset: H.workingLineWidth / 2, scale: scale)
        var twoLaps = lap
        twoLaps.addPath(lap)
        // `HaloView` draws with y going down; this view's y goes up.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        let path = twoLaps.applying(isFlipped ? .identity : flip).cgPath
        for piece in pieces {
            piece.frame = bounds
            piece.path = path
        }
        CATransaction.commit()
    }

    /// One lap every `lapDuration`, repeated forever, starting where the frame-by-frame
    /// drawing would be now (both follow the clock).
    private func startAnimations() {
        let phase = (Date().timeIntervalSinceReferenceDate / H.lapDuration).truncatingRemainder(dividingBy: 1)
        let begin = container.convertTime(CACurrentMediaTime(), from: nil) - phase * H.lapDuration
        let halfTrail = H.trailFraction / 2   // the path is two laps long
        for (k, piece) in pieces.enumerated() {
            let end = 0.5 - halfTrail * Double(k) / Double(pieces.count)
            let start = 0.5 - halfTrail * Double(k + 1) / Double(pieces.count)
            for (key, from) in [("strokeEnd", end), ("strokeStart", start)] {
                let animation = CABasicAnimation(keyPath: key)
                animation.fromValue = from
                animation.toValue = from + 0.5
                animation.duration = H.lapDuration
                animation.repeatCount = .infinity
                animation.beginTime = begin
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                piece.add(animation, forKey: key)
            }
        }
    }
}
