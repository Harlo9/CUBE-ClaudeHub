import SwiftUI

/// The ice cube of a session in the Cube Hub. Simpler than the widget's (there can be
/// many of them): each pose is computed from the clock, with the same images and colors.
/// - bosse: blue, looks left and right and blinks (the `Travail` loop)
/// - attend: orange, a small jump every few seconds
/// - terminé: green, still
/// - no session: asleep, breathing slowly
struct HubCube: View {
    enum Mood: Equatable {
        case working, waiting, done, asleep

        init(_ status: SessionStatus?) {
            switch status {
            case .working: self = .working
            case .waiting: self = .waiting
            case .done: self = .done
            case nil: self = .asleep
            }
        }

        var color: Color? {
            switch self {
            case .working: Constants.Colors.working
            case .waiting: Constants.Colors.waiting
            case .done: Constants.Colors.completed
            case .asleep: nil
            }
        }
    }

    let mood: Mood
    /// Height of the cube, in points.
    let size: CGFloat
    /// Time shift, so that several cubes do not move all together.
    var phase: Double = 0

    @Environment(\.hubCubesMove) private var moves

    var body: some View {
        ZStack {
            // The glow does not move: outside the timeline, so it is not redrawn with the image.
            if let color = mood.color {
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(Constants.Hub.cubeGlowOpacity), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.62))
                    .frame(width: size * 1.3, height: size * 1.3)
            }
            TimelineView(HubCubeSchedule(mood: mood, phase: phase, isPaused: !moves)) { context in
                let time = context.date.timeIntervalSinceReferenceDate + phase
                Group {
                    if mood == .asleep {
                        // Breathing played by Core Animation: nothing redrawn by the app.
                        BreathingImage(image: image(at: time), since: Date(timeIntervalSinceReferenceDate: -phase),
                                       anchor: .bottom)
                            .aspectRatio(FrameLibrary.aspectRatio, contentMode: .fit)
                            .allowsHitTesting(false)
                    } else {
                        Image(nsImage: image(at: time) ?? NSImage())
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    }
                }
                .frame(height: size)
                .offset(y: -lift(at: time))
                .opacity(mood == .asleep ? Constants.Hub.asleepOpacity : 1)
            }
        }
        .frame(width: size * 1.15, height: size)
    }

    private func image(at time: Double) -> NSImage? {
        switch mood {
        case .working: FrameLibrary.frame(.working, WorkingLoop.frame(at: time))
        case .waiting: FrameLibrary.frame(.working, 1, tint: .orange)
        case .done: FrameLibrary.frame(.working, 1, tint: .green)
        case .asleep: FrameLibrary.frame(.sleep, 10)
        }
    }

    /// Height of the "waiting" jump: one jump every `reminderJumpInterval` seconds.
    private func lift(at time: Double) -> CGFloat {
        guard mood == .waiting else { return 0 }
        let duration = Constants.Cube.jumpDuration
        let t = time.truncatingRemainder(dividingBy: Constants.Cube.reminderJumpInterval)
        guard t < duration else { return 0 }
        return size * Constants.Hub.cubeJumpFraction * sin(.pi * t / duration)
    }

}

/// The moments when a Hub cube's picture changes, so the app redraws it only then (and
/// is not woken up at every screen refresh): each new image of the `Travail` loop, the
/// steps of the "waiting" jump, nothing for a still or breathing cube.
private struct HubCubeSchedule: TimelineSchedule {
    let mood: HubCube.Mood
    let phase: Double
    let isPaused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        if isPaused { return AnySequence([startDate]) }
        switch mood {
        case .done, .asleep:
            return AnySequence([startDate])
        case .working:
            return AnySequence(sequence(first: startDate) { date in
                date.addingTimeInterval(WorkingLoop.timeToNextFrame(at: date.timeIntervalSinceReferenceDate + phase))
            })
        case .waiting:
            let step = 1 / Constants.Hub.cubeFramesPerSecond
            let interval = Constants.Cube.reminderJumpInterval
            let jump = Constants.Cube.jumpDuration
            return AnySequence(sequence(first: startDate) { date in
                let t = (date.timeIntervalSinceReferenceDate + phase).truncatingRemainder(dividingBy: interval)
                // During a jump: its next step (the last one lands it); otherwise the next jump.
                let wait = t < jump ? min(step, jump - t + 0.001) : interval - t
                return date.addingTimeInterval(max(wait, 0.001))
            })
        }
    }
}

extension EnvironmentValues {
    /// The Hub's cubes move (false while the Hub window cannot be seen).
    @Entry var hubCubesMove = true
}
