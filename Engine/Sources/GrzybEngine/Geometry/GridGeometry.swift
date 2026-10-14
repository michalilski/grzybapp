import Foundation

/// Regular cell grid over a bounding box; row 0 is the northern edge.
public struct GridGeometry: Codable, Equatable, Sendable {
    public let bbox: BoundingBox
    public let cellSizeM: Double
    public let cols: Int
    public let rows: Int

    public init(bbox: BoundingBox, cellSizeM: Double) {
        self.bbox = bbox
        self.cellSizeM = cellSizeM
        cols = max(1, Int((bbox.widthMeters / cellSizeM).rounded()))
        rows = max(1, Int((bbox.heightMeters / cellSizeM).rounded()))
    }

    public var count: Int { cols * rows }
    public var dLon: Double { (bbox.maxLon - bbox.minLon) / Double(cols) }
    public var dLat: Double { (bbox.maxLat - bbox.minLat) / Double(rows) }

    public func index(col: Int, row: Int) -> Int {
        row * cols + col
    }

    public func position(of index: Int) -> (col: Int, row: Int) {
        (index % cols, index / cols)
    }

    public func center(of index: Int) -> Coordinate {
        let (col, row) = position(of: index)
        return Coordinate(
            lon: bbox.minLon + (Double(col) + 0.5) * dLon,
            lat: bbox.maxLat - (Double(row) + 0.5) * dLat
        )
    }

    public func cellBounds(of index: Int) -> BoundingBox {
        let (col, row) = position(of: index)
        let minLon = bbox.minLon + Double(col) * dLon
        let maxLat = bbox.maxLat - Double(row) * dLat
        return BoundingBox(minLon: minLon, minLat: maxLat - dLat, maxLon: minLon + dLon, maxLat: maxLat)
    }

    public func index(containing p: Coordinate) -> Int? {
        guard bbox.contains(p) else { return nil }
        let col = min(cols - 1, Int((p.lon - bbox.minLon) / dLon))
        let row = min(rows - 1, Int((bbox.maxLat - p.lat) / dLat))
        return index(col: col, row: row)
    }

    public func indices(within radiusM: Double, of p: Coordinate) -> [Int] {
        let reach = Int((radiusM / cellSizeM).rounded(.up))
        let col0 = Int(((p.lon - bbox.minLon) / dLon).rounded(.down))
        let row0 = Int(((bbox.maxLat - p.lat) / dLat).rounded(.down))
        let rowRange = max(0, row0 - reach)..<min(rows, row0 + reach + 1)
        let colRange = max(0, col0 - reach)..<min(cols, col0 + reach + 1)
        guard !rowRange.isEmpty, !colRange.isEmpty else { return [] }
        return rowRange.flatMap { row in
            colRange.map { index(col: $0, row: row) }
        }.filter { center(of: $0).distanceMeters(to: p) <= radiusM }
    }
}
