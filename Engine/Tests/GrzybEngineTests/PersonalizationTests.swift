import XCTest
@testable import GrzybEngine

final class PersonalizationTests: XCTestCase {
    private let prior = LocalPrior(parameters: TestSupport.knowledge.parameters.prior)
    private let geometry = GridGeometry(
        bbox: BoundingBox(minLon: 21.33, minLat: 52.02, maxLon: 21.40, maxLat: 52.065), cellSizeM: 100
    )
    private let calibrator = Calibrator(knowledge: TestSupport.knowledge)

    private func date(_ iso: String) -> Date {
        DayStamp(iso: iso)!.date
    }

    private func found(_ amount: Int, at index: Int, on iso: String = "2026-09-28") -> FieldObservation {
        let c = geometry.center(of: index)
        return FieldObservation(speciesId: "boletus_edulis", kind: .found, amount: amount, lon: c.lon, lat: c.lat, observedAt: date(iso))
    }

    func testSingleBigFindRaisesNeighbourhood() {
        let field = prior.field(speciesId: "boletus_edulis", observations: [found(3, at: 1000)], geometry: geometry, year: 2026)
        XCTAssertEqual(field[1000]?.factor, 2.0)
        let neighbour = field[1001]?.factor ?? 1
        XCTAssertEqual(neighbour, exp(0.8 * exp(-0.5 * pow(geometry.center(of: 1000).distanceMeters(to: geometry.center(of: 1001)) / 150, 2))), accuracy: 1e-6)
        XCTAssertGreaterThan(neighbour, 1.5)
        XCTAssertNil(field[1000 + 20])
    }

    func testRepeatedSeasonsHitCeiling() {
        let obs = ["2024-09-20", "2025-09-20", "2026-09-20"].map { found(3, at: 1000, on: $0) }
        let field = prior.field(speciesId: "boletus_edulis", observations: obs, geometry: geometry, year: 2026)
        XCTAssertEqual(field[1000]?.factor, 2.0)
    }

    func testEmptyOnlyCountsWhenModelWasConfident() {
        let c = geometry.center(of: 1000)
        var low = FieldObservation(speciesId: "boletus_edulis", kind: .empty, lon: c.lon, lat: c.lat, observedAt: date("2026-09-28"))
        low.scoreAtTime = 10
        XCTAssertTrue(prior.field(speciesId: "boletus_edulis", observations: [low], geometry: geometry, year: 2026).isEmpty)
        var high = low
        high.scoreAtTime = 60
        let twice = [high, high]
        let factor = prior.field(speciesId: "boletus_edulis", observations: twice, geometry: geometry, year: 2026)[1000]?.factor
        XCTAssertEqual(factor ?? 1, 0.5, accuracy: 1e-9)
    }

    private func observation(kind: ObservationKind, site: String, host: Double = 1, siteFactor: Double, doy: Int = 250, rainAgo: Int? = nil) -> FieldObservation {
        let statics = StaticFactors(host: host, age: 1, site: siteFactor, sitePenalty: 1, terrain: 1, hostInferred: false, siteSource: .data)
        let dynamic = DynamicFactors(season: 1, weather: .unavailable(1))
        var obs = FieldObservation(speciesId: "boletus_edulis", kind: kind, lon: 21.36, lat: 52.04)
        obs.factors = FactorSet(staticFactors: statics, dynamic: dynamic, user: 1)
        obs.context = ObservationContext(siteType: site, dominantSpecies: "SO", dayOfYear: doy, daysSinceRainEvent: rainAgo)
        obs.scoreAtTime = 60
        return obs
    }

    func testCalibrationRaisesBottleneckSite() {
        let finds = (0..<7).map { _ in observation(kind: .found, site: "Lśw", siteFactor: 0.5) }
            + (0..<3).map { _ in observation(kind: .found, site: "Bśw", siteFactor: 1) }
        let change = calibrator.calibrate(species: TestSupport.species("boletus_edulis"), observations: finds, on: DayStamp(iso: "2026-10-03")!)
        XCTAssertEqual(change?.parameter, "tsl.Lśw")
        XCTAssertEqual(change?.oldValue, [0.5])
        XCTAssertEqual(change?.newValue.first ?? 0, 0.6, accuracy: 1e-9)
        XCTAssertEqual(change?.observationIds.count, 7)
        XCTAssertEqual(change?.reason, "Od 3.10.2026 podniesiono wagę siedliska Lśw dla gatunku Borowik szlachetny z 0,5 do 0,6 na podstawie 7 znalezisk")
    }

    func testCalibrationNeverOpensAGate() {
        let finds = (0..<10).map { _ in observation(kind: .found, site: "Ol", siteFactor: 0) }
        let change = calibrator.calibrate(species: TestSupport.species("boletus_edulis"), observations: finds, on: DayStamp(iso: "2026-10-03")!)
        XCTAssertNotEqual(change?.parameter, "tsl.Ol")
    }

    func testCalibrationLowersSharedFactorOfEmptyVisits() {
        let empties = (0..<6).map { _ in observation(kind: .empty, site: "BMśw", siteFactor: 1) }
        let change = calibrator.calibrate(species: TestSupport.species("boletus_edulis"), observations: empties, on: DayStamp(iso: "2026-10-03")!)
        XCTAssertEqual(change?.parameter, "hosts.SO")
        XCTAssertEqual(change?.newValue.first ?? 0, 0.9, accuracy: 1e-9)
    }

    func testCalibrationWidensSeason() {
        let finds = (0..<3).map { _ in observation(kind: .found, site: "Bśw", siteFactor: 1, doy: 160) }
        let change = calibrator.calibrate(species: TestSupport.species("boletus_edulis"), observations: finds, on: DayStamp(iso: "2026-06-12")!)
        XCTAssertEqual(change?.parameter, "season.start_doy")
        XCTAssertEqual(change?.newValue, [163])
    }

    func testCalibrationShiftsLag() {
        let finds = (0..<5).map { _ in observation(kind: .found, site: "Bśw", siteFactor: 1, rainAgo: 5) }
        let change = calibrator.calibrate(species: TestSupport.species("boletus_edulis"), observations: finds, on: DayStamp(iso: "2026-10-03")!)
        XCTAssertEqual(change?.parameter, "weather.lag_days")
        XCTAssertEqual(change?.newValue, [6, 12])
    }

    func testOverrideAppliesOnTopOfAtlas() {
        let override = ParameterOverride(speciesId: "boletus_edulis", path: "tsl.Lśw", value: [0.6], source: .calibration, changedAt: Date())
        let profiles = TestSupport.knowledge.species(applying: [override])
        XCTAssertEqual(profiles.first { $0.id == "boletus_edulis" }?.tsl["Lśw"], 0.6)
        XCTAssertEqual(TestSupport.species("boletus_edulis").tsl["Lśw"], 0.5)
    }
}
