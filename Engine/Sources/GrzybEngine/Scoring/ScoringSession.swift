import Foundation

/// Per-cell potential for the map: value 0–100 or -1 where the cell is not drawn.
public struct ScoreLayer: Sendable {
    public let geometry: GridGeometry
    public let values: [Float]
    public let winners: [Int16]
    public let speciesIds: [String]

    public func value(at index: Int) -> Float {
        values[index]
    }

    public func winner(at index: Int) -> String? {
        let w = Int(winners[index])
        return w >= 0 && w < speciesIds.count ? speciesIds[w] : nil
    }
}

public struct SpeciesScore: Sendable, Identifiable {
    public var species: SpeciesProfile
    public var score: Double
    public var scoreWithoutPrior: Double
    public var band: PotentialBand
    public var staticFactors: StaticFactors
    public var dynamic: DynamicFactors
    public var prior: PriorValue?
    public var reasons: [Reason]

    public var id: String { species.id }
}

/// Snapshot stored with an observation so calibration can replay the model later.
public struct ObservationSnapshot: Sendable {
    public var scoreWithoutPrior: Double
    public var factors: FactorSet
    public var context: ObservationContext
}

/// Scoring engine bound to one region: static factors cached once, weather applied per day.
public final class ScoringSession: @unchecked Sendable {
    public let knowledge: KnowledgeBase
    public let species: [SpeciesProfile]
    public let geometry: GridGeometry
    public let cells: [CellFeatures]
    public let weather: WeatherSeries
    private let scorer: Scorer
    private let explainer: Explainer
    private let lookup: [Int32]
    private let staticCache: [String: [Float]]
    private let priors: [String: [Int: PriorValue]]

    public init(
        knowledge: KnowledgeBase, species: [SpeciesProfile], geometry: GridGeometry, cells: [CellFeatures],
        weather: WeatherSeries, observations: [FieldObservation], year: Int
    ) {
        self.knowledge = knowledge
        self.species = species
        self.geometry = geometry
        self.cells = cells
        self.weather = weather
        scorer = Scorer(knowledge: knowledge)
        explainer = Explainer(knowledge: knowledge)
        var lookup = [Int32](repeating: -1, count: geometry.count)
        for (i, cell) in cells.enumerated() where cell.cellIndex < geometry.count {
            lookup[cell.cellIndex] = Int32(i)
        }
        self.lookup = lookup
        let scorer = self.scorer
        staticCache = Dictionary(uniqueKeysWithValues: species.map { profile in
            (profile.id, cells.map { $0.isExcluded ? 0 : Float(scorer.staticFactors(for: $0, species: profile).product) })
        })
        let prior = LocalPrior(parameters: knowledge.parameters.prior)
        priors = Dictionary(uniqueKeysWithValues: species.map { profile in
            (profile.id, prior.field(speciesId: profile.id, observations: observations, geometry: geometry, year: year))
        })
    }

    public func profile(_ id: String) -> SpeciesProfile? {
        species.first { $0.id == id }
    }

    public func cell(at index: Int) -> CellFeatures? {
        guard index >= 0, index < lookup.count, lookup[index] >= 0 else { return nil }
        return cells[Int(lookup[index])]
    }

    public func cell(containing coordinate: Coordinate) -> CellFeatures? {
        geometry.index(containing: coordinate).flatMap(cell(at:))
    }

    public func dynamicFactors(for profile: SpeciesProfile, on day: DayStamp) -> DynamicFactors {
        scorer.dynamicFactors(for: profile, on: day, weather: weather)
    }

    public func layer(on day: DayStamp, speciesIds: [String]) -> ScoreLayer {
        var values = [Float](repeating: -1, count: geometry.count)
        var winners = [Int16](repeating: -1, count: geometry.count)
        for (s, id) in speciesIds.enumerated() {
            guard let profile = profile(id), let statics = staticCache[id] else { continue }
            let dynamic = Float(dynamicFactors(for: profile, on: day).product)
            let prior = priors[id] ?? [:]
            for (i, cell) in cells.enumerated() where statics[i] > 0 {
                let u = Float(prior[cell.cellIndex]?.factor ?? 1)
                let score = min(100, 100 * statics[i] * dynamic * u)
                if score > values[cell.cellIndex] {
                    values[cell.cellIndex] = score
                    winners[cell.cellIndex] = Int16(s)
                }
            }
        }
        return ScoreLayer(geometry: geometry, values: values, winners: winners, speciesIds: speciesIds)
    }

    public func ranking(at index: Int, on day: DayStamp, speciesIds: [String]? = nil) -> [SpeciesScore] {
        guard let cell = cell(at: index) else { return [] }
        let ids = speciesIds ?? species.map(\.id)
        return ids.compactMap { id in profile(id).map { score(cell: cell, profile: $0, day: day) } }
            .sorted { $0.score > $1.score }
    }

    public func score(cell: CellFeatures, profile: SpeciesProfile, day: DayStamp) -> SpeciesScore {
        let statics = scorer.staticFactors(for: cell, species: profile)
        let dynamic = dynamicFactors(for: profile, on: day)
        let prior = priors[profile.id]?[cell.cellIndex]
        let excluded = cell.isExcluded ? 0.0 : 1.0
        let base = scorer.score(staticFactors: statics, dynamic: dynamic, user: 1) * excluded
        let score = scorer.score(staticFactors: statics, dynamic: dynamic, user: prior?.factor ?? 1) * excluded
        let input = ExplainInput(cell: cell, species: profile, staticFactors: statics, dynamic: dynamic, prior: prior, day: day)
        return SpeciesScore(
            species: profile,
            score: score,
            scoreWithoutPrior: base,
            band: PotentialBand(score: score, bands: knowledge.parameters.bands),
            staticFactors: statics,
            dynamic: dynamic,
            prior: prior,
            reasons: explainer.explain(input)
        )
    }

    public func topCells(speciesId: String, on day: DayStamp, limit: Int) -> [(cell: CellFeatures, score: SpeciesScore)] {
        guard let profile = profile(speciesId) else { return [] }
        let layer = layer(on: day, speciesIds: [speciesId])
        let ranked = cells
            .filter { layer.values[$0.cellIndex] > 0 }
            .sorted { lhs, rhs in
                let a = layer.values[lhs.cellIndex], b = layer.values[rhs.cellIndex]
                return a != b ? a > b : lhs.cellIndex < rhs.cellIndex
            }
        return ranked.prefix(limit).map { ($0, score(cell: $0, profile: profile, day: day)) }
    }

    public func snapshot(cell: CellFeatures, speciesId: String?, day: DayStamp) -> ObservationSnapshot? {
        let candidates = speciesId.flatMap(profile).map { [$0] } ?? species
        let scores = candidates.map { score(cell: cell, profile: $0, day: day) }
        guard let best = scores.max(by: { $0.scoreWithoutPrior < $1.scoreWithoutPrior }) else { return nil }
        let context = ObservationContext(
            siteType: cell.effective.siteType,
            dominantSpecies: cell.dominantSpecies,
            dayOfYear: day.dayOfYear,
            daysSinceRainEvent: daysSinceRainEvent(before: day)
        )
        return ObservationSnapshot(
            scoreWithoutPrior: best.scoreWithoutPrior,
            factors: FactorSet(staticFactors: best.staticFactors, dynamic: best.dynamic, user: best.prior?.factor ?? 1),
            context: context
        )
    }

    public func daysSinceRainEvent(before day: DayStamp) -> Int? {
        let threshold = knowledge.parameters.calibration.rainEventMm
        for ago in 0...60 {
            if let w = weather.day(day.adding(-ago)), w.precipMm >= threshold { return ago }
        }
        return nil
    }

    public func flushForecasts(today: DayStamp, speciesIds: [String]) -> [FlushForecast] {
        let detector = FlushDetector(parameters: knowledge.parameters)
        return speciesIds.compactMap { id in profile(id).flatMap { detector.detect(for: $0, today: today, weather: weather) } }
    }
}
