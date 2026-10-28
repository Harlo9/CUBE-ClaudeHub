import AppKit

/// Animates the mini cube of the menu bar icon, following the widget's cube (it changes
/// at the same moment): blue looking left and right while Claude works, orange with a
/// mini jump while waiting for your answer, green when done, asleep with no session.
///
/// A timer redraws the icon only while something moves (working, waiting), and only
/// when the image actually changes, so the app stays light.
@MainActor
final class MenuBarCube {
    private weak var button: NSStatusBarButton?
    private var mood: CubeAnimator.Mood = .sleeping
    private var moodStartedAt = Date()
    private var timer: Timer?
    private var shownPose: Pose?

    /// What the icon shows: one image, raised by `lift` points during a jump.
    private struct Pose: Equatable {
        var folder: FrameLibrary.Folder
        var number: Int
        var tint: FrameLibrary.Tint
        var lift: CGFloat
    }

    init(button: NSStatusBarButton?) {
        self.button = button
    }

    func show(_ newMood: CubeAnimator.Mood) {
        mood = newMood
        moodStartedAt = Date()
        timer?.invalidate()
        timer = nil
        update()
        guard newMood == .working || newMood == .waiting else { return }
        let timer = Timer(timeInterval: 1 / Constants.MenuBar.framesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer.tolerance = 0.01
        // "common" mode: keeps moving while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func update() {
        let pose = pose(at: Date())
        guard pose != shownPose else { return }
        shownPose = pose
        button?.image = Self.image(for: pose)
    }

    private func pose(at now: Date) -> Pose {
        switch mood {
        case .working:
            return Pose(folder: .working, number: WorkingLoop.frame(at: now.timeIntervalSinceReferenceDate),
                        tint: .blue, lift: 0)
        case .waiting:
            // One mini jump right away, then one every few seconds, like the widget's cube.
            let duration = Constants.Cube.jumpDuration
            let t = now.timeIntervalSince(moodStartedAt).truncatingRemainder(dividingBy: Constants.Cube.reminderJumpInterval)
            let lift = t < duration ? Constants.MenuBar.jumpHeight * sin(.pi * t / duration) : 0
            return Pose(folder: .working, number: 1, tint: .orange, lift: (lift * 4).rounded() / 4)
        case .celebrating, .done:
            return Pose(folder: .working, number: 1, tint: .green, lift: 0)
        case .sleeping:
            return Pose(folder: .sleep, number: Constants.MenuBar.sleepFrame, tint: .blue, lift: 0)
        }
    }

    /// The cube at the menu bar's size (the files are twice as big, for Retina screens),
    /// in a slightly taller image so that the jump is never cut.
    private static func image(for pose: Pose) -> NSImage? {
        guard let cube = FrameLibrary.frame(pose.folder, pose.number, size: .menubar, tint: pose.tint) else { return nil }
        let height = Constants.MenuBar.iconHeight
        let width = height * cube.size.width / cube.size.height
        let size = NSSize(width: width, height: height + Constants.MenuBar.jumpHeight)
        return NSImage(size: size, flipped: false) { _ in
            cube.draw(in: NSRect(x: 0, y: pose.lift, width: width, height: height))
            return true
        }
    }
}
