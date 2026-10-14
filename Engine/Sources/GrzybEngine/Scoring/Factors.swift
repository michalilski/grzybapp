import Foundation

/// Cell-dependent, weather-independent factors (H, A, T, P, R).
public struct StaticFactors: Codable, Equatable, Sendable {
    public var host: Double
    public var age: Double
    public var site: Double
    public var sitePenalty: Double
    public var terrain: Double
    public var hostInferred: Bool
    public var siteSource: SiteSource
    public var droughtRelief: Double = 0

    public enum SiteSource: String, Codable, Sendable {
        case data, geology, missing
    }

    public var product: Double {
        host * age * site * sitePenalty * terrain
    }
}

/// Weather and calendar factors (F, W_rain, W_temp, W_frost) shared by every cell of a region.
public struct DynamicFactors: Codable, Equatable, Sendable {
    public var season: Double
    public var weather: WeatherFactors

    public var product: Double {
        product(droughtRelief: 0)
    }

    /// Moist sites keep a share of the missing water factor during dry spells.
    public func water(droughtRelief: Double) -> Double {
        weather.rain + (1 - weather.rain) * droughtRelief
    }

    public func product(droughtRelief: Double) -> Double {
        season * water(droughtRelief: droughtRelief) * weather.temp * weather.frost
    }
}

/// Full factor set stored with observations for later calibration.
public struct FactorSet: Codable, Equatable, Sendable {
    public var host: Double
    public var age: Double
    public var site: Double
    public var sitePenalty: Double
    public var terrain: Double
    public var season: Double
    public var rain: Double
    public var temp: Double
    public var frost: Double
    public var user: Double

    public init(staticFactors s: StaticFactors, dynamic d: DynamicFactors, user: Double) {
        host = s.host
        age = s.age
        site = s.site
        sitePenalty = s.sitePenalty
        terrain = s.terrain
        season = d.season
        rain = d.weather.rain
        temp = d.weather.temp
        frost = d.weather.frost
        self.user = user
    }
}

public enum PotentialBand: Int, Codable, Sendable, CaseIterable, Comparable {
    case low, moderate, good, veryGood

    public init(score: Double, bands: EngineParameters.Bands) {
        switch score {
        case bands.veryGood...: self = .veryGood
        case bands.good...: self = .good
        case bands.moderate...: self = .moderate
        default: self = .low
        }
    }

    public var label: String {
        switch self {
        case .low: "niski"
        case .moderate: "umiarkowany"
        case .good: "dobry"
        case .veryGood: "bardzo dobry"
        }
    }

    public static func < (lhs: PotentialBand, rhs: PotentialBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
