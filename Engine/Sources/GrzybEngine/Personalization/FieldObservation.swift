import Foundation

public enum ObservationKind: String, Codable, Sendable, CaseIterable {
    case found
    case empty
    case terrainFix = "terrain_fix"
    case rating
}

/// Facts about the cell and weather at observation time, used by calibration.
public struct ObservationContext: Codable, Equatable, Sendable {
    public var siteType: String?
    public var dominantSpecies: String?
    public var dayOfYear: Int
    public var daysSinceRainEvent: Int?

    public init(siteType: String?, dominantSpecies: String?, dayOfYear: Int, daysSinceRainEvent: Int?) {
        self.siteType = siteType
        self.dominantSpecies = dominantSpecies
        self.dayOfYear = dayOfYear
        self.daysSinceRainEvent = daysSinceRainEvent
    }
}

public struct FieldObservation: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var regionId: String?
    public var speciesId: String?
    public var kind: ObservationKind
    public var amount: Int
    public var lon: Double
    public var lat: Double
    public var cellIndex: Int?
    public var observedAt: Date
    public var photoPath: String?
    public var note: String?
    public var scoreAtTime: Double?
    public var factors: FactorSet?
    public var context: ObservationContext?
    public var terrainFix: TerrainOverride?

    public init(
        id: String = UUID().uuidString, regionId: String? = nil, speciesId: String?, kind: ObservationKind,
        amount: Int = 1, lon: Double, lat: Double, cellIndex: Int? = nil, observedAt: Date = Date(),
        photoPath: String? = nil, note: String? = nil, scoreAtTime: Double? = nil, factors: FactorSet? = nil,
        context: ObservationContext? = nil, terrainFix: TerrainOverride? = nil
    ) {
        self.id = id
        self.regionId = regionId
        self.speciesId = speciesId
        self.kind = kind
        self.amount = amount
        self.lon = lon
        self.lat = lat
        self.cellIndex = cellIndex
        self.observedAt = observedAt
        self.photoPath = photoPath
        self.note = note
        self.scoreAtTime = scoreAtTime
        self.factors = factors
        self.context = context
        self.terrainFix = terrainFix
    }

    public var coordinate: Coordinate { Coordinate(lon: lon, lat: lat) }
    public var day: DayStamp { DayStamp(date: observedAt) }

    public func applies(to speciesId: String) -> Bool {
        switch kind {
        case .found: self.speciesId == speciesId
        case .empty: self.speciesId == nil || self.speciesId == speciesId
        case .rating, .terrainFix: false
        }
    }
}
