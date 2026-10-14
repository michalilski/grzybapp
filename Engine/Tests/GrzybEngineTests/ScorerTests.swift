import XCTest
@testable import GrzybEngine

final class ScorerTests: XCTestCase {
    private let scorer = Scorer(knowledge: TestSupport.knowledge)

    func testHostGateZeroesMycorrhizalSpeciesWithoutPartner() {
        let scaber = TestSupport.species("leccinum_scabrum")
        let pine = scorer.staticFactors(for: TestSupport.cell(tree: "SO"), species: scaber)
        XCTAssertEqual(pine.host, 0)
        XCTAssertEqual(pine.product, 0)
        let birch = scorer.staticFactors(for: TestSupport.cell(tree: "BRZ", age: 40, site: "BMw"), species: scaber)
        XCTAssertEqual(birch.host, 1)
    }

    func testAdmixtureFromForestTypeCountsForRemainingShare() {
        var cell = TestSupport.cell(tree: "SO", share: 0.7)
        cell.admixture = ["BRZ"]
        let f = scorer.staticFactors(for: cell, species: TestSupport.species("leccinum_scabrum"))
        XCTAssertEqual(f.host, 0.3, accuracy: 1e-9)
    }

    func testSiteGateZeroesBoletusInAlderSwamp() {
        let f = scorer.staticFactors(for: TestSupport.cell(site: "Ol"), species: TestSupport.species("boletus_edulis"))
        XCTAssertEqual(f.site, 0)
        XCTAssertEqual(f.product, 0)
    }

    func testSaprotrophIgnoresHost() {
        let f = scorer.staticFactors(for: TestSupport.cell(tree: nil, age: nil, site: "Lśw"), species: TestSupport.species("macrolepiota_procera"))
        XCTAssertEqual(f.host, 1)
        XCTAssertEqual(f.age, 1)
    }

    func testMissingSiteFallsBackToGeologyWithUncertainty() {
        var cell = TestSupport.cell(site: nil)
        cell.geology = "Qfp"
        let f = scorer.staticFactors(for: cell, species: TestSupport.species("boletus_edulis"))
        XCTAssertEqual(f.siteSource, .geology)
        XCTAssertEqual(f.site, 0.7, accuracy: 1e-9)
    }

    func testArablePenaltyAndEdgeBonus() {
        let boletus = TestSupport.species("boletus_edulis")
        let f = scorer.staticFactors(for: TestSupport.cell(distEdge: 50, arable: true), species: boletus)
        XCTAssertEqual(f.sitePenalty, 0.7, accuracy: 1e-9)
        XCTAssertEqual(f.terrain, 1.1, accuracy: 1e-9)
    }

    func testTerrainOverrideClearcutKillsAge() {
        var cell = TestSupport.cell()
        cell.override = .clearcut
        let f = scorer.staticFactors(for: cell, species: TestSupport.species("boletus_edulis"))
        XCTAssertEqual(f.age, 0)
    }

    func testSeasonFloorOutsideWindow() {
        XCTAssertEqual(scorer.seasonFactor(TestSupport.species("boletus_edulis"), doy: 30), 0.05)
        XCTAssertEqual(scorer.seasonFactor(TestSupport.species("boletus_edulis"), doy: 260), 1)
    }

    func testIdealConditionsScoreVeryGood() {
        let day = DayStamp(iso: "2026-09-20")!
        let weather = TestSupport.syntheticWeather(end: day)
        let session = ScoringSession(
            knowledge: TestSupport.knowledge, species: TestSupport.knowledge.atlasSpecies,
            geometry: GridGeometry(bbox: BoundingBox(minLon: 21.35, minLat: 52.03, maxLon: 21.37, maxLat: 52.05), cellSizeM: 100),
            cells: [TestSupport.cell(index: 0)], weather: weather, observations: [], year: 2026
        )
        let boletus = session.ranking(at: 0, on: day).first { $0.species.id == "boletus_edulis" }
        XCTAssertEqual(boletus?.band, .veryGood)
        XCTAssertEqual(boletus?.reasons.first?.kind, .positive)
    }
}

final class AggregationTests: XCTestCase {
    func testAnyOfCombinesIndependentSpecies() {
        let general = PotentialAggregation.general(diversityBonus: 0.4)
        XCTAssertEqual(general.combine([50, 50]), 50 + 0.4 * 25, accuracy: 1e-9)
        XCTAssertEqual(general.combine([80]), 80, accuracy: 1e-9)
        XCTAssertEqual(general.combine([5, 5, 5]), 5 + 0.4 * (14.2625 - 5), accuracy: 1e-9)
        XCTAssertEqual(PotentialAggregation.best.combine([50, 50]), 50)
        XCTAssertEqual(general.combine([]), 0)
    }

    func testGeneralLayerIsAtLeastBestSpecies() throws {
        let day = DayStamp(iso: "2026-10-09")!
        let session = ScoringSession(
            knowledge: TestSupport.knowledge, species: TestSupport.knowledge.atlasSpecies,
            geometry: GridGeometry(bbox: BoundingBox(minLon: 21.35, minLat: 52.03, maxLon: 21.37, maxLat: 52.05), cellSizeM: 100),
            cells: [TestSupport.cell(index: 0)], weather: TestSupport.syntheticWeather(end: day), observations: [], year: 2026
        )
        let ids = TestSupport.knowledge.atlasSpecies.map(\.id)
        let best = session.layer(on: day, speciesIds: ids).values[0]
        let general = session.layer(on: day, speciesIds: ids, aggregation: session.generalAggregation).values[0]
        let expected = session.generalAggregation.combine(session.ranking(at: 0, on: day).map(\.score))
        XCTAssertGreaterThanOrEqual(general, best)
        XCTAssertEqual(Double(general), expected, accuracy: 0.01)
        XCTAssertEqual(session.layer(on: day, speciesIds: ids, aggregation: session.generalAggregation).values[1], -1)
    }

    func testHabitatLayerIgnoresDrought() {
        let day = DayStamp(iso: "2026-10-09")!
        let dry = WeatherSeries((0..<40).map {
            WeatherDay(day: day.adding(-$0), precipMm: 0, tminC: 8, tmaxC: 16, soilTempC: 13, soilMoisture: nil, humidity: nil, isForecast: false)
        })
        let session = ScoringSession(
            knowledge: TestSupport.knowledge, species: TestSupport.knowledge.atlasSpecies,
            geometry: GridGeometry(bbox: BoundingBox(minLon: 21.35, minLat: 52.03, maxLon: 21.37, maxLat: 52.05), cellSizeM: 100),
            cells: [TestSupport.cell(index: 0)], weather: dry, observations: [], year: 2026
        )
        let ids = TestSupport.knowledge.atlasSpecies.map(\.id)
        XCTAssertLessThan(session.layer(on: day, speciesIds: ids).values[0], 1)
        let habitat = session.habitatLayer(speciesIds: ids, aggregation: session.generalAggregation).values[0]
        XCTAssertGreaterThan(habitat, 90)
        XCTAssertEqual(Double(habitat), session.habitatScore(at: 0, speciesIds: ids, aggregation: session.generalAggregation), accuracy: 0.01)
    }
}
