import Foundation
import GRDB
import GrzybEngine

public struct Region: Codable, Equatable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "regions"

    public var id: String
    public var name: String
    public var minLon: Double
    public var minLat: Double
    public var maxLon: Double
    public var maxLat: Double
    public var cellSizeM: Double
    public var createdAt: Date
    public var bdlFetchedAt: Date?
    public var bdlYearMin: Int?
    public var bdlYearMax: Int?
    public var weatherFetchedAt: Date?
    public var sizeBytes: Int
    public var tilesReady: Bool

    public init(id: String = UUID().uuidString, name: String, bbox: BoundingBox, cellSizeM: Double, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        minLon = bbox.minLon
        minLat = bbox.minLat
        maxLon = bbox.maxLon
        maxLat = bbox.maxLat
        self.cellSizeM = cellSizeM
        self.createdAt = createdAt
        sizeBytes = 0
        tilesReady = false
    }

    public var bbox: BoundingBox {
        BoundingBox(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
    }

    public var geometry: GridGeometry {
        GridGeometry(bbox: bbox, cellSizeM: cellSizeM)
    }

    public var isDownloaded: Bool { bdlFetchedAt != nil }
}

struct StandRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "stands"

    var id: String
    var regionId: String
    var layer: String
    var address: String?
    var dominantSpecies: String?
    var dominantShare: Double
    var age: Int?
    var structure: String?
    var dataYear: Int?

    init(_ stand: StandRecord, regionId: String) {
        id = stand.id
        self.regionId = regionId
        layer = stand.layer.rawValue
        address = stand.address
        dominantSpecies = stand.dominantSpecies
        dominantShare = stand.dominantShare
        age = stand.age
        structure = stand.structure
        dataYear = stand.dataYear
    }
}

/// Stand attributes shown in the cell details sheet.
public struct StandInfo: Codable, Equatable, Sendable, FetchableRecord {
    public var id: String
    public var address: String?
    public var dataYear: Int?
}

struct SiteRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sites"

    var id: String
    var regionId: String
    var siteType: String?
    var soilSubtype: String?
    var moistureCode: String?
    var geology: String?
    var soilSpecies: String?
    var arableFormerly: Bool
    var degraded: Bool
    var forestType: String?
    var dataYear: Int?

    init(_ site: SiteRecord, regionId: String) {
        id = site.id
        self.regionId = regionId
        siteType = site.siteType
        soilSubtype = site.soilSubtype
        moistureCode = site.moistureCode
        geology = site.geology
        soilSpecies = site.soilSpecies
        arableFormerly = site.arableFormerly
        degraded = site.degraded
        forestType = site.forestType
        dataYear = site.dataYear
    }
}

struct GridCellRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "grid_cells"

    var regionId: String
    var cellIndex: Int
    var lon: Double
    var lat: Double
    var standId: String?
    var dominantSpecies: String?
    var dominantShare: Double
    var admixture: String
    var standAge: Int?
    var standYear: Int?
    var standStructure: String?
    var siteId: String?
    var siteType: String?
    var geology: String?
    var forestType: String?
    var arableFormerly: Bool
    var degraded: Bool
    var siteYear: Int?
    var distEdgeM: Double
    var override: String?

    init(_ c: CellFeatures, regionId: String) {
        self.regionId = regionId
        cellIndex = c.cellIndex
        lon = c.lon
        lat = c.lat
        standId = c.standId
        dominantSpecies = c.dominantSpecies
        dominantShare = c.dominantShare
        admixture = c.admixture.joined(separator: ",")
        standAge = c.standAge
        standYear = c.standYear
        standStructure = c.standStructure
        siteId = c.siteId
        siteType = c.siteType
        geology = c.geology
        forestType = c.forestType
        arableFormerly = c.arableFormerly
        degraded = c.degraded
        siteYear = c.siteYear
        distEdgeM = c.distEdgeM.isFinite ? c.distEdgeM : 1e9
        override = c.override?.rawValue
    }

    var features: CellFeatures {
        CellFeatures(
            cellIndex: cellIndex, lon: lon, lat: lat, standId: standId, dominantSpecies: dominantSpecies,
            dominantShare: dominantShare, admixture: admixture.split(separator: ",").map(String.init),
            standAge: standAge, standYear: standYear, standStructure: standStructure, siteId: siteId,
            siteType: siteType, geology: geology, forestType: forestType, arableFormerly: arableFormerly,
            degraded: degraded, siteYear: siteYear, distEdgeM: distEdgeM, override: override.flatMap(TerrainOverride.init)
        )
    }
}

struct WeatherRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "weather_days"

    var regionId: String
    var day: String
    var precipMm: Double
    var tminC: Double?
    var tmaxC: Double?
    var soilTempC: Double?
    var soilMoisture: Double?
    var humidity: Double?
    var isForecast: Bool

    init(_ w: WeatherDay, regionId: String) {
        self.regionId = regionId
        day = w.day.iso
        precipMm = w.precipMm
        tminC = w.tminC
        tmaxC = w.tmaxC
        soilTempC = w.soilTempC
        soilMoisture = w.soilMoisture
        humidity = w.humidity
        isForecast = w.isForecast
    }

    var weatherDay: WeatherDay? {
        DayStamp(iso: day).map {
            WeatherDay(
                day: $0, precipMm: precipMm, tminC: tminC, tmaxC: tmaxC, soilTempC: soilTempC,
                soilMoisture: soilMoisture, humidity: humidity, isForecast: isForecast
            )
        }
    }
}

extension FieldObservation: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "observations"
}

struct OverrideRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "species_overrides"

    var speciesId: String
    var path: String
    var value: [Double]
    var source: String
    var changedAt: Date

    init(_ o: ParameterOverride) {
        speciesId = o.speciesId
        path = o.path
        value = o.value
        source = o.source.rawValue
        changedAt = o.changedAt
    }

    var override: ParameterOverride {
        ParameterOverride(
            speciesId: speciesId, path: path, value: value,
            source: OverrideSource(rawValue: source) ?? .user, changedAt: changedAt
        )
    }
}

public struct CalibrationEntry: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "calibration_log"

    public var id: Int64?
    public var speciesId: String
    public var parameter: String
    public var oldValue: [Double]
    public var newValue: [Double]
    public var reasonText: String
    public var observationIds: [String]
    public var createdAt: Date
    public var reverted: Bool

    public init(change: CalibrationChange, createdAt: Date = Date()) {
        speciesId = change.speciesId
        parameter = change.parameter
        oldValue = change.oldValue
        newValue = change.newValue
        reasonText = change.reason
        observationIds = change.observationIds
        self.createdAt = createdAt
        reverted = false
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct SettingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "settings"

    var key: String
    var value: String
}
