import Foundation

public struct Coordinate: Codable, Equatable, Hashable, Sendable {
    public var lon: Double
    public var lat: Double

    public init(lon: Double, lat: Double) {
        self.lon = lon
        self.lat = lat
    }

    public func distanceMeters(to other: Coordinate) -> Double {
        let metersPerDegree = 111_320.0
        let dx = (other.lon - lon) * metersPerDegree * cos((lat + other.lat) / 2 * .pi / 180)
        let dy = (other.lat - lat) * metersPerDegree
        return (dx * dx + dy * dy).squareRoot()
    }

    public func bearingDegrees(to other: Coordinate) -> Double {
        let phi1 = lat * .pi / 180
        let phi2 = other.lat * .pi / 180
        let dLambda = (other.lon - lon) * .pi / 180
        let y = sin(dLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

public struct BoundingBox: Codable, Equatable, Hashable, Sendable {
    public var minLon: Double
    public var minLat: Double
    public var maxLon: Double
    public var maxLat: Double

    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }

    public init?(points: [Coordinate]) {
        guard let first = points.first else { return nil }
        var box = BoundingBox(minLon: first.lon, minLat: first.lat, maxLon: first.lon, maxLat: first.lat)
        for p in points.dropFirst() {
            box.minLon = min(box.minLon, p.lon)
            box.maxLon = max(box.maxLon, p.lon)
            box.minLat = min(box.minLat, p.lat)
            box.maxLat = max(box.maxLat, p.lat)
        }
        self = box
    }

    public var center: Coordinate {
        Coordinate(lon: (minLon + maxLon) / 2, lat: (minLat + maxLat) / 2)
    }

    public var widthMeters: Double {
        Coordinate(lon: minLon, lat: center.lat).distanceMeters(to: Coordinate(lon: maxLon, lat: center.lat))
    }

    public var heightMeters: Double {
        Coordinate(lon: center.lon, lat: minLat).distanceMeters(to: Coordinate(lon: center.lon, lat: maxLat))
    }

    public func contains(_ p: Coordinate) -> Bool {
        p.lon >= minLon && p.lon <= maxLon && p.lat >= minLat && p.lat <= maxLat
    }

    public func intersects(_ other: BoundingBox) -> Bool {
        minLon <= other.maxLon && maxLon >= other.minLon && minLat <= other.maxLat && maxLat >= other.minLat
    }

    public func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(
            minLon: min(minLon, other.minLon), minLat: min(minLat, other.minLat),
            maxLon: max(maxLon, other.maxLon), maxLat: max(maxLat, other.maxLat)
        )
    }

    /// Splits the box into tiles of roughly `sizeMeters` per side.
    public func tiles(sizeMeters: Double) -> [BoundingBox] {
        let cols = max(1, Int((widthMeters / sizeMeters).rounded(.up)))
        let rows = max(1, Int((heightMeters / sizeMeters).rounded(.up)))
        let dLon = (maxLon - minLon) / Double(cols)
        let dLat = (maxLat - minLat) / Double(rows)
        var result: [BoundingBox] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let lon0 = minLon + Double(c) * dLon
                let lat0 = minLat + Double(r) * dLat
                result.append(BoundingBox(minLon: lon0, minLat: lat0, maxLon: lon0 + dLon, maxLat: lat0 + dLat))
            }
        }
        return result
    }
}

/// Polygon with outer ring first and optional holes; containment uses the even-odd rule.
public struct Polygon: Sendable {
    public let rings: [[Coordinate]]
    public let bbox: BoundingBox

    public init?(rings: [[Coordinate]]) {
        guard let outer = rings.first, outer.count >= 3, let box = BoundingBox(points: outer) else { return nil }
        self.rings = rings
        bbox = box
    }

    public func contains(_ p: Coordinate) -> Bool {
        guard bbox.contains(p) else { return false }
        var inside = false
        for ring in rings {
            var j = ring.count - 1
            for i in 0..<ring.count {
                let a = ring[i]
                let b = ring[j]
                if (a.lat > p.lat) != (b.lat > p.lat),
                   p.lon < (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon {
                    inside.toggle()
                }
                j = i
            }
        }
        return inside
    }
}

/// Area made of one or more polygons, as in GeoJSON MultiPolygon.
public struct Shape: Sendable {
    public let polygons: [Polygon]
    public let bbox: BoundingBox

    public init?(polygons: [Polygon]) {
        guard let first = polygons.first else { return nil }
        self.polygons = polygons
        bbox = polygons.dropFirst().reduce(first.bbox) { $0.union($1.bbox) }
    }

    public func contains(_ p: Coordinate) -> Bool {
        bbox.contains(p) && polygons.contains { $0.contains(p) }
    }
}
