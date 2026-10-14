import Foundation

/// Expected fruiting window after a heavy rain followed by warm soil.
public struct FlushForecast: Codable, Equatable, Sendable {
    public var speciesId: String
    public var rainEnd: DayStamp
    public var from: DayStamp
    public var to: DayStamp
}

public struct FlushDetector: Sendable {
    public let parameters: EngineParameters
    private let index: WeatherIndex

    public init(parameters: EngineParameters) {
        self.parameters = parameters
        index = WeatherIndex(parameters: parameters.scoring)
    }

    public func detect(for species: SpeciesProfile, today: DayStamp, weather: WeatherSeries) -> FlushForecast? {
        guard let last = weather.lastDay else { return nil }
        let earliest = today.adding(-species.weather.windowFar)
        var candidate: FlushForecast?
        var end = earliest
        while end <= last {
            if let flush = flush(endingAt: end, species: species, weather: weather), flush.to >= today {
                candidate = flush
            }
            end = end.adding(1)
        }
        return candidate
    }

    private func flush(endingAt end: DayStamp, species: SpeciesProfile, weather: WeatherSeries) -> FlushForecast? {
        let rainDays = weather.range(from: end.adding(-(parameters.flush.maxRainDays - 1)), to: end)
        let total = rainDays.reduce(0) { $0 + index.precipitation(of: $1) }
        guard total >= species.weather.rainOptMm, let endDay = weather.day(end), endDay.precipMm >= 1 else { return nil }
        let warm = weather.range(from: end.adding(1), to: end.adding(parameters.flush.warmDays))
        let warmEnough = warm.count == parameters.flush.warmDays
            && warm.allSatisfy { ($0.soilOrAirTemp ?? -99) >= species.weather.soilTempC.optLo }
        guard warmEnough else { return nil }
        return FlushForecast(
            speciesId: species.id,
            rainEnd: end,
            from: end.adding(species.weather.lagLo),
            to: end.adding(species.weather.lagHi)
        )
    }
}
