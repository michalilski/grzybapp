import Foundation

/// Prior multiplier for one cell, with the strongest observation behind it.
public struct PriorValue: Equatable, Sendable {
    public var factor: Double
    public var strongest: FieldObservation?
    public var distanceM: Double?
}

/// U_local = exp(Σ w · k(d) · g(Δt)), clamped; mycelium is persistent so nearby finds raise future scores.
public struct LocalPrior: Sendable {
    public let parameters: EngineParameters.Prior

    public init(parameters: EngineParameters.Prior) {
        self.parameters = parameters
    }

    public var radiusM: Double { parameters.sigmaM * parameters.radiusSigmas }

    /// Sparse map cellIndex → prior for every cell influenced by the observations.
    public func field(
        speciesId: String, observations: [FieldObservation], geometry: GridGeometry, year: Int
    ) -> [Int: PriorValue] {
        var sums: [Int: (sum: Double, best: FieldObservation?, bestImpact: Double, distance: Double)] = [:]
        for obs in observations where obs.applies(to: speciesId) {
            let w = weight(of: obs, year: year)
            guard w != 0 else { continue }
            for index in geometry.indices(within: radiusM, of: obs.coordinate) {
                let d = geometry.center(of: index).distanceMeters(to: obs.coordinate)
                let contribution = w * kernel(d)
                var entry = sums[index] ?? (0, nil, 0, 0)
                entry.sum += contribution
                if abs(contribution) > entry.bestImpact {
                    entry.best = obs
                    entry.bestImpact = abs(contribution)
                    entry.distance = d
                }
                sums[index] = entry
            }
        }
        return sums.mapValues { PriorValue(factor: clamp(exp($0.sum)), strongest: $0.best, distanceM: $0.distance) }
    }

    func weight(of obs: FieldObservation, year: Int) -> Double {
        let decay = parameters.decay(years: year - obs.day.year)
        switch obs.kind {
        case .found:
            return parameters.weight(forAmount: obs.amount) * decay
        case .empty:
            guard let score = obs.scoreAtTime, score >= parameters.negativeMinScore else { return 0 }
            return parameters.emptyWeight * decay
        case .rating, .terrainFix:
            return 0
        }
    }

    func kernel(_ distance: Double) -> Double {
        exp(-(distance * distance) / (2 * parameters.sigmaM * parameters.sigmaM))
    }

    private func clamp(_ value: Double) -> Double {
        value.clamped(parameters.minFactor, parameters.maxFactor)
    }
}
