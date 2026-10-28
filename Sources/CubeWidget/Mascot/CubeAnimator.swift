import AppKit

/// Plays the cube animations and moves from one to the other without ever cutting
/// an animation in the middle.
///
/// Set `mood` from outside; a single loop (the "director") plays the sequences and only
/// looks at `mood` at clean points: centered frame with eyes open, end of a jump,
/// end of a breath, end of the falling-asleep or waking-up sequence.
@MainActor
final class CubeAnimator: ObservableObject {
    enum Mood: CaseIterable {
        case sleeping
        case working
        case waiting
        /// A task was just completed: green cube following the mouse with its eyes.
        case celebrating
        /// Claude finished its answer: the cube stays green and still until you write.
        case done
    }

    /// Breathing state while asleep; the view turns it into a scale with `breathScale(at:)`.
    enum Breath: Equatable {
        case none
        case breathing(since: Date)
        case releasing(from: Double, since: Date)
    }

    /// What the cube should show.
    @Published var mood: Mood {
        didSet { if mood != oldValue { resumeDirector() } }
    }

    @Published private(set) var frame: CubeFrame?
    /// The mood whose animation is playing right now (`mood` is the one asked for: the cube
    /// first finishes its current move). The halo follows it, so both change together.
    @Published private(set) var shownMood: Mood
    /// When the cube last started working after waiting or sleeping (when the "bosse"
    /// sound plays); the halo plays its entrance from then.
    @Published private(set) var workStartedAt: Date?
    /// Color of the cube (blue, orange while waiting, green for a completed task);
    /// the view fades from one to the other.
    @Published private(set) var tint: FrameLibrary.Tint = .blue

    /// While not nil, the cube is shown without its eyes and the eyes are drawn on top,
    /// moved by this offset from their rest position (in pixels of the original images).
    @Published private(set) var eyesOffset: CGPoint?

    /// Distance from the cube's center to the mouse, in screen points (x: negative = mouse
    /// on the left; y: negative = mouse below). Set by the window, which knows where the cube is.
    var mouseOffset: (() -> CGVector?)?
    @Published private(set) var breath: Breath = .none
    /// Incremented for each jump; the view plays a jump every time it changes.
    @Published private(set) var jumpCount = 0
    /// Height of the jump being played, in points (before the widget scale).
    private(set) var jumpHeight: CGFloat = 0

    private typealias C = Constants.Cube

    private var director: Task<Void, Never>?
    /// Sound to play when the matching animation starts (see `cue`).
    private var cuedSound: (sound: SoundPlayer.Sound, at: Date)?
    private var pendingWait: CheckedContinuation<Void, Never>?
    private var waitID = 0

    /// - Parameter mood: initial mood. When it is `.sleeping`, the cube first falls asleep.
    init(mood: Mood) {
        self.mood = mood
        shownMood = mood
        frame = CubeFrame(folder: mood == .sleeping ? .sleep : .working, number: 1)
        director = Task { [weak self] in await self?.direct() }
    }

    deinit {
        director?.cancel()
    }

    // MARK: - Director

    private func direct() async {
        var isAsleep = false
        while !Task.isCancelled {
            if isAsleep {
                if mood == .sleeping {
                    await breatheUntilMoodChanges()
                } else {
                    await stopBreathing()
                    await wakeUp()
                    isAsleep = false
                }
                continue
            }
            switch mood {
            case .sleeping:
                await fallAsleep()
                isAsleep = true
            case .working:
                await workUntilMoodChanges()
            case .waiting:
                await jumpUntilMoodChanges()
            case .celebrating:
                await followMouseUntilMoodChanges()
            case .done:
                await stayGreenUntilMoodChanges()
            }
        }
    }

    // MARK: - Sequences

    /// Travail 01 → 21 in a loop, left only on a centered eyes-open frame.
    private func workUntilMoodChanges() async {
        shownMood = .working
        if playCuedSound(.working) { workStartedAt = Date() }
        var number = 1
        while !Task.isCancelled {
            show(.working, number)
            let duration = workingDuration(number)
            if C.workingExitFrames.contains(number) {
                if mood != .working { return }
                await waitForMoodChange(timeout: duration)
                if mood != .working { return }
            } else if mood == .working, duration > Double(C.workingFrameMs) / 1000 {
                // Long look to the side: cut short if the mood changes, then the eyes
                // come back to the center at normal speed.
                await waitForMoodChange(timeout: duration)
            } else {
                await sleep(mood == .working ? duration : min(duration, Double(C.workingFrameMs) / 1000))
            }
            number = number % 21 + 1
        }
    }

    /// Turns orange, jumps a few times, then a small reminder jump every few seconds.
    private func jumpUntilMoodChanges() async {
        show(.working, 1)
        tint = .orange
        shownMood = .waiting
        playCuedSound(.waiting)
        defer { tint = .blue }
        for _ in 0..<C.initialJumpCount {
            await jump(height: C.jumpHeight)
        }
        while mood == .waiting, !Task.isCancelled {
            await waitForMoodChange(timeout: C.reminderJumpInterval)
            if mood != .waiting { return }
            await jump(height: C.smallJumpHeight)
        }
    }

    /// Turns green, jumps once and moves its eyes toward the mouse (in x and y).
    /// The eyes softly catch up with their target about 60 times per second. When the
    /// mood changes, the eyes first come back to rest and the cube turns blue again,
    /// then the normal frames take over (the eyes at rest match frame 01 exactly).
    private func followMouseUntilMoodChanges() async {
        show(.working, 1)
        var offset = CGPoint.zero
        eyesOffset = offset
        tint = .green
        shownMood = .celebrating
        playCuedSound(.taskCompleted)
        defer { eyesOffset = nil }
        // One jump right away; the eyes keep following the mouse during it.
        if C.celebrationJumpHeight > 0 {
            jumpHeight = C.celebrationJumpHeight
            jumpCount += 1
        }

        var lastUpdate = Date()
        // After Claude finished its answer, the eyes keep following the mouse for a while.
        let followUntil = Date().addingTimeInterval(C.doneEyeFollowDuration)
        while !Task.isCancelled {
            let following = mood == .celebrating || (mood == .done && Date() < followUntil)
            let leaving = !following
            let target = leaving ? .zero : eyesTarget()
            // Move a part of the remaining way, based on the real time elapsed (smooth even
            // if an update comes a little late).
            let now = Date()
            let follow = 1 - exp(-now.timeIntervalSince(lastUpdate) / C.eyeFollowSmoothing)
            lastUpdate = now
            offset.x += (target.x - offset.x) * follow
            offset.y += (target.y - offset.y) * follow

            if leaving, hypot(offset.x, offset.y) < 0.5 {
                eyesOffset = .zero
                // Claude finished its answer: the cube stays green.
                if mood == .done { return }
                tint = .blue
                shownMood = mood   // the halo fades with the cube's color
                await sleep(Constants.Cube.colorFadeDuration)
                return
            }
            // Only redraw when the eyes really move (nothing to do while the mouse is still).
            let moved = eyesOffset.map { abs($0.x - offset.x) >= 0.01 || abs($0.y - offset.y) >= 0.01 } ?? true
            if moved { eyesOffset = offset }
            // Another task completed while already green: its sound plays right away.
            if !leaving { playCuedSound(.taskCompleted) }
            await sleep(1 / C.eyeUpdatesPerSecond)
        }
    }

    /// Green and still (centered frame) until the mood changes; then back to blue,
    /// unless the next state is green too.
    private func stayGreenUntilMoodChanges() async {
        show(.working, 1)
        tint = .green
        shownMood = .done
        await waitForMoodChange(timeout: nil)
        if mood != .celebrating { tint = .blue }
    }

    /// Where the eyes should be for the current mouse position, in original pixels.
    /// The farther the mouse, the closer to `eyeMaxOffset`, never beyond it.
    private func eyesTarget() -> CGPoint {
        guard let distance = mouseOffset?() else { return .zero }
        let maxOffset = C.eyeMaxOffset, reach = C.eyeFollowDistance
        // tanh smoothly goes from 0 (mouse on the cube) toward 1 (mouse far away).
        // The screen's y goes up while the image's y goes down, hence the minus sign.
        return CGPoint(x: maxOffset * tanh(distance.dx / reach),
                       y: -maxOffset * tanh(distance.dy / reach))
    }

    private func fallAsleep() async {
        shownMood = .sleeping
        SoundPlayer.play(.fallAsleep)
        for number in 1...10 {
            show(.sleep, number)
            await sleep(Double(C.fallAsleepLongFramesMs[number] ?? C.fallAsleepFrameMs) / 1000)
        }
    }

    private func wakeUp() async {
        for number in C.wakeUpSleepFrames {
            show(.sleep, number)
            await sleep(Double(C.wakeUpFrameMs) / 1000)
        }
        show(.working, 1)
        await sleep(Double(C.wakeUpFrameMs) / 1000)
        for number in C.wakeUpBlinkFrames {
            show(.working, number)
            await sleep(Double(C.blinkFrameMs) / 1000)
        }
    }

    private func breatheUntilMoodChanges() async {
        show(.sleep, 10)
        if breath == .none { breath = .breathing(since: Date()) }
        await waitForMoodChange(timeout: nil)
    }

    /// Smoothly brings the cube back to its normal size, from wherever the breath was.
    private func stopBreathing() async {
        guard breath != .none else { return }
        breath = .releasing(from: breathScale(at: Date()), since: Date())
        await sleep(C.breathReleaseDuration)
        breath = .none
    }

    private func jump(height: CGFloat) async {
        jumpHeight = height
        jumpCount += 1
        await sleep(C.jumpDuration)
    }

    // MARK: - Breath

    /// Scale of the cube at a given moment (1 = normal size).
    func breathScale(at date: Date) -> Double {
        switch breath {
        case .none:
            return 1
        case .breathing(let since):
            // Smooth in-and-out: 1 → 1 + amplitude → 1 over one period.
            let phase = date.timeIntervalSince(since) / C.breathPeriod * 2 * .pi
            return 1 + C.breathAmplitude * (1 - cos(phase)) / 2
        case .releasing(let from, let since):
            let progress = min(1, date.timeIntervalSince(since) / C.breathReleaseDuration)
            let eased = 1 - (1 - progress) * (1 - progress)
            return from + (1 - from) * eased
        }
    }

    // MARK: - Sounds

    /// Asks for a sound that goes with an animation (work loop, waiting jump, green state):
    /// it plays when that animation actually starts, so sound and movement happen together.
    /// The cube first finishes its current move cleanly (or wakes up), which takes a moment.
    /// A newer cue replaces an older one.
    func cue(_ sound: SoundPlayer.Sound) {
        cuedSound = (sound, Date())
    }

    /// Plays the cued sound if it is this one, and tells if it did. A cue that waited too
    /// long is dropped (e.g. a task completed, but the session started waiting before
    /// the cube turned green).
    @discardableResult
    private func playCuedSound(_ sound: SoundPlayer.Sound) -> Bool {
        guard let cued = cuedSound else { return false }
        if Date().timeIntervalSince(cued.at) > Constants.Sound.cueMaxDelay {
            cuedSound = nil
        } else if cued.sound == sound {
            cuedSound = nil
            SoundPlayer.play(sound)
            return true
        }
        return false
    }

    // MARK: - Helpers

    /// Shows the eyes at a fixed offset, green. Only used by `--snapshot --eyes x,y`.
    func showEyesForSnapshot(_ offset: CGPoint) {
        director?.cancel()
        eyesOffset = offset
        tint = .green
    }

    private func show(_ folder: FrameLibrary.Folder, _ number: Int) {
        frame = CubeFrame(folder: folder, number: number)
    }

    private func workingDuration(_ number: Int) -> Double {
        if C.workingBlinkFrames.contains(number) { return Double(C.blinkFrameMs) / 1000 }
        return Double(C.workingLongFramesMs[number] ?? C.workingFrameMs) / 1000
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Waits until `mood` changes, or until `timeout` seconds have passed (if given).
    private func waitForMoodChange(timeout: Double?) async {
        waitID += 1
        let id = waitID
        await withCheckedContinuation { continuation in
            pendingWait = continuation
            if let timeout {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    // Ignore if this wait already ended and another one started.
                    if self?.waitID == id { self?.resumeDirector() }
                }
            }
        }
    }

    private func resumeDirector() {
        pendingWait?.resume()
        pendingWait = nil
    }
}

/// One frame of the cube, by folder and number (01 = first file of the folder).
struct CubeFrame: Equatable {
    let folder: FrameLibrary.Folder
    let number: Int
}
