import Foundation
import GrzybEngine

/// Client for Open-Meteo forecast API: 92 past days plus 16 days of forecast in one request.
public struct OpenMeteoClient: Sendable {
    public static let baseURL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(at point: Coordinate, today: DayStamp = .today()) async throws -> [WeatherDay] {
        var request = URLRequest(url: url(for: point))
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DataError.http(http.statusCode)
        }
        return try OpenMeteoParser.days(from: data, today: today)
    }

    func url(for point: Coordinate) -> URL {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", point.lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", point.lon)),
            URLQueryItem(name: "past_days", value: "92"),
            URLQueryItem(name: "forecast_days", value: "16"),
            URLQueryItem(name: "daily", value: "precipitation_sum,temperature_2m_min,temperature_2m_max"),
            URLQueryItem(name: "hourly", value: "soil_temperature_7_to_28cm,soil_moisture_7_to_28cm,relative_humidity_2m"),
            URLQueryItem(name: "timezone", value: "Europe/Warsaw"),
        ]
        return components.url!
    }
}

/// Converts Open-Meteo JSON into daily aggregates; hourly soil values are averaged per day.
public enum OpenMeteoParser {
    private struct Response: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let precipitation_sum: [Double?]
            let temperature_2m_min: [Double?]
            let temperature_2m_max: [Double?]
        }

        struct Hourly: Decodable {
            let time: [String]
            let soil_temperature_7_to_28cm: [Double?]?
            let soil_moisture_7_to_28cm: [Double?]?
            let relative_humidity_2m: [Double?]?
        }

        let daily: Daily
        let hourly: Hourly?
    }

    public static func days(from data: Data, today: DayStamp) throws -> [WeatherDay] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let hourly = response.hourly
        let soilT = dailyMeans(hourly?.time ?? [], hourly?.soil_temperature_7_to_28cm ?? [])
        let soilM = dailyMeans(hourly?.time ?? [], hourly?.soil_moisture_7_to_28cm ?? [])
        let humidity = dailyMeans(hourly?.time ?? [], hourly?.relative_humidity_2m ?? [])
        let daily = response.daily
        return daily.time.enumerated().compactMap { i, iso in
            guard let day = DayStamp(iso: iso), let precip = daily.precipitation_sum[safe: i] ?? nil else { return nil }
            return WeatherDay(
                day: day,
                precipMm: precip,
                tminC: daily.temperature_2m_min[safe: i] ?? nil,
                tmaxC: daily.temperature_2m_max[safe: i] ?? nil,
                soilTempC: soilT[iso],
                soilMoisture: soilM[iso],
                humidity: humidity[iso],
                isForecast: day > today
            )
        }
    }

    private static func dailyMeans(_ times: [String], _ values: [Double?]) -> [String: Double] {
        var sums: [String: (Double, Int)] = [:]
        for (time, value) in zip(times, values) {
            guard let value else { continue }
            let key = String(time.prefix(10))
            let current = sums[key] ?? (0, 0)
            sums[key] = (current.0 + value, current.1 + 1)
        }
        return sums.mapValues { $0.0 / Double($0.1) }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
