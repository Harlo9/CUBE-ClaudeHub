import AppKit

/// Builds a colored version of a blue cube frame, in code (no extra image files).
///
/// Each pixel is turned to gray (its brightness), then that gray picks a color in a
/// dark → mid → light gradient. Transparency is kept as is.
enum CubeRecolor {
    struct Gradient {
        let dark: UInt32
        let mid: UInt32
        let light: UInt32

        static let orange = Gradient(dark: Constants.Cube.orangeGradientDark,
                                     mid: Constants.Cube.orangeGradientMid,
                                     light: Constants.Cube.orangeGradientLight)
        static let green = Gradient(dark: Constants.Cube.greenGradientDark,
                                    mid: Constants.Cube.greenGradientMid,
                                    light: Constants.Cube.greenGradientLight)
    }

    private struct RGB {
        var r, g, b: Double
    }

    /// 256 colors: entry `n` is the color that replaces gray level `n`.
    private static func table(for gradient: Gradient) -> [RGB] {
        func rgb(_ hex: UInt32) -> RGB {
            RGB(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
        }
        func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
            RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
        }
        let dark = rgb(gradient.dark), mid = rgb(gradient.mid), light = rgb(gradient.light)
        return (0..<256).map { level in
            let t = Double(level) / 255
            return t < 0.5 ? mix(dark, mid, t * 2) : mix(mid, light, (t - 0.5) * 2)
        }
    }

    static func recolor(_ image: NSImage, _ gradient: Gradient) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let width = source.width, height = source.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return image }

        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let colors = table(for: gradient)

        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let alpha = Double(pixels[i + 3]) / 255
            guard alpha > 0 else { continue }
            // Pixels are stored "premultiplied" (color × alpha): divide to get the real color.
            let r = Double(pixels[i]) / 255 / alpha
            let g = Double(pixels[i + 1]) / 255 / alpha
            let b = Double(pixels[i + 2]) / 255 / alpha
            let gray = min(1, max(0, 0.2126 * r + 0.7152 * g + 0.0722 * b))
            let color = colors[Int((gray * 255).rounded())]
            pixels[i] = UInt8((color.r * alpha * 255).rounded())
            pixels[i + 1] = UInt8((color.g * alpha * 255).rounded())
            pixels[i + 2] = UInt8((color.b * alpha * 255).rounded())
        }

        guard let result = context.makeImage() else { return image }
        return NSImage(cgImage: result, size: image.size)
    }
}
