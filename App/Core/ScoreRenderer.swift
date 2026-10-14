import CoreGraphics
import CoreImage
import GrzybEngine
import UIKit

/// Map overlay: one pixel per grid cell, colored by potential band.
struct ScoreOverlay: Equatable {
    let id: UUID
    let image: UIImage
    let bbox: BoundingBox
    let smooth: Bool

    static func == (lhs: ScoreOverlay, rhs: ScoreOverlay) -> Bool {
        lhs.id == rhs.id
    }
}

enum ScoreRenderer {
    private static let blurContext = CIContext(options: [.useSoftwareRenderer: false])

    static func render(_ layer: ScoreLayer, bands: EngineParameters.Bands, fieldMode: Bool) -> ScoreOverlay? {
        let geometry = layer.geometry
        var pixels = [UInt8](repeating: 0, count: geometry.count * 4)
        for i in 0..<geometry.count {
            let value = Double(layer.values[i])
            guard value >= 0, let rgba = BandStyle.rgba(PotentialBand(score: value, bands: bands), fieldMode: fieldMode) else { continue }
            pixels[i * 4] = rgba.0
            pixels[i * 4 + 1] = rgba.1
            pixels[i * 4 + 2] = rgba.2
            pixels[i * 4 + 3] = rgba.3
        }
        guard let image = makeImage(pixels: pixels, width: geometry.cols, height: geometry.rows) else { return nil }
        return ScoreOverlay(id: UUID(), image: image, bbox: geometry.bbox, smooth: false)
    }

    /// Continuous heatmap: transparent at low values, yellow → orange → deep red as potential grows.
    static func renderHeatmap(_ layer: ScoreLayer, fieldMode: Bool) -> ScoreOverlay? {
        let geometry = layer.geometry
        var pixels = [UInt8](repeating: 0, count: geometry.count * 4)
        let alphaBoost = fieldMode ? 1.15 : 1.0
        for i in 0..<geometry.count where layer.values[i] >= 0 {
            let c = HeatRamp.color(at: Double(layer.values[i]))
            let alpha = min(255, c.a * alphaBoost)
            pixels[i * 4] = UInt8(c.r * alpha / 255)
            pixels[i * 4 + 1] = UInt8(c.g * alpha / 255)
            pixels[i * 4 + 2] = UInt8(c.b * alpha / 255)
            pixels[i * 4 + 3] = UInt8(alpha)
        }
        guard let image = makeImage(pixels: pixels, width: geometry.cols, height: geometry.rows, premultiplied: true),
              let smooth = upsample(image, factor: 4) else { return nil }
        return ScoreOverlay(id: UUID(), image: smooth, bbox: geometry.bbox, smooth: true)
    }

    /// Smooth upscaling so 100 m cells blend into a continuous heatmap.
    private static func upsample(_ image: UIImage, factor: Int) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width * factor, height = cg.height * factor
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let input = CIImage(cgImage: scaled)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: Double(factor) * 0.4).cropped(to: input.extent)
        return blurContext.createCGImage(blurred, from: input.extent).map { UIImage(cgImage: $0) }
    }

    private static func makeImage(pixels: [UInt8], width: Int, height: Int, premultiplied: Bool = false) -> UIImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        let info = CGBitmapInfo(rawValue: (premultiplied ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.last).rawValue)
        guard let cg = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Color stops of the general heatmap, value 0–100 → RGBA.
enum HeatRamp {
    static let stops: [(value: Double, r: Double, g: Double, b: Double, a: Double)] = [
        (4, 255, 214, 0, 0),
        (15, 255, 214, 0, 120),
        (35, 255, 140, 0, 175),
        (60, 230, 40, 0, 205),
        (85, 160, 0, 30, 225),
        (100, 110, 0, 40, 235),
    ]

    static func color(at value: Double) -> (r: Double, g: Double, b: Double, a: Double) {
        guard let first = stops.first, let last = stops.last else { return (0, 0, 0, 0) }
        if value <= first.value { return (first.r, first.g, first.b, 0) }
        if value >= last.value { return (last.r, last.g, last.b, last.a) }
        for (lo, hi) in zip(stops, stops.dropFirst()) where value <= hi.value {
            let t = (value - lo.value) / (hi.value - lo.value)
            return (lo.r + (hi.r - lo.r) * t, lo.g + (hi.g - lo.g) * t, lo.b + (hi.b - lo.b) * t, lo.a + (hi.a - lo.a) * t)
        }
        return (last.r, last.g, last.b, last.a)
    }
}
