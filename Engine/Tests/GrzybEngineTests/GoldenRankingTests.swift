import XCTest
@testable import GrzybData
@testable import GrzybEngine

/// Golden test: fixture region 5 × 5 km + synthetic weather → expected top-10 cells.
/// Run with UPDATE_GOLDEN=1 to deliberately rewrite `expected_ranking.json` after a heuristic change.
final class GoldenRankingTests: XCTestCase {
    private struct Entry: Codable, Equatable {
        let species: String
        let cells: [Int]
        let scores: [Int]
    }

    private let day = DayStamp(iso: "2026-10-09")!
    private let speciesIds = ["boletus_edulis", "imleria_badia", "leccinum_scabrum", "suillus_luteus"]

    private func makeSession() throws -> ScoringSession {
        let fixture = try FixtureRegion(directory: TestSupport.fixturesURL, knowledge: TestSupport.knowledge)
        return fixture.session(knowledge: TestSupport.knowledge, weather: TestSupport.syntheticWeather(end: day), year: day.year)
    }

    private func ranking(_ session: ScoringSession) -> [Entry] {
        speciesIds.map { id in
            let top = session.topCells(speciesId: id, on: day, limit: 10)
            return Entry(species: id, cells: top.map(\.cell.cellIndex), scores: top.map { Int($0.score.score.rounded()) })
        }
    }

    func testRankingMatchesGoldenFile() throws {
        let actual = ranking(try makeSession())
        let file = TestSupport.sourceFixturesURL.appendingPathComponent("expected_ranking.json")
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(actual).write(to: file)
        }
        let expected = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
        XCTAssertEqual(actual, expected)
    }

    func testDeterminism() throws {
        let a = try makeSession().layer(on: day, speciesIds: speciesIds)
        let b = try makeSession().layer(on: day, speciesIds: speciesIds)
        XCTAssertEqual(a.values, b.values)
        XCTAssertEqual(a.winners, b.winners)
    }

    func testFixtureGridHasForest() throws {
        let session = try makeSession()
        XCTAssertGreaterThan(session.cells.count, 1000)
        XCTAssertTrue(session.cells.contains { $0.siteType == "Bśw" && $0.dominantSpecies == "SO" })
    }

    func testFullRegionPerformance() throws {
        let fixture = try FixtureRegion(directory: TestSupport.fixturesURL, knowledge: TestSupport.knowledge)
        let big = Array(repeating: fixture.cells, count: 38).enumerated().flatMap { copy, cells in
            cells.map { cell -> CellFeatures in
                var c = cell
                c.cellIndex = copy * 2400 + cell.cellIndex
                return c
            }
        }
        let geometry = GridGeometry(bbox: BoundingBox(minLon: 21.0, minLat: 52.0, maxLon: 21.44, maxLat: 52.27), cellSizeM: 100)
        let session = ScoringSession(
            knowledge: TestSupport.knowledge, species: TestSupport.knowledge.atlasSpecies, geometry: geometry,
            cells: big.filter { $0.cellIndex < geometry.count }, weather: TestSupport.syntheticWeather(end: day),
            observations: [], year: 2026
        )
        let start = Date()
        _ = session.layer(on: day, speciesIds: TestSupport.knowledge.atlasSpecies.map(\.id))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }
}
