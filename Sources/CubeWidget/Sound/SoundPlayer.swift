import AVFoundation

/// Plays the short sounds of the Sons/ folder (copied into the app by build.sh).
///
/// Everything audio happens on a background queue: starting a sound can take tens of
/// milliseconds, which would freeze the cube animation if done on the main thread.
/// A missing or unreadable file is not an error: that event simply plays nothing.
enum SoundPlayer {
    enum Sound: String, CaseIterable {
        /// The active project starts working (you answered, or a session opened).
        case working = "bosse"
        /// A task was just completed.
        case taskCompleted = "fini"
        /// A session starts waiting for your answer.
        case waiting = "attente"
        /// The cube starts falling asleep.
        case fallAsleep = "dodo"

        /// The starting volume (Réglages → Sons can change it).
        var defaultVolume: Float {
            switch self {
            case .working: Constants.Sound.workingVolume
            case .taskCompleted: Constants.Sound.taskCompletedVolume
            case .waiting: Constants.Sound.waitingVolume
            case .fallAsleep: Constants.Sound.fallAsleepVolume
            }
        }

        /// Its name and when it plays, as shown in Réglages → Sons.
        var title: String {
            switch self {
            case .working: "Bosse"
            case .taskCompleted: "Fini"
            case .waiting: "Attente"
            case .fallAsleep: "Dodo"
            }
        }

        var detail: String {
            switch self {
            case .working: "Le projet actif commence à bosser."
            case .taskCompleted: "Une tâche est terminée, ou Claude a fini sa réponse."
            case .waiting: "Une session attend ta réponse."
            case .fallAsleep: "Le cube s'endort : plus aucune session."
            }
        }
    }

    private static let extensions = ["aiff", "wav", "mp3", "m4a"]
    private static let queue = DispatchQueue(label: "CubeWidget.sounds", qos: .userInitiated)
    /// Loaded players (only touched on `queue`); `.some(nil)` remembers that a file is missing.
    nonisolated(unsafe) private static var players: [Sound: AVAudioPlayer?] = [:]

    /// Loads every sound and gets the audio output ready, so the first sound starts right away.
    static func preload() {
        queue.async { Sound.allCases.forEach { _ = player(for: $0) } }
    }

    /// Plays a sound once, at its volume from Réglages → Sons (nothing if the sounds are
    /// off). If it is already playing, it starts again from the beginning.
    static func play(_ sound: Sound) {
        guard SoundSettings.isOn else { return }
        preview(sound, volume: SoundSettings.volume(of: sound))
    }

    /// Plays a sound at a given volume, even if the sounds are off (the ▶ buttons).
    static func preview(_ sound: Sound, volume: Float) {
        queue.async {
            guard let player = player(for: sound) else { return }
            player.volume = volume
            player.currentTime = 0
            player.play()
        }
    }

    /// Call on `queue` only.
    private static func player(for sound: Sound) -> AVAudioPlayer? {
        if let cached = players[sound] { return cached }
        let folder = Bundle.main.resourceURL?.appendingPathComponent("Sons")
        let player = extensions.lazy
            .compactMap { folder?.appendingPathComponent("\(sound.rawValue).\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
            .flatMap { try? AVAudioPlayer(contentsOf: $0) }
        player?.prepareToPlay()
        players[sound] = .some(player)
        return player
    }
}
