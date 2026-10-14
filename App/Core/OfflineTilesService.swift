import Foundation
import MapLibre
import GrzybEngine

/// Downloads OpenFreeMap vector tiles for a region (zoom 10–16) so the map works without network.
@MainActor
final class OfflineTilesService: NSObject {
    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
    static let minZoom = 10.0
    static let maxZoom = 16.0
    private var observers: [String: (Double) -> Void] = [:]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(progressChanged(_:)), name: NSNotification.Name.MLNOfflinePackProgressChanged, object: nil
        )
    }

    func download(regionId: String, bbox: BoundingBox, progress: @escaping (Double) -> Void) {
        observers[regionId] = progress
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: bbox.minLat, longitude: bbox.minLon),
            ne: CLLocationCoordinate2D(latitude: bbox.maxLat, longitude: bbox.maxLon)
        )
        let region = MLNTilePyramidOfflineRegion(styleURL: Self.styleURL, bounds: bounds, fromZoomLevel: Self.minZoom, toZoomLevel: Self.maxZoom)
        remove(regionId: regionId)
        MLNOfflineStorage.shared.addPack(for: region, withContext: Data(regionId.utf8)) { pack, error in
            guard let pack, error == nil else {
                progress(1)
                return
            }
            pack.resume()
        }
    }

    func remove(regionId: String) {
        for pack in MLNOfflineStorage.shared.packs ?? [] where String(data: pack.context, encoding: .utf8) == regionId {
            MLNOfflineStorage.shared.removePack(pack, withCompletionHandler: nil)
        }
    }

    func isComplete(regionId: String) -> Bool {
        MLNOfflineStorage.shared.packs?.contains {
            String(data: $0.context, encoding: .utf8) == regionId && $0.state == .complete
        } ?? false
    }

    static func estimatedTileCount(_ bbox: BoundingBox) -> Double {
        stride(from: minZoom, through: maxZoom, by: 1).reduce(0) { total, zoom in
            let tileMeters = 40_075_016 * cos(bbox.center.lat * .pi / 180) / pow(2, zoom)
            let cols = (bbox.widthMeters / tileMeters).rounded(.up) + 1
            let rows = (bbox.heightMeters / tileMeters).rounded(.up) + 1
            return total + cols * rows
        }
    }

    @objc private func progressChanged(_ notification: Notification) {
        guard let pack = notification.object as? MLNOfflinePack,
              let regionId = String(data: pack.context, encoding: .utf8),
              let observer = observers[regionId] else { return }
        let p = pack.progress
        let expected = max(1, p.countOfResourcesExpected)
        let fraction = pack.state == .complete ? 1 : Double(p.countOfResourcesCompleted) / Double(expected)
        observer(min(1, fraction))
        if pack.state == .complete { observers[regionId] = nil }
    }
}
