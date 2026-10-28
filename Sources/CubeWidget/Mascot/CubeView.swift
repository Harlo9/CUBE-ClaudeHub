import SwiftUI

/// The cube mascot: shows the animator's current frame, plus the breathing and jumping
/// movements and the color fades done in code.
struct CubeView: View {
    @ObservedObject var animator: CubeAnimator
    var size: FrameLibrary.Size = .card

    @Environment(\.widgetScale) private var scale

    var body: some View {
        // Read here: `jumpHeight` is set just before `jumpCount` changes and redraws this view.
        let jumpHeight = animator.jumpHeight * scale

        Group {
            if case .breathing(let since) = animator.breath {
                // The sleeping cube's slow breathing, played by Core Animation: the app
                // redraws nothing while the cube sleeps.
                BreathingImage(image: animator.frame.flatMap {
                    FrameLibrary.frame($0.folder, $0.number, size: size, tint: animator.tint)
                }, since: since)
                .allowsHitTesting(false)
            } else {
                // Redraws every screen refresh, only while the cube gets back to its normal
                // size after a breath (waking up).
                TimelineView(.animation(paused: animator.breath == .none)) { context in
                    frameImage
                        .scaleEffect(animator.breathScale(at: context.date))
                }
            }
        }
        .keyframeAnimator(initialValue: JumpPose(), trigger: animator.jumpCount) { content, pose in
            content
                .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                .offset(y: -pose.lift * jumpHeight)
        } keyframes: { _ in
            let d = Constants.Cube.jumpDuration
            let squash = Constants.Cube.landingSquash
            // Timeline of one jump: rise 40 %, fall 35 %, squash 10 %, recover 15 %.
            KeyframeTrack(\.lift) {
                LinearKeyframe(1, duration: d * 0.40, timingCurve: .easeOut)
                LinearKeyframe(0, duration: d * 0.35, timingCurve: .easeIn)
                LinearKeyframe(0, duration: d * 0.25)
            }
            KeyframeTrack(\.scaleY) {
                LinearKeyframe(1 + squash * 0.3, duration: d * 0.15, timingCurve: .easeOut)  // stretch on takeoff
                LinearKeyframe(1, duration: d * 0.60)
                LinearKeyframe(1 - squash, duration: d * 0.10, timingCurve: .easeOut)       // squash on landing
                LinearKeyframe(1, duration: d * 0.15, timingCurve: .easeInOut)
            }
            KeyframeTrack(\.scaleX) {
                LinearKeyframe(1 - squash * 0.2, duration: d * 0.15, timingCurve: .easeOut)
                LinearKeyframe(1, duration: d * 0.60)
                LinearKeyframe(1 + squash * 0.7, duration: d * 0.10, timingCurve: .easeOut)
                LinearKeyframe(1, duration: d * 0.15, timingCurve: .easeInOut)
            }
        }
        // Small "pop" when the halo's entrance ring hits the card (start of work).
        .keyframeAnimator(initialValue: 1.0, trigger: animator.workStartedAt) { content, pop in
            content.scaleEffect(pop)
        } keyframes: { _ in
            let h = Constants.Halo.self
            LinearKeyframe(1.0, duration: h.entranceDuration)
            SpringKeyframe(1 + h.entranceCubePop, duration: h.entranceCubePopDuration * 0.3)
            SpringKeyframe(1.0, duration: h.entranceCubePopDuration * 0.7)
        }
        .aspectRatio(FrameLibrary.aspectRatio, contentMode: .fit)
    }

    /// Normal frames, or the eyeless cube with its eyes drawn on top (task completed).
    @ViewBuilder
    private var frameImage: some View {
        if let eyesOffset = animator.eyesOffset {
            tinted { FrameLibrary.eyelessCube(size: size, tint: $0) }
                .overlay { eyes(offset: eyesOffset) }
        } else {
            tinted { tint in
                animator.frame.flatMap { FrameLibrary.frame($0.folder, $0.number, size: size, tint: tint) }
            }
        }
    }

    /// The blue image, with its orange and green versions on top: the one matching
    /// the animator's tint fades in.
    private func tinted(_ image: @escaping (FrameLibrary.Tint) -> NSImage?) -> some View {
        ZStack {
            picture(image(.blue))
            picture(image(.orange))
                .opacity(animator.tint == .orange ? 1 : 0)
            picture(image(.green))
                .opacity(animator.tint == .green ? 1 : 0)
        }
        .animation(.easeInOut(duration: Constants.Cube.colorFadeDuration), value: animator.tint)
    }

    /// The two eyes, placed like in the original images and moved by `offset`.
    private func eyes(offset: CGPoint) -> some View {
        GeometryReader { geometry in
            // Original pixels → points on screen.
            let k = geometry.size.height / Constants.Cube.sourceCrop.height
            ForEach([Constants.Cube.leftEyeRest, Constants.Cube.rightEyeRest], id: \.x) { rest in
                picture(FrameLibrary.eye(size: size))
                    .frame(width: Constants.Cube.eyeSize.width * k, height: Constants.Cube.eyeSize.height * k)
                    .position(
                        x: (rest.x - Constants.Cube.sourceCrop.minX + offset.x + Constants.Cube.eyeSize.width / 2) * k,
                        y: (rest.y - Constants.Cube.sourceCrop.minY + offset.y + Constants.Cube.eyeSize.height / 2) * k
                    )
            }
        }
    }

    @ViewBuilder
    private func picture(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

/// Position and shape of the cube during a jump.
private struct JumpPose {
    /// 0 = on the ground, 1 = top of the jump.
    var lift = 0.0
    var scaleX = 1.0
    var scaleY = 1.0
}
