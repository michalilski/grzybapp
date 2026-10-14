import Foundation
@testable import GrzybEngine

enum TestSupport {
    static let knowledge: KnowledgeBase = {
        do { return try KnowledgeBase.bundled() } catch { fatalError("knowledge: \(error)") }
    }()

    static func species(_ id: String) -> SpeciesProfile {
        guard let profile = knowledge.atlasSpecies.first(where: { $0.id == id }) else { fatalError("missing \(id)") }
        return profile
    }

    static var fixturesURL: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    }

    static var sourceFixturesURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    /// Deterministic 45-day series: 60 mm spell 10–12 days before `end`, light showers on days 1, 3 and 5.
    static func syntheticWeather(end: DayStamp, soilTemp: Double = 13, tmin: Double = 8) -> WeatherSeries {
        let days = (0..<45).map { offset -> WeatherDay in
            let day = end.adding(-44 + offset)
            let ago = end - day
            let precip: Double = switch ago {
            case 10...12: 20
            case 1, 3, 5: 2
            default: 0
            }
            return WeatherDay(
                day: day, precipMm: precip, tminC: tmin, tmaxC: tmin + 8, soilTempC: soilTemp,
                soilMoisture: 0.25, humidity: 80, isForecast: false
            )
        }
        return WeatherSeries(days)
    }

    static func cell(
        index: Int = 0, tree: String? = "SO", share: Double = 1, age: Int? = 70, site: String? = "Bśw",
        distEdge: Double = 500, arable: Bool = false
    ) -> CellFeatures {
        CellFeatures(
            cellIndex: index, lon: 21.36, lat: 52.04, standId: "s1", dominantSpecies: tree, dominantShare: share,
            standAge: age, standYear: 2024, siteId: "t1", siteType: site, arableFormerly: arable, distEdgeM: distEdge
        )
    }
}
