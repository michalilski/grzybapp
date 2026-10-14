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
