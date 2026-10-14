import Foundation

public enum ForestLayer: String, Codable, Sendable {
    case stateForest = "lp"
    case otherForest = "pul"
}

/// Forest stand (wydzielenie) from BDL layers 66/67.
public struct StandRecord: Sendable {
    public var id: String
    public var layer: ForestLayer
    public var address: String?
    public var dominantSpecies: String?
    public var dominantShare: Double
    public var age: Int?
    public var structure: String?
    public var dataYear: Int?
    public var shape: Shape

    public init(
        id: String, layer: ForestLayer, address: String?, dominantSpecies: String?, dominantShare: Double,
        age: Int?, structure: String?, dataYear: Int?, shape: Shape
    ) {
        self.id = id
        self.layer = layer
        self.address = address
        self.dominantSpecies = dominantSpecies
        self.dominantShare = dominantShare
        self.age = age
        self.structure = structure
        self.dataYear = dataYear
        self.shape = shape
    }
}

/// Forest site (siedlisko) from BDL layer 20.
public struct SiteRecord: Sendable {
    public var id: String
    public var siteType: String?
    public var soilSubtype: String?
    public var moistureCode: String?
    public var geology: String?
    public var soilSpecies: String?
    public var arableFormerly: Bool
    public var degraded: Bool
    public var forestType: String?
    public var dataYear: Int?
    public var shape: Shape

    public init(
        id: String, siteType: String?, soilSubtype: String?, moistureCode: String?, geology: String?,
        soilSpecies: String?, arableFormerly: Bool, degraded: Bool, forestType: String?, dataYear: Int?, shape: Shape
    ) {
        self.id = id
        self.siteType = siteType
        self.soilSubtype = soilSubtype
        self.moistureCode = moistureCode
        self.geology = geology
        self.soilSpecies = soilSpecies
        self.arableFormerly = arableFormerly
        self.degraded = degraded
        self.forestType = forestType
        self.dataYear = dataYear
        self.shape = shape
    }
}

public enum TerrainOverride: String, Codable, Sendable, CaseIterable {
    case clearcut
    case wet
    case young
    case plowed
}

/// Static per-cell features computed once per region.
public struct CellFeatures: Codable, Equatable, Sendable {
    public var cellIndex: Int
    public var lon: Double
    public var lat: Double
    public var standId: String?
    public var dominantSpecies: String?
    public var dominantShare: Double
    public var admixture: [String]
    public var standAge: Int?
    public var standYear: Int?
    public var standStructure: String?
    public var siteId: String?
    public var siteType: String?
    public var geology: String?
    public var forestType: String?
    public var arableFormerly: Bool
    public var degraded: Bool
    public var siteYear: Int?
    public var distEdgeM: Double
    public var override: TerrainOverride?

    public init(
        cellIndex: Int, lon: Double, lat: Double, standId: String? = nil, dominantSpecies: String? = nil,
        dominantShare: Double = 0, admixture: [String] = [], standAge: Int? = nil, standYear: Int? = nil,
        standStructure: String? = nil, siteId: String? = nil, siteType: String? = nil, geology: String? = nil,
        forestType: String? = nil, arableFormerly: Bool = false, degraded: Bool = false, siteYear: Int? = nil,
        distEdgeM: Double = .infinity, override: TerrainOverride? = nil
    ) {
        self.cellIndex = cellIndex
        self.lon = lon
        self.lat = lat
        self.standId = standId
        self.dominantSpecies = dominantSpecies
        self.dominantShare = dominantShare
        self.admixture = admixture
        self.standAge = standAge
        self.standYear = standYear
        self.standStructure = standStructure
        self.siteId = siteId
        self.siteType = siteType
        self.geology = geology
        self.forestType = forestType
        self.arableFormerly = arableFormerly
        self.degraded = degraded
        self.siteYear = siteYear
        self.distEdgeM = distEdgeM
        self.override = override
    }

    public var coordinate: Coordinate { Coordinate(lon: lon, lat: lat) }

    /// Features after applying the user's terrain correction.
    public var effective: CellFeatures {
        var cell = self
        switch override {
        case .clearcut: cell.standAge = 0
        case .young: cell.standAge = 10
        case .wet: cell.siteType = wetVariant(of: siteType)
        case .plowed, .none: break
        }
        return cell
    }

    public var isExcluded: Bool { override == .plowed }

    private func wetVariant(of code: String?) -> String {
        guard let code else { return "Bw" }
        for suffix in ["św", "s"] where code.hasSuffix(suffix) {
            return String(code.dropLast(suffix.count)) + "w"
        }
        return code
    }
}
