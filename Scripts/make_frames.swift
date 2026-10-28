// Generates the reduced cube frames used by the app from the originals in Assets/.
//
// Every original is 1371 x 1147 px with the cube at the same spot, so the same crop
// box is applied to all of them (measured: the cube and its glow fit in
// x 247...1123, y 176...1015, from the top-left corner). Smaller images (the eye of
// Assets/Regard) are not cropped, only downscaled by the same factor.
// Each frame is then downscaled into two sets:
//   Resources/Frames/card/<Folder>/<name>.png      for the widget card
//   Resources/Frames/menubar/<Folder>/<name>.png   for the menu bar icon
//
// Usage (from the project root): swift Scripts/make_frames.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Crop box in original pixels, origin at the top-left corner.
/// Must match `Constants.Cube.sourceCrop` in the app.
let cropBox = CGRect(x: 236, y: 160, width: 900, height: 870)
/// Size of the full frames; only images of this size are cropped.
let fullFrameSize = CGSize(width: 1371, height: 1147)

/// Output heights in pixels (2x the largest on-screen size, for Retina screens).
let outputHeights: [(set: String, height: Int)] = [("card", 180), ("menubar", 44)]

let folders = ["Travail", "Sommeil", "Regard"]
let fileManager = FileManager.default

func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func resize(_ image: CGImage, scale: Double) -> CGImage? {
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

var count = 0
for folder in folders {
    let sourceDir = URL(fileURLWithPath: "Assets/\(folder)")
    let files = (try? fileManager.contentsOfDirectory(atPath: sourceDir.path)) ?? []
    for file in files.sorted() where file.lowercased().hasSuffix(".png") {
        guard let original = loadImage(sourceDir.appendingPathComponent(file)) else {
            print("⚠️  Could not read \(folder)/\(file)")
            continue
        }
        let isFullFrame = original.width == Int(fullFrameSize.width) && original.height == Int(fullFrameSize.height)
        guard let source = isFullFrame ? original.cropping(to: cropBox) : original else {
            print("⚠️  Could not crop \(folder)/\(file)")
            continue
        }
        for output in outputHeights {
            let outDir = URL(fileURLWithPath: "Resources/Frames/\(output.set)/\(folder)")
            try? fileManager.createDirectory(at: outDir, withIntermediateDirectories: true)
            // Same factor for every image, so the eye keeps its size relative to the cube.
            let scale = Double(output.height) / cropBox.height
            guard let small = resize(source, scale: scale),
                  writePNG(small, to: outDir.appendingPathComponent(file)) else {
                print("⚠️  Could not write \(output.set)/\(folder)/\(file)")
                continue
            }
        }
        count += 1
    }
}
print("✓ \(count) frames generated in Resources/Frames/")
