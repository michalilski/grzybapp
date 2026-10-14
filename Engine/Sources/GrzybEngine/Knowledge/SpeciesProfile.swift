import Foundation

public enum Ecology: String, Codable, Sendable {
    case mycorrhizal
    case saprotroph
}

public enum MoistureClass: String, Codable, Sendable, CaseIterable {
    case dry, fresh, moist, wet, riparian
}

public struct SeasonWindow: Codable, Equatable, Sendable {
    public var startDoy: Int
    public var peakLoDoy: Int
    public var peakHiDoy: Int
    public var endDoy: Int

    enum CodingKeys: String, CodingKey {
        case startDoy = "start_doy"
        case peakLoDoy = "peak_lo_doy"
        case peakHiDoy = "peak_hi_doy"
        case endDoy = "end_doy"
    }

    public var trapezoid: Trapezoid {
        Trapezoid(min: Double(startDoy), optLo: Double(peakLoDoy), optHi: Double(peakHiDoy), max: Double(endDoy))
    }

    public func contains(_ doy: Int) -> Bool {
        doy >= startDoy && doy <= endDoy
    }

    public func isPeak(_ doy: Int) -> Bool {
        doy >= peakLoDoy && doy <= peakHiDoy
    }
}

public struct ColdNightsRule: Codable, Equatable, Sendable {
    public var maxTminC: Double
    public var minCount: Int
    public var windowDays: Int
    public var elseFactor: Double

    enum CodingKeys: String, CodingKey {
        case maxTminC = "max_tmin_c"
        case minCount = "min_count"
        case windowDays = "window_days"
        case elseFactor = "else_factor"
    }
}

public struct WeatherNeeds: Codable, Equatable, Sendable {
    public var rainWindowDays: [Int]
    public var rainMinMm: Double
    public var rainOptMm: Double
    public var lagDays: [Int]
    public var soilTempC: Trapezoid
    public var frostKillC: Double
    public var frostRecoveryDays: Int
    public var dryWindowDays: Int
    public var dryDayPenalty: Double
    public var coldNights: ColdNightsRule?

    enum CodingKeys: String, CodingKey {
        case rainWindowDays = "rain_window_days"
        case rainMinMm = "rain_min_mm"
        case rainOptMm = "rain_opt_mm"
        case lagDays = "lag_days"
        case soilTempC = "soil_temp_c"
        case frostKillC = "frost_kill_c"
        case frostRecoveryDays = "frost_recovery_days"
        case dryWindowDays = "dry_window_days"
        case dryDayPenalty = "dry_day_penalty"
        case coldNights = "cold_nights"
    }

    public var windowNear: Int { rainWindowDays.first ?? 7 }
    public var windowFar: Int { rainWindowDays.last ?? 21 }
    public var lagLo: Int { lagDays.first ?? 7 }
    public var lagHi: Int { lagDays.last ?? 14 }
}

public struct TerrainNeeds: Codable, Equatable, Sendable {
    public var edgeBonus: Double
    public var interiorFactor: Double

    enum CodingKeys: String, CodingKey {
        case edgeBonus = "edge_bonus"
        case interiorFactor = "interior_factor"
    }
}

public struct Lookalike: Codable, Equatable, Sendable, Hashable {
    public var name: String
    public var text: String
}

public struct SpeciesProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var namePl: String
    public var nameLat: String
    public var edible: Bool
    public var ecology: Ecology
    public var hosts: [String: Double]
    public var standAge: Trapezoid?
    public var tsl: [String: Double]
    public var moisturePref: [MoistureClass]
    public var arableFormerlyPenalty: Double
    public var season: SeasonWindow
    public var weather: WeatherNeeds
    public var terrain: TerrainNeeds
    public var structBonus: [String: Double]
    public var lookalikes: [Lookalike]
    public var notice: String?
    public var explain: [String: String]
    public var source: String

    enum CodingKeys: String, CodingKey {
        case id, edible, ecology, hosts, tsl, season, weather, terrain, lookalikes, notice, explain, source
        case namePl = "name_pl"
        case nameLat = "name_lat"
        case standAge = "stand_age"
        case moisturePref = "moisture_pref"
        case arableFormerlyPenalty = "arable_formerly_penalty"
        case structBonus = "struct_bonus"
    }
}
