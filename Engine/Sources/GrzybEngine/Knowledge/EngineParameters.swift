import Foundation

/// Global heuristic constants loaded from `engine_params.json`.
public struct EngineParameters: Codable, Equatable, Sendable {
    public struct Scoring: Codable, Equatable, Sendable {
        public var seasonFloor: Double
        public var uncertaintyWeight: Double
        public var missingSiteTsl: Double
        public var unknownAgeFactor: Double
        public var moistureMismatch: Double
        public var degradedFactor: Double
        public var forecastRainFactor: Double
        public var frostFloor: Double
        public var dryDayThresholdMm: Double
        public var soilTempDays: Int
        public var missingWeatherFactor: Double
        public var edgeDistanceM: Double
        public var terrainMin: Double
        public var terrainMax: Double

        enum CodingKeys: String, CodingKey {
            case seasonFloor = "season_floor"
            case uncertaintyWeight = "uncertainty_weight"
            case missingSiteTsl = "missing_site_tsl"
            case unknownAgeFactor = "unknown_age_factor"
            case moistureMismatch = "moisture_mismatch"
            case degradedFactor = "degraded_factor"
            case forecastRainFactor = "forecast_rain_factor"
            case frostFloor = "frost_floor"
            case dryDayThresholdMm = "dry_day_threshold_mm"
            case soilTempDays = "soil_temp_days"
            case missingWeatherFactor = "missing_weather_factor"
            case edgeDistanceM = "edge_distance_m"
            case terrainMin = "terrain_min"
            case terrainMax = "terrain_max"
        }
    }

    public struct Bands: Codable, Equatable, Sendable {
        public var moderate: Double
        public var good: Double
        public var veryGood: Double

        enum CodingKeys: String, CodingKey {
            case moderate, good
            case veryGood = "very_good"
        }
    }

    public struct Prior: Codable, Equatable, Sendable {
        public var sigmaM: Double
        public var radiusSigmas: Double
        public var amountWeights: [Double]
        public var emptyWeight: Double
        public var yearDecay: [Double]
        public var minFactor: Double
        public var maxFactor: Double
        public var negativeMinScore: Double

        enum CodingKeys: String, CodingKey {
            case sigmaM = "sigma_m"
            case radiusSigmas = "radius_sigmas"
            case amountWeights = "amount_weights"
            case emptyWeight = "empty_weight"
            case yearDecay = "year_decay"
            case minFactor = "min_factor"
            case maxFactor = "max_factor"
            case negativeMinScore = "negative_min_score"
        }

        public func weight(forAmount amount: Int) -> Double {
            amountWeights[(amount - 1).clampedIndex(amountWeights.count)]
        }

        public func decay(years: Int) -> Double {
            yearDecay[max(0, years).clampedIndex(yearDecay.count)]
        }
    }

    public struct Calibration: Codable, Equatable, Sendable {
        public var everyObservations: Int
        public var majorityShare: Double
        public var step: Double
        public var maxValue: Double
        public var minValue: Double
        public var seasonOutsideCount: Int
        public var seasonStepDays: Int
        public var lagToleranceDays: Int
        public var lagStepDays: Int
        public var rainEventMm: Double

        enum CodingKeys: String, CodingKey {
            case everyObservations = "every_observations"
            case majorityShare = "majority_share"
            case step
            case maxValue = "max_value"
            case minValue = "min_value"
            case seasonOutsideCount = "season_outside_count"
            case seasonStepDays = "season_step_days"
            case lagToleranceDays = "lag_tolerance_days"
            case lagStepDays = "lag_step_days"
            case rainEventMm = "rain_event_mm"
        }
    }

    public struct Flush: Codable, Equatable, Sendable {
        public var maxRainDays: Int
        public var warmDays: Int

        enum CodingKeys: String, CodingKey {
            case maxRainDays = "max_rain_days"
            case warmDays = "warm_days"
        }
    }

    public struct Grid: Codable, Equatable, Sendable {
        public var cellSizeM: Double
        public var maxRegionKm: Double
        public var tileKm: Double

        enum CodingKeys: String, CodingKey {
            case cellSizeM = "cell_size_m"
            case maxRegionKm = "max_region_km"
            case tileKm = "tile_km"
        }
    }

    public var scoring: Scoring
    public var bands: Bands
    public var prior: Prior
    public var calibration: Calibration
    public var flush: Flush
    public var grid: Grid
}

extension Int {
    func clampedIndex(_ count: Int) -> Int {
        Swift.min(Swift.max(self, 0), count - 1)
    }
}
