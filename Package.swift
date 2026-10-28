// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CubeWidget",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CubeWidget", targets: ["CubeWidget"]),
        .executable(name: "cube-hook", targets: ["CubeHook"]),
    ],
    dependencies: [
        // A terminal view for macOS (used by the Claude Hub window).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", .upToNextMinor(from: "1.20.0")),
    ],
    targets: [
        // The app.
        .executableTarget(name: "CubeWidget",
                          dependencies: ["SessionFile", .product(name: "SwiftTerm", package: "SwiftTerm")],
                          path: "Sources/CubeWidget"),
        // The small program run by the Claude Code hooks: it writes one file per session.
        .executableTarget(name: "CubeHook", dependencies: ["SessionFile"], path: "Sources/CubeHook"),
        // The format of those files, shared by the hook and the app.
        .target(name: "SessionFile", path: "Sources/SessionFile"),
    ]
)
