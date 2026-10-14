import Foundation

public struct Reason: Codable, Equatable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case positive, negative, info, prior
    }

    public var kind: Kind
    public var factor: String
    public var value: Double
    public var text: String
}

/// Everything needed to explain one species score in one cell.
public struct ExplainInput: Sendable {
    public var cell: CellFeatures
    public var species: SpeciesProfile
    public var staticFactors: StaticFactors
    public var dynamic: DynamicFactors
    public var prior: PriorValue?
    public var day: DayStamp

    public init(
        cell: CellFeatures, species: SpeciesProfile, staticFactors: StaticFactors,
        dynamic: DynamicFactors, prior: PriorValue?, day: DayStamp
    ) {
        self.cell = cell
        self.species = species
        self.staticFactors = staticFactors
        self.dynamic = dynamic
        self.prior = prior
        self.day = day
    }
}

/// Turns factor values into Polish sentences, negatives sorted by impact.
public struct Explainer: Sendable {
    public let knowledge: KnowledgeBase
    private let goodThreshold = 0.8

    public init(knowledge: KnowledgeBase) {
        self.knowledge = knowledge
    }

    public func explain(_ input: ExplainInput) -> [Reason] {
        let candidates = hostReasons(input) + siteReasons(input) + seasonReasons(input)
            + weatherReasons(input) + terrainReasons(input)
        let positives = candidates.filter { $0.kind == .positive }
        let negatives = candidates.filter { $0.kind == .negative }.sorted { $0.value < $1.value }
        return positives + negatives + infoReasons(input) + priorReasons(input)
    }

    private func text(_ key: String, _ input: ExplainInput, _ values: [String: String]) -> String {
        knowledge.templates.render(key, values, overrides: input.species.explain)
    }

    private func reason(_ factor: String, _ value: Double, _ text: String, positive: Bool? = nil) -> Reason {
        let isPositive = positive ?? (value >= goodThreshold)
        return Reason(kind: isPositive ? .positive : .negative, factor: factor, value: value, text: text)
    }

    private func fmt(_ value: Double) -> String {
        PolishNumber.format(value, decimals: 2)
    }

    private func hostReasons(_ input: ExplainInput) -> [Reason] {
        let s = input.staticFactors
        let cell = input.cell.effective
        if input.species.ecology == .saprotroph {
            return [reason("H", 1, text("saprotroph", input, [:]), positive: true)]
        }
        if s.hostInferred {
            return [reason("H", s.host, text("host_inferred", input, ["value": fmt(s.host)]), positive: false)]
        }
        let ageText = cell.standAge.map { ", \($0) lat" } ?? ""
        let values = [
            "tree": knowledge.codes.treeName(cell.dominantSpecies),
            "age": ageText,
            "share": PolishNumber.integer(cell.dominantShare * 100),
            "value": fmt(s.host),
        ]
        var reasons = [reason("H", s.host, text(s.host >= goodThreshold ? "host_good" : "host_weak", input, values))]
        if input.species.standAge != nil {
            let ageValues = ["age": cell.standAge.map(String.init) ?? "?", "value": fmt(s.age)]
            let key = cell.standAge == nil ? "age_unknown" : (s.age >= goodThreshold ? "age_good" : "age_bad")
            reasons.append(reason("A", s.age, text(key, input, ageValues)))
        }
        return reasons
    }

    private func siteReasons(_ input: ExplainInput) -> [Reason] {
        let s = input.staticFactors
        let cell = input.cell.effective
        var reasons: [Reason] = []
        switch s.siteSource {
        case .data:
            let key = s.site >= goodThreshold ? "site_good" : "site_bad"
            reasons.append(reason("T", s.site, text(key, input, ["site": knowledge.codes.siteName(cell.siteType), "value": fmt(s.site)])))
        case .geology:
            reasons.append(reason("T", s.site, text("site_fallback", input, ["geology": cell.geology ?? "?", "value": fmt(s.site)]), positive: false))
        case .missing:
            reasons.append(reason("T", s.site, text("site_missing", input, ["value": fmt(s.site)]), positive: false))
        }
        if cell.arableFormerly, input.species.arableFormerlyPenalty > 0 {
            let pct = PolishNumber.integer(input.species.arableFormerlyPenalty * 100)
            reasons.append(reason("P", 1 - input.species.arableFormerlyPenalty, text("arable", input, ["pct": pct]), positive: false))
        }
        if let moisture = knowledge.sites.moistureClass(of: cell.siteType),
           !input.species.moisturePref.isEmpty, !input.species.moisturePref.contains(moisture) {
            let name = knowledge.codes.moisture[moisture.rawValue] ?? moisture.rawValue
            reasons.append(reason("P", knowledge.parameters.scoring.moistureMismatch, text("moisture_mismatch", input, ["moisture": name]), positive: false))
        }
        if cell.degraded {
            reasons.append(reason("P", knowledge.parameters.scoring.degradedFactor, text("degraded", input, [:]), positive: false))
        }
        return reasons
    }

    private func seasonReasons(_ input: ExplainInput) -> [Reason] {
        let f = input.dynamic.season
        let doy = input.day.dayOfYear
        let values = ["value": fmt(f)]
        if input.species.season.isPeak(doy) { return [reason("F", f, text("season_peak", input, values), positive: true)] }
        if input.species.season.contains(doy) { return [reason("F", f, text("season_in", input, values))] }
        return [reason("F", f, text("season_out", input, values), positive: false)]
    }

    private func weatherReasons(_ input: ExplainInput) -> [Reason] {
        let w = input.dynamic.weather
        guard w.available else {
            return [reason("W", w.rain, text("no_weather", input, [:]), positive: false)]
        }
        let needs = input.species.weather
        let rainValues = [
            "rain": PolishNumber.integer(w.rainMm), "from": String(needs.windowNear),
            "to": String(needs.windowFar), "value": fmt(w.rain),
        ]
        let rainOnly = w.rainBase > w.soilWater || w.soilMoisture == nil
        var reasons = [reason("W_rain", w.rainBase, text(rainOnly && w.rainBase >= goodThreshold ? "rain_good" : "rain_low", input, rainValues), positive: rainOnly ? nil : false)]
        if !rainOnly, let moisture = w.soilMoisture {
            reasons.append(reason("W_soil", w.soilWater, text("soil_moisture", input, ["moisture": PolishNumber.format(moisture, decimals: 2)]), positive: true))
        }
        let relief = input.staticFactors.droughtRelief
        if relief > 0, w.rain < 1 {
            let values = ["from": fmt(w.rain), "to": fmt(input.dynamic.water(droughtRelief: relief))]
            reasons.append(reason("W_relief", relief, text("drought_relief", input, values), positive: true))
        }
        if w.dryPenalty > 0 {
            let values = ["days": String(w.dryDays), "window": String(needs.dryWindowDays), "penalty": fmt(w.dryPenalty)]
            reasons.append(reason("W_dry", 1 - w.dryPenalty, text("dry_days", input, values), positive: false))
        }
        if let soil = w.soilTempC {
            let key = w.temp >= goodThreshold ? "soil_good" : "soil_bad"
            reasons.append(reason("W_temp", w.temp, text(key, input, ["temp": PolishNumber.format(soil), "value": fmt(w.temp)])))
        }
        if w.coldNightsShort, let rule = needs.coldNights {
            let values = ["temp": PolishNumber.integer(rule.maxTminC), "count": String(w.coldNights ?? 0), "need": String(rule.minCount)]
            reasons.append(reason("W_temp", rule.elseFactor, text("cold_nights_missing", input, values), positive: false))
        }
        if let ago = w.frostDaysAgo {
            reasons.append(reason("W_frost", w.frost, text("frost", input, ["days": String(ago), "value": fmt(w.frost)]), positive: false))
        }
        return reasons
    }

    private func terrainReasons(_ input: ExplainInput) -> [Reason] {
        let r = input.staticFactors.terrain
        let cell = input.cell.effective
        var reasons: [Reason] = []
        if cell.distEdgeM < knowledge.parameters.scoring.edgeDistanceM, input.species.terrain.edgeBonus > 0 {
            reasons.append(reason("R", r, text("edge", input, ["dist": PolishNumber.integer(cell.distEdgeM), "value": fmt(r)]), positive: true))
        } else if input.species.terrain.interiorFactor < 1 {
            reasons.append(reason("R", r, text("interior", input, ["value": fmt(r)]), positive: false))
        }
        if let structure = cell.standStructure, input.species.structBonus[structure] != nil {
            let name = knowledge.codes.standStructure[structure] ?? structure
            reasons.append(reason("R", r, text("struct_bonus", input, ["structure": name, "value": fmt(r)]), positive: true))
        }
        return reasons
    }

    private func infoReasons(_ input: ExplainInput) -> [Reason] {
        var reasons: [Reason] = []
        if input.dynamic.weather.usesForecast {
            let factor = PolishNumber.format(knowledge.parameters.scoring.forecastRainFactor)
            reasons.append(Reason(kind: .info, factor: "forecast", value: 0, text: text("forecast_used", input, ["factor": factor])))
        }
        if let year = input.cell.standYear, input.day.year - year >= 3 {
            reasons.append(Reason(kind: .info, factor: "data_year", value: Double(year), text: text("data_year", input, ["year": String(year)])))
        }
        if let fix = input.cell.override {
            let name = knowledge.codes.terrainOverrides[fix.rawValue] ?? fix.rawValue
            reasons.append(Reason(kind: .info, factor: "override", value: 0, text: text("override", input, ["override": name])))
        }
        return reasons
    }

    private func priorReasons(_ input: ExplainInput) -> [Reason] {
        guard let prior = input.prior, let obs = prior.strongest, abs(prior.factor - 1) > 0.01 else { return [] }
        let values = [
            "dist": PolishNumber.integer(prior.distanceM ?? 0),
            "date": obs.day.shortPolish,
            "value": PolishNumber.format(prior.factor),
        ]
        let key = prior.factor >= 1 ? "prior_positive" : "prior_negative"
        return [Reason(kind: .prior, factor: "U", value: prior.factor, text: text(key, input, values))]
    }
}
