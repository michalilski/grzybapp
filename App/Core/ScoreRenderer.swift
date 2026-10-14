import CoreGraphics
import GrzybEngine
import UIKit

/// Map overlay: one pixel per grid cell, colored by potential band.
struct ScoreOverlay: Equatable {
    let id: UUID
    let image: UIImage
    let bbox: BoundingBox

    static func == (lhs: ScoreOverlay, rhs: ScoreOverlay) -> Bool {
        lhs.id == rhs.id
    }
}

enum ScoreRenderer {
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
        return ScoreOverlay(id: UUID(), image: image, bbox: geometry.bbox)
    }

    private static func makeImage(pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let cg = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cg)
    }
}
