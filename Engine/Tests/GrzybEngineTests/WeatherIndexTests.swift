import XCTest
@testable import GrzybEngine

final class WeatherIndexTests: XCTestCase {
    private let index = WeatherIndex(parameters: TestSupport.knowledge.parameters.scoring)
    private let day = DayStamp(iso: "2026-10-09")!

    private func series(rain: [Int: Double], forecastFrom: Int? = nil, tmin: Double = 8) -> WeatherSeries {
        WeatherSeries((0..<40).map { ago in
            WeatherDay(
                day: day.adding(-ago), precipMm: rain[ago] ?? 0, tminC: tmin, tmaxC: tmin + 8, soilTempC: 14,
                soilMoisture: nil, humidity: nil, isForecast: forecastFrom.map { ago < $0 } ?? false
            )
        })
    }

    func testRainWindowEdgesAreInclusive() {
        let boletus = TestSupport.species("boletus_edulis")
        let inside = index.factors(for: boletus, on: day, weather: series(rain: [7: 10, 21: 15]))
        XCTAssertEqual(inside.rainMm, 25, accuracy: 1e-9)
        let outside = index.factors(for: boletus, on: day, weather: series(rain: [6: 10, 22: 15]))
        XCTAssertEqual(outside.rainMm, 0, accuracy: 1e-9)
    }

    func testRainCurveHitsHalfAtMinimumAndOneAtOptimum() {
        let boletus = TestSupport.species("boletus_edulis")
        let wetRecent = [1: 2.0, 2: 2.0, 3: 2.0, 4: 2.0, 5: 2.0]
        let atMin = index.factors(for: boletus, on: day, weather: series(rain: wetRecent.merging([10: 25]) { a, _ in a }))
        XCTAssertEqual(atMin.rainBase, 0.5, accuracy: 1e-9)
        XCTAssertEqual(atMin.rain, 0.5, accuracy: 1e-9)
        let atOpt = index.factors(for: boletus, on: day, weather: series(rain: wetRecent.merging([10: 50]) { a, _ in a }))
        XCTAssertEqual(atOpt.rain, 1, accuracy: 1e-9)
    }

    func testDryDaysPenaltyCountsOnlyWindow() {
        let boletus = TestSupport.species("boletus_edulis")
        let f = index.factors(for: boletus, on: day, weather: series(rain: [10: 50]))
        XCTAssertEqual(f.dryDays, 5)
        XCTAssertEqual(f.rain, 1 - 5 * 0.08, accuracy: 1e-9)
    }

    func testForecastRainIsDiscounted() {
        let boletus = TestSupport.species("boletus_edulis")
        let f = index.factors(for: boletus, on: day, weather: series(rain: [10: 40], forecastFrom: 20))
        XCTAssertEqual(f.rainMm, 28, accuracy: 1e-9)
        XCTAssertTrue(f.usesForecast)
    }

    func testFrostRecoversLinearly() {
        let boletus = TestSupport.species("boletus_edulis")
        var days = series(rain: [10: 50]).days
        if let i = days.firstIndex(where: { $0.day == day.adding(-5) }) { days[i].tminC = -3 }
        let f = index.factors(for: boletus, on: day, weather: WeatherSeries(days))
        XCTAssertEqual(f.frostDaysAgo, 5)
        XCTAssertEqual(f.frost, 0.2 + 0.8 * 5 / 10, accuracy: 1e-9)
    }

    func testHoneyFungusNeedsColdNights() {
        let armillaria = TestSupport.species("armillaria")
        let warm = index.factors(for: armillaria, on: day, weather: series(rain: [10: 40], tmin: 12))
        XCTAssertTrue(warm.coldNightsShort)
        XCTAssertLessThanOrEqual(warm.temp, 0.3)
        let cold = index.factors(for: armillaria, on: day, weather: series(rain: [10: 40], tmin: 6))
        XCTAssertFalse(cold.coldNightsShort)
    }

    func testMissingWeatherIsNeutralAndFlagged() {
        let f = index.factors(for: TestSupport.species("boletus_edulis"), on: day, weather: WeatherSeries([]))
        XCTAssertFalse(f.available)
        XCTAssertEqual(f.rain, 0.5)
    }

    func testFlushDetectedAfterHeavyRainAndWarmSoil() {
        let boletus = TestSupport.species("boletus_edulis")
        let detector = FlushDetector(parameters: TestSupport.knowledge.parameters)
        let weather = series(rain: [6: 20, 5: 20, 4: 15])
        let flush = detector.detect(for: boletus, today: day, weather: weather)
        XCTAssertEqual(flush?.rainEnd, day.adding(-4))
        XCTAssertEqual(flush?.from, day.adding(-4 + 8))
        XCTAssertEqual(flush?.to, day.adding(-4 + 14))
        XCTAssertNil(detector.detect(for: boletus, today: day, weather: series(rain: [5: 10])))
    }
}
