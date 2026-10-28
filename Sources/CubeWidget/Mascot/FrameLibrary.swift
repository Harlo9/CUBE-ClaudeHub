import AppKit

/// Loads the reduced cube frames bundled in the app (Contents/Resources/Frames),
/// and computes their orange and green versions on first use.
@MainActor
enum FrameLibrary {
    enum Folder: String {
        case working = "Travail"
        case sleep = "Sommeil"
    }

    enum Size: String {
        case card
        case menubar
    }

    enum Tint: String {
        case blue
        /// Waiting for your answer.
        case orange
        /// Task completed.
        case green
    }

    private static var cache: [String: [NSImage]] = [:]

    /// All frames of a folder, sorted by file name.
    /// Returns an empty array (never crashes) if the folder is missing.
    static func frames(_ folder: Folder, size: Size = .card, tint: Tint = .blue) -> [NSImage] {
        let key = "\(size.rawValue)/\(folder.rawValue)/\(tint.rawValue)"
        if let cached = cache[key] { return cached }

        let images: [NSImage]
        switch tint {
        case .blue:
            guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Frames/\(size.rawValue)/\(folder.rawValue)"),
                  let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
                return []
            }
            images = files.sorted()
                .filter { $0.hasSuffix(".png") }
                .compactMap { NSImage(contentsOf: dir.appendingPathComponent($0)) }
        case .orange:
            images = frames(folder, size: size, tint: .blue).map { CubeRecolor.recolor($0, .orange) }
        case .green:
            images = frames(folder, size: size, tint: .blue).map { CubeRecolor.recolor($0, .green) }
        }
        cache[key] = images
        return images
    }

    /// Frame number `number` (1-based, as in the file names), or nil if it does not exist.
    static func frame(_ folder: Folder, _ number: Int, size: Size = .card, tint: Tint = .blue) -> NSImage? {
        let all = frames(folder, size: size, tint: tint)
        return all.indices.contains(number - 1) ? all[number - 1] : nil
    }

    private static var singles: [String: NSImage] = [:]

    /// The cube without eyes (Assets/Regard), in the given color.
    static func eyelessCube(size: Size = .card, tint: Tint = .blue) -> NSImage? {
        let key = "\(size.rawValue)/eyeless/\(tint.rawValue)"
        if let cached = singles[key] { return cached }
        let image: NSImage?
        switch tint {
        case .blue: image = load("Regard/cube_sans_yeux.png", size: size)
        case .orange: image = eyelessCube(size: size).map { CubeRecolor.recolor($0, .orange) }
        case .green: image = eyelessCube(size: size).map { CubeRecolor.recolor($0, .green) }
        }
        singles[key] = image
        return image
    }

    /// One eye (Assets/Regard). It is never recolored.
    static func eye(size: Size = .card) -> NSImage? {
        let key = "\(size.rawValue)/eye"
        if let cached = singles[key] { return cached }
        let image = load("Regard/oeil.png", size: size)
        singles[key] = image
        return image
    }

    private static func load(_ path: String, size: Size) -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Frames/\(size.rawValue)/\(path)") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Computes the orange and green versions of the widget frames in advance (recoloring
    /// takes a little time, which would make the cube stutter the first time a color shows).
    static func preload() {
        for tint in [Tint.orange, .green] {
            _ = frames(.working, tint: tint)
            _ = eyelessCube(tint: tint)
        }
        _ = eye()
    }

    /// Width / height of the frames, used to lay out the cube before an image is shown.
    static var aspectRatio: CGFloat {
        guard let size = frames(.working).first?.size, size.height > 0 else { return 1 }
        return size.width / size.height
    }
}
