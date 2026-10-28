import AppKit
import SwiftUI

// Debug helper: `CubeWidget --snapshot out.png [--waiting | --completed] [--eyes x,y]`
// renders the widget into a PNG and quits.
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    MainActor.assumeIsolated {
        let settings = WidgetSettings()
        let board = SessionBoard(demo: true)
        if arguments.contains("--waiting") { board.debugSetActiveStatus(.waiting) }
        if arguments.contains("--completed") { board.debugCompleteTask() }
        let cube = CubeAnimator(mood: board.cubeMood)
        if let eyesIndex = arguments.firstIndex(of: "--eyes"), eyesIndex + 1 < arguments.count {
            let xy = arguments[eyesIndex + 1].split(separator: ",").compactMap { Double($0) }
            if xy.count == 2 { cube.showEyesForSnapshot(CGPoint(x: xy[0], y: xy[1])) }
        }
        let content = CardStackView(board: board, cube: cube,
                                    isCollapsed: settings.isCollapsed, onToggleCollapsed: {})
            .padding(Constants.Window.haloMargin * settings.scale)
            .environment(\.widgetScale, settings.scale)
            .background(Color(hex: 0x1C1C1E))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        if let image = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: arguments[index + 1]))
        }
    }
    exit(0)
}

// Entry point. The app runs as an "accessory": no Dock icon, no app menu
// (LSUIElement in Info.plist does the same for the launch itself).
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
