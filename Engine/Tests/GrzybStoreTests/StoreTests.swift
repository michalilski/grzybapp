import XCTest
@testable import GrzybEngine
@testable import GrzybStore

final class StoreTests: XCTestCase {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase.inMemory()
    }

    private func sampleRegion() -> Region {
        Region(name: "Test", bbox: BoundingBox(minLon: 21.33, minLat: 52.02, maxLon: 21.40, maxLat: 52.065), cellSizeM: 100)
    }

    func testGridRoundTripKeepsUserOverrides() throws {
        let db = try makeDatabase()
        let regions = RegionRepository(db)
        let region = sampleRegion()
        try regions.save(region)
        let cell = CellFeatures(cellIndex: 5, lon: 21.35, lat: 52.03, dominantSpecies: "SO", dominantShare: 0.8, admixture: ["BRZ", "DB"], standAge: 60, siteType: "Bśw", distEdgeM: 150)
        try regions.replaceForest(regionId: region.id, stands: [], sites: [], cells: [cell])
        try regions.setOverride(regionId: region.id, cellIndex: 5, override: .clearcut)
        try regions.replaceForest(regionId: region.id, stands: [], sites: [], cells: [cell])
        let loaded = try regions.cells(regionId: region.id)
        XCTAssertEqual(loaded.first?.admixture, ["BRZ", "DB"])
        XCTAssertEqual(loaded.first?.override, .clearcut)
    }

    func testWeatherUpsertReplacesForecast() throws {
        let db = try makeDatabase()
        let region = sampleRegion()
        try RegionRepository(db).save(region)
        let repo = WeatherRepository(db)
        let day = DayStamp(iso: "2026-10-10")!
        try repo.save([WeatherDay(day: day, precipMm: 5, tminC: 3, tmaxC: 10, soilTempC: 9, soilMoisture: nil, humidity: nil, isForecast: true)], regionId: region.id)
        try repo.save([WeatherDay(day: day, precipMm: 8, tminC: 3, tmaxC: 10, soilTempC: 9, soilMoisture: nil, humidity: nil, isForecast: false)], regionId: region.id)
        let series = try repo.series(regionId: region.id)
        XCTAssertEqual(series.days.count, 1)
        XCTAssertEqual(series.day(day)?.precipMm, 8)
        XCTAssertEqual(series.day(day)?.isForecast, false)
    }

    func testExportImportRoundTrip() throws {
        let source = try makeDatabase()
        let region = sampleRegion()
        try RegionRepository(source).save(region)
        var obs = FieldObservation(regionId: region.id, speciesId: "boletus_edulis", kind: .found, amount: 3, lon: 21.35, lat: 52.03, observedAt: Date(timeIntervalSince1970: 1_790_000_000))
        obs.context = ObservationContext(siteType: "Bśw", dominantSpecies: "SO", dayOfYear: 250, daysSinceRainEvent: 9)
        try ObservationRepository(source).save(obs)
        let change = CalibrationChange(speciesId: "boletus_edulis", parameter: "tsl.Lśw", oldValue: [0.5], newValue: [0.6], reason: "test", observationIds: [obs.id])
        try SpeciesRuleRepository(source).apply(change, at: Date(timeIntervalSince1970: 1_790_000_000))
        let data = try ExportService(source).exportJSON()

        let target = try makeDatabase()
        let created = try ExportService(target).importJSON(data)
        XCTAssertEqual(created.map(\.id), [region.id])
        XCTAssertEqual(try ObservationRepository(target).all(), [obs])
        XCTAssertEqual(try SpeciesRuleRepository(target).overrides().first?.value, [0.6])
        XCTAssertEqual(try SpeciesRuleRepository(target).log().count, 1)
    }

    func testRevertRestoresOldValue() throws {
        let db = try makeDatabase()
        let rules = SpeciesRuleRepository(db)
        let change = CalibrationChange(speciesId: "boletus_edulis", parameter: "tsl.Lśw", oldValue: [0.5], newValue: [0.6], reason: "r", observationIds: [])
        try rules.apply(change)
        let entry = try XCTUnwrap(rules.log().first)
        try rules.revert(entry)
        XCTAssertEqual(try rules.overrides().first?.value, [0.5])
        XCTAssertEqual(try rules.log().first?.reverted, true)
    }
}
