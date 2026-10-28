import SwiftUI

/// A sleeping cube, growing and shrinking slowly (`breathAmplitude`, `breathPeriod`),
/// animated by Core Animation: macOS plays the movement, the app redraws nothing. Follows
/// the same curve as `CubeAnimator.breathScale(at:)`, from `since`, so the cube can go
/// back to the frame-by-frame drawing (waking up) without a jump.
struct BreathingImage: NSViewRepresentable {
    let image: NSImage?
    /// Start of the breathing (the cube is at its normal size then).
    let since: Date
    /// The point that stays in place while the cube grows.
    var anchor: UnitPoint = .center

    func makeNSView(context: Context) -> BreathingImageView { BreathingImageView() }

    func updateNSView(_ view: BreathingImageView, context: Context) {
        view.configure(image: image, since: since, anchor: anchor)
    }
}

final class BreathingImageView: NSView {
    private let imageLayer = CALayer()
    private var since: Date?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.minificationFilter = .trilinear
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    func configure(image: NSImage?, since: Date, anchor: UnitPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        // SwiftUI's y goes down, this view's y goes up.
        imageLayer.anchorPoint = CGPoint(x: anchor.x, y: 1 - anchor.y)
        imageLayer.frame = bounds
        CATransaction.commit()
        guard since != self.since else { return }
        self.since = since
        // 1 → 1 + amplitude → 1 over one period, smooth at both ends (close to the cosine
        // of `breathScale`), repeated forever, in step with `since`.
        let period = Constants.Cube.breathPeriod
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 1
        breath.toValue = 1 + Constants.Cube.breathAmplitude
        breath.duration = period / 2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(controlPoints: 0.37, 0, 0.63, 1)
        breath.beginTime = imageLayer.convertTime(CACurrentMediaTime(), from: nil) - Date().timeIntervalSince(since)
        imageLayer.add(breath, forKey: "breath")
    }
}
