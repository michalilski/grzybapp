import Foundation
import GrzybEngine

/// Region snapshot on disk (BDL GeoJSON + Open-Meteo JSON) used by the CLI and golden tests.
public struct FixtureRegion {
    struct Metadata: Decodable {
        let name: String
        let bbox: BoundingBox
        let weather: String
        let weather_today: String
    }

    public let name: String
    public let geometry: GridGeometry
    public let cells: [CellFeatures]
    public let weather: WeatherSeries

    public init(directory: URL, knowledge: KnowledgeBase) throws {
        let meta = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: directory.appendingPathComponent("region.json")))
        let read = { (name: String) in try GeoJSONParser.features(from: Data(contentsOf: directory.appendingPathComponent(name))) }
        let stands = try read("stands_lp.geojson").compactMap { BDLRecordMapper.stand($0, layer: .stateForest) }
            + read("stands_pul.geojson").compactMap { BDLRecordMapper.stand($0, layer: .otherForest) }
        let sites = try read("sites.geojson").compactMap(BDLRecordMapper.site)
        name = meta.name
        geometry = GridGeometry(bbox: meta.bbox, cellSizeM: knowledge.parameters.grid.cellSizeM)
        cells = GridBuilder(sites: knowledge.sites).build(geometry: geometry, stands: stands, siteRecords: sites)
        let today = DayStamp(iso: meta.weather_today) ?? .today()
        let weatherData = try Data(contentsOf: directory.appendingPathComponent(meta.weather))
        weather = WeatherSeries(try OpenMeteoParser.days(from: weatherData, today: today))
    }

    public func session(knowledge: KnowledgeBase, weather override: WeatherSeries? = nil, observations: [FieldObservation] = [], year: Int) -> ScoringSession {
        ScoringSession(
            knowledge: knowledge, species: knowledge.atlasSpecies, geometry: geometry, cells: cells,
            weather: override ?? weather, observations: observations, year: year
        )
    }
}
