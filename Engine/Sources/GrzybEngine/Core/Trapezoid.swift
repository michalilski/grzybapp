import Foundation

/// Trapezoidal membership: 0 outside [min, max], 1 inside [optLo, optHi], linear in between.
public struct Trapezoid: Codable, Equatable, Sendable {
    public var min: Double
    public var optLo: Double
    public var optHi: Double
    public var max: Double

    public init(min: Double, optLo: Double, optHi: Double, max: Double) {
        self.min = min
        self.optLo = optLo
        self.optHi = optHi
        self.max = max
    }

    enum CodingKeys: String, CodingKey {
        case min, max
        case optLo = "opt_lo"
        case optHi = "opt_hi"
    }

    public func value(at x: Double) -> Double {
        if x <= min || x >= max { return x >= optLo && x <= optHi ? 1 : 0 }
        if x < optLo { return (x - min) / (optLo - min) }
        if x <= optHi { return 1 }
        return (max - x) / (max - optHi)
    }
}

/// Piecewise-linear curve through sorted (x, y) points, flat beyond the ends.
public struct LinearCurve: Sendable {
    public let points: [(x: Double, y: Double)]

    public init(_ points: [(Double, Double)]) {
        self.points = points.map { (x: $0.0, y: $0.1) }
    }

    public func value(at x: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.x {
            guard b.x > a.x else { return b.y }
            return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
        }
        return last.y
    }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double {
        Swift.min(Swift.max(self, lo), hi)
    }
}
