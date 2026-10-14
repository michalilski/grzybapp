import Foundation

/// Bucket grid over item bounding boxes for fast point lookups.
struct SpatialIndex<Item> {
    private let items: [Item]
    private let shapes: [Shape]
    private let bounds: BoundingBox
    private let bucketsPerSide: Int
    private var buckets: [[Int]]

    init(items: [Item], shape: (Item) -> Shape, bounds: BoundingBox, bucketsPerSide: Int = 64) {
        self.items = items
        self.shapes = items.map(shape)
        self.bounds = bounds
        self.bucketsPerSide = bucketsPerSide
        buckets = Array(repeating: [], count: bucketsPerSide * bucketsPerSide)
        for (i, s) in shapes.enumerated() where s.bbox.intersects(bounds) {
            for b in bucketRange(for: s.bbox) { buckets[b].append(i) }
        }
    }

    func first(containing p: Coordinate) -> Item? {
        guard let b = bucket(for: p) else { return nil }
        return buckets[b].first { shapes[$0].contains(p) }.map { items[$0] }
    }

    private func bucket(for p: Coordinate) -> Int? {
        guard bounds.contains(p) else { return nil }
        return bucketIndex(col: column(p.lon), row: row(p.lat))
    }

    private func bucketRange(for box: BoundingBox) -> [Int] {
        let c0 = column(box.minLon), c1 = column(box.maxLon)
        let r0 = row(box.minLat), r1 = row(box.maxLat)
        return (r0...r1).flatMap { r in (c0...c1).map { bucketIndex(col: $0, row: r) } }
    }

    private func column(_ lon: Double) -> Int {
        let t = (lon - bounds.minLon) / (bounds.maxLon - bounds.minLon)
        return Int(t * Double(bucketsPerSide)).clampedIndex(bucketsPerSide)
    }

    private func row(_ lat: Double) -> Int {
        let t = (lat - bounds.minLat) / (bounds.maxLat - bounds.minLat)
        return Int(t * Double(bucketsPerSide)).clampedIndex(bucketsPerSide)
    }

    private func bucketIndex(col: Int, row: Int) -> Int {
        row * bucketsPerSide + col
    }
}
