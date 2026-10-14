import XCTest
@testable import GrzybEngine

final class TrapezoidTests: XCTestCase {
    private let t = Trapezoid(min: 25, optLo: 50, optHi: 120, max: 200)

    func testBoundaries() {
        XCTAssertEqual(t.value(at: 25), 0)
        XCTAssertEqual(t.value(at: 50), 1)
        XCTAssertEqual(t.value(at: 120), 1)
        XCTAssertEqual(t.value(at: 200), 0)
        XCTAssertEqual(t.value(at: 10), 0)
        XCTAssertEqual(t.value(at: 250), 0)
    }

    func testSlopes() {
        XCTAssertEqual(t.value(at: 37.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(t.value(at: 160), 0.5, accuracy: 1e-9)
    }

    func testDegenerateLowerEdge() {
        let flat = Trapezoid(min: 0, optLo: 0, optHi: 10, max: 20)
        XCTAssertEqual(flat.value(at: 0), 1)
    }

    func testLinearCurve() {
        let curve = LinearCurve([(0, 0), (25, 0.5), (50, 1)])
        XCTAssertEqual(curve.value(at: 0), 0)
        XCTAssertEqual(curve.value(at: 25), 0.5)
        XCTAssertEqual(curve.value(at: 37.5), 0.75, accuracy: 1e-9)
        XCTAssertEqual(curve.value(at: 80), 1)
    }

    func testDayStampRoundTrip() {
        let day = DayStamp(iso: "2026-10-09")!
        XCTAssertEqual(day.iso, "2026-10-09")
        XCTAssertEqual(day.dayOfYear, 282)
        XCTAssertEqual(DayStamp(iso: "2024-03-01")!.dayOfYear, 61)
        XCTAssertEqual(day.adding(30).iso, "2026-11-08")
    }
}
