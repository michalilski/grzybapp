import Foundation

/// Daily weather aggregate for a region (observed or forecast).
public struct WeatherDay: Codable, Equatable, Sendable {
    public var day: DayStamp
    public var precipMm: Double
    public var tminC: Double?
    public var tmaxC: Double?
    public var soilTempC: Double?
    public var soilMoisture: Double?
    public var humidity: Double?
    public var isForecast: Bool

    public init(
        day: DayStamp, precipMm: Double, tminC: Double?, tmaxC: Double?, soilTempC: Double?,
        soilMoisture: Double?, humidity: Double?, isForecast: Bool
    ) {
        self.day = day
        self.precipMm = precipMm
        self.tminC = tminC
        self.tmaxC = tmaxC
        self.soilTempC = soilTempC
        self.soilMoisture = soilMoisture
        self.humidity = humidity
        self.isForecast = isForecast
    }

    var soilOrAirTemp: Double? {
        if let soilTempC { return soilTempC }
        guard let tminC, let tmaxC else { return nil }
        return (tminC + tmaxC) / 2
    }
}

/// Lookup over daily weather keyed by day.
public struct WeatherSeries: Sendable {
    private let byDay: [DayStamp: WeatherDay]
    public let days: [WeatherDay]

    public init(_ days: [WeatherDay]) {
        self.days = days.sorted { $0.day < $1.day }
        byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    public var isEmpty: Bool { days.isEmpty }
    public var firstDay: DayStamp? { days.first?.day }
    public var lastDay: DayStamp? { days.last?.day }

    public func day(_ d: DayStamp) -> WeatherDay? {
        byDay[d]
    }

    public func range(from: DayStamp, to: DayStamp) -> [WeatherDay] {
        guard from <= to else { return [] }
        return (from.value...to.value).compactMap { byDay[DayStamp($0)] }
    }

    public func covers(_ d: DayStamp) -> Bool {
        byDay[d] != nil
    }
}
