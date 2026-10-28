import Foundation

/// Timing of the `Travail` loop (the cube looks left, blinks, looks right, blinks), for the
/// small cubes that compute their image from the clock (Hub, menu bar), with the same
/// durations as the widget's cube.
enum WorkingLoop {
    static let frameCount = 21

    /// Duration of each image, in seconds.
    static let durations: [Double] = (1...frameCount).map { number in
        let ms = Constants.Cube.workingLongFramesMs[number]
            ?? (Constants.Cube.workingBlinkFrames.contains(number) ? Constants.Cube.blinkFrameMs
                                                                   : Constants.Cube.workingFrameMs)
        return Double(ms) / 1000
    }

    private static let total = durations.reduce(0, +)

    /// Image number (1-based) shown at this time.
    static func frame(at time: Double) -> Int {
        var t = time.truncatingRemainder(dividingBy: total)
        for (index, duration) in durations.enumerated() {
            if t < duration { return index + 1 }
            t -= duration
        }
        return 1
    }

    /// Time left before the image changes (at least 1 ms, so a schedule always moves on).
    static func timeToNextFrame(at time: Double) -> Double {
        var t = time.truncatingRemainder(dividingBy: total)
        for duration in durations {
            if t < duration { return max(duration - t, 0.001) }
            t -= duration
        }
        return durations[0]
    }
}
