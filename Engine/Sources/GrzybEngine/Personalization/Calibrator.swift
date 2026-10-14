import Foundation

/// One explicit, reversible rule change proposed by calibration.
public struct CalibrationChange: Codable, Equatable, Sendable {
    public var speciesId: String
    public var parameter: String
    public var oldValue: [Double]
    public var newValue: [Double]
    public var reason: String
    public var observationIds: [String]
}

/// Rule-based calibration: nudges a single parameter when observations consistently disagree with the model.
public struct Calibrator: Sendable {
    public let knowledge: KnowledgeBase

    public init(knowledge: KnowledgeBase) {
        self.knowledge = knowledge
    }

    private var p: EngineParameters.Calibration { knowledge.parameters.calibration }

    public func calibrate(
        species: SpeciesProfile, observations: [FieldObservation], on day: DayStamp
    ) -> CalibrationChange? {
        let relevant = observations.filter { $0.applies(to: species.id) }
        let finds = relevant.filter { $0.kind == .found && $0.factors != nil && $0.context != nil }
        let empties = relevant.filter {
            $0.kind == .empty && ($0.scoreAtTime ?? 0) >= knowledge.parameters.prior.negativeMinScore && $0.context != nil
        }
        return raise(species, finds, day) ?? lower(species, empties, day) ?? widenSeason(species, finds, day)
            ?? shiftLag(species, finds, day)
    }

    private func raise(_ species: SpeciesProfile, _ finds: [FieldObservation], _ day: DayStamp) -> CalibrationChange? {
        let bottlenecks = finds.compactMap { obs in bottleneck(of: obs).map { ($0, obs.id) } }
        guard let (path, ids) = majority(bottlenecks, of: finds.count) else { return nil }
        let current = path.read(from: species).first ?? 0
        guard current > 0, current < p.maxValue else { return nil }
        let new = min(p.maxValue, current + p.step)
        return change(species, path, [current], [new], ids, "calibration_raise", day)
    }

    private func lower(_ species: SpeciesProfile, _ empties: [FieldObservation], _ day: DayStamp) -> CalibrationChange? {
        let keys = empties.flatMap { obs in adjustablePaths(of: obs, species).map { ($0, obs.id) } }
        guard let (path, ids) = majority(keys, of: empties.count) else { return nil }
        let current = path.read(from: species).first ?? 0
        guard current > p.minValue else { return nil }
        let new = max(p.minValue, current - p.step)
        return change(species, path, [current], [new], ids, "calibration_lower", day)
    }

    private func widenSeason(_ species: SpeciesProfile, _ finds: [FieldObservation], _ day: DayStamp) -> CalibrationChange? {
        let doys = finds.compactMap { obs in obs.context.map { ($0.dayOfYear, obs.id) } }
        let early = doys.filter { $0.0 < species.season.startDoy }
        let late = doys.filter { $0.0 > species.season.endDoy }
        if early.count >= p.seasonOutsideCount {
            let old = Double(species.season.startDoy)
            return change(species, .seasonStart, [old], [old - Double(p.seasonStepDays)], early.map(\.1), "calibration_season", day)
        }
        if late.count >= p.seasonOutsideCount {
            let old = Double(species.season.endDoy)
            return change(species, .seasonEnd, [old], [old + Double(p.seasonStepDays)], late.map(\.1), "calibration_season", day)
        }
        return nil
    }

    private func shiftLag(_ species: SpeciesProfile, _ finds: [FieldObservation], _ day: DayStamp) -> CalibrationChange? {
        let samples = finds.compactMap { obs in obs.context?.daysSinceRainEvent.map { (Double($0), obs.id) } }
        guard samples.count >= p.seasonOutsideCount else { return nil }
        let median = samples.map(\.0).sorted()[samples.count / 2]
        let lag = species.weather.lagDays.map(Double.init)
        let center = lag.reduce(0, +) / Double(max(1, lag.count))
        let diff = median - center
        guard abs(diff) > Double(p.lagToleranceDays) else { return nil }
        let shift = diff > 0 ? Double(p.lagStepDays) : -Double(p.lagStepDays)
        let new = lag.map { max(1, $0 + shift) }
        return change(species, .lagDays, lag, new, samples.map(\.1), "calibration_lag", day)
    }

    private func bottleneck(of obs: FieldObservation) -> ParameterPath? {
        guard let factors = obs.factors, let context = obs.context else { return nil }
        var candidates: [(ParameterPath, Double)] = []
        if let site = context.siteType { candidates.append((.tsl(site), factors.site)) }
        if let host = context.dominantSpecies { candidates.append((.host(host), factors.host)) }
        return candidates.filter { $0.1 < 1 }.min { $0.1 < $1.1 }?.0
    }

    private func adjustablePaths(of obs: FieldObservation, _ species: SpeciesProfile) -> [ParameterPath] {
        guard let context = obs.context else { return [] }
        var paths: [ParameterPath] = []
        if let site = context.siteType { paths.append(.tsl(site)) }
        if species.ecology == .mycorrhizal, let host = context.dominantSpecies { paths.append(.host(host)) }
        return paths
    }

    private func majority(_ entries: [(ParameterPath, String)], of total: Int) -> (ParameterPath, [String])? {
        guard total > 0 else { return nil }
        let grouped = Dictionary(grouping: entries, by: \.0)
        let ranked = grouped.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.key.description < b.key.description
        }
        guard let best = ranked.first, Double(best.value.count) >= p.majorityShare * Double(total) else { return nil }
        return (best.key, best.value.map(\.1))
    }

    private func change(
        _ species: SpeciesProfile, _ path: ParameterPath, _ old: [Double], _ new: [Double],
        _ ids: [String], _ templateKey: String, _ day: DayStamp
    ) -> CalibrationChange {
        let values = [
            "date": day.shortPolish,
            "parameter": parameterLabel(path),
            "species": species.namePl,
            "old": format(old),
            "new": format(new),
            "count": String(ids.count),
        ]
        return CalibrationChange(
            speciesId: species.id,
            parameter: path.description,
            oldValue: old,
            newValue: new,
            reason: knowledge.templates.render(templateKey, values),
            observationIds: ids
        )
    }

    public func parameterLabel(_ path: ParameterPath) -> String {
        switch path.group {
        case "tsl": knowledge.templates.render("param_tsl", ["key": path.key])
        case "hosts": knowledge.templates.render("param_hosts", ["key": knowledge.codes.treeName(path.key).lowercased()])
        case "season" where path.key == "start_doy": knowledge.templates.render("param_season_start")
        case "season": knowledge.templates.render("param_season_end")
        default: path.description
        }
    }

    private func format(_ values: [Double]) -> String {
        let isInteger = values.allSatisfy { $0 == $0.rounded() && $0 > 2 }
        return values.map { isInteger ? PolishNumber.integer($0) : PolishNumber.format($0) }.joined(separator: "–")
    }
}
