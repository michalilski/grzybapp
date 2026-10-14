import Foundation

/// Weather-derived factors for one species on one day, with the inputs behind them.
public struct WeatherFactors: Codable, Equatable, Sendable {
    public var available: Bool
    public var rain: Double
    public var rainMm: Double
    public var rainBase: Double
    public var soilMoisture: Double?
    public var soilWater: Double
    public var dryDays: Int
    public var dryPenalty: Double
    public var usesForecast: Bool
    public var temp: Double
    public var soilTempC: Double?
    public var coldNights: Int?
    public var coldNightsShort: Bool
    public var frost: Double
    public var frostDaysAgo: Int?

    public static func unavailable(_ factor: Double) -> WeatherFactors {
        WeatherFactors(
            available: false, rain: factor, rainMm: 0, rainBase: factor, soilMoisture: nil, soilWater: 0, dryDays: 0, dryPenalty: 0,
            usesForecast: false, temp: factor, soilTempC: nil, coldNights: nil, coldNightsShort: false,
            frost: 1, frostDaysAgo: nil
        )
    }
}

/// Computes rain, temperature and frost factors from the regional weather series.
public struct WeatherIndex: Sendable {
    public let parameters: EngineParameters.Scoring

    public init(parameters: EngineParameters.Scoring) {
        self.parameters = parameters
    }

    public func factors(for species: SpeciesProfile, on day: DayStamp, weather: WeatherSeries) -> WeatherFactors {
        let needs = species.weather
        let window = weather.range(from: day.adding(-needs.windowFar), to: day.adding(-needs.windowNear))
        guard !window.isEmpty, weather.covers(day.adding(-1)) || weather.covers(day) else {
            return .unavailable(parameters.missingWeatherFactor)
        }
        let rainMm = window.reduce(0) { $0 + precipitation(of: $1) }
        let moisture = meanSoilMoisture(endingAt: day, weather: weather)
        let soilWater = moisture.map(soilWaterFactor) ?? 0
        let base = max(rainCurve(needs).value(at: rainMm), soilWater)
        let dryDays = dryDayCount(before: day, window: needs.dryWindowDays, weather: weather)
        let penalty = needs.dryDayPenalty * Double(dryDays)
        let soil = meanSoilTemp(endingAt: day, weather: weather)
        let cold = coldNights(rule: needs.coldNights, endingAt: day, weather: weather)
        let frost = frostState(needs: needs, endingAt: day, weather: weather)
        let coldShort = cold.map { $0 < (needs.coldNights?.minCount ?? 0) } ?? false
        var temp = soil.map { needs.soilTempC.value(at: $0) } ?? parameters.missingWeatherFactor
        if coldShort, let rule = needs.coldNights { temp = min(temp, rule.elseFactor) }
        return WeatherFactors(
            available: true,
            rain: (base - penalty).clamped(0, 1),
            rainMm: rainMm,
            rainBase: base,
            soilMoisture: moisture,
            soilWater: soilWater,
            dryDays: dryDays,
            dryPenalty: min(penalty, base),
            usesForecast: window.contains { $0.isForecast },
            temp: temp,
            soilTempC: soil,
            coldNights: cold,
            coldNightsShort: coldShort,
            frost: frost.factor,
            frostDaysAgo: frost.daysAgo
        )
    }

    public func precipitation(of day: WeatherDay) -> Double {
        day.isForecast ? day.precipMm * parameters.forecastRainFactor : day.precipMm
    }

    func rainCurve(_ needs: WeatherNeeds) -> LinearCurve {
        LinearCurve([(0, 0), (needs.rainMinMm, 0.5), (needs.rainOptMm, 1)])
    }

    /// Soil moisture keeps fruiting going between rains, but never counts as much as a fresh rain pulse.
    func soilWaterFactor(_ moisture: Double) -> Double {
        let curve = LinearCurve([(parameters.soilMoistureDry, 0), (parameters.soilMoistureMid, 0.5), (parameters.soilMoistureWet, 1)])
        return curve.value(at: moisture) * parameters.soilMoistureWeight
    }

    func meanSoilMoisture(endingAt day: DayStamp, weather: WeatherSeries) -> Double? {
        let values = weather.range(from: day.adding(-(parameters.soilMoistureDays - 1)), to: day).compactMap(\.soilMoisture)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func dryDayCount(before day: DayStamp, window: Int, weather: WeatherSeries) -> Int {
        weather.range(from: day.adding(-window), to: day.adding(-1))
            .filter { precipitation(of: $0) < parameters.dryDayThresholdMm }
            .count
    }

    func meanSoilTemp(endingAt day: DayStamp, weather: WeatherSeries) -> Double? {
        let values = weather.range(from: day.adding(-(parameters.soilTempDays - 1)), to: day).compactMap(\.soilOrAirTemp)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func coldNights(rule: ColdNightsRule?, endingAt day: DayStamp, weather: WeatherSeries) -> Int? {
        guard let rule else { return nil }
        let days = weather.range(from: day.adding(-(rule.windowDays - 1)), to: day)
        return days.filter { ($0.tminC ?? .infinity) < rule.maxTminC }.count
    }

    func frostState(needs: WeatherNeeds, endingAt day: DayStamp, weather: WeatherSeries) -> (factor: Double, daysAgo: Int?) {
        let recovery = max(1, needs.frostRecoveryDays)
        for ago in 0..<recovery {
            guard let w = weather.day(day.adding(-ago)), let tmin = w.tminC, tmin <= needs.frostKillC else { continue }
            let floor = parameters.frostFloor
            return (floor + (1 - floor) * Double(ago) / Double(recovery), ago)
        }
        return (1, nil)
    }
}
