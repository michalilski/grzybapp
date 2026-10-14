import Foundation

/// Rule-based potential index: S = 100 · H · A · T · P · F · W_rain · W_temp · W_frost · R · U.
public struct Scorer: Sendable {
    public let knowledge: KnowledgeBase
    private let weatherIndex: WeatherIndex

    public init(knowledge: KnowledgeBase) {
        self.knowledge = knowledge
        weatherIndex = WeatherIndex(parameters: knowledge.parameters.scoring)
    }

    private var p: EngineParameters.Scoring { knowledge.parameters.scoring }

    public func score(staticFactors: StaticFactors, dynamic: DynamicFactors, user: Double) -> Double {
        (100 * staticFactors.product * dynamic.product(droughtRelief: staticFactors.droughtRelief) * user).clamped(0, 100)
    }

    public func dynamicFactors(for species: SpeciesProfile, on day: DayStamp, weather: WeatherSeries) -> DynamicFactors {
        DynamicFactors(
            season: seasonFactor(species, doy: day.dayOfYear),
            weather: weatherIndex.factors(for: species, on: day, weather: weather)
        )
    }

    public func staticFactors(for raw: CellFeatures, species: SpeciesProfile) -> StaticFactors {
        let cell = raw.effective
        let site = siteFactor(cell, species)
        return StaticFactors(
            host: hostFactor(cell, species),
            age: ageFactor(cell, species),
            site: site.value,
            sitePenalty: sitePenalty(cell, species),
            terrain: terrainFactor(cell, species),
            hostInferred: species.ecology == .mycorrhizal && cell.dominantSpecies == nil,
            siteSource: site.source,
            droughtRelief: droughtRelief(cell)
        )
    }

    func droughtRelief(_ cell: CellFeatures) -> Double {
        guard let moisture = knowledge.sites.moistureClass(of: cell.siteType) else { return 0 }
        return p.droughtRelief[moisture.rawValue] ?? 0
    }

    func seasonFactor(_ species: SpeciesProfile, doy: Int) -> Double {
        max(p.seasonFloor, species.season.trapezoid.value(at: Double(doy)))
    }

    func hostFactor(_ cell: CellFeatures, _ species: SpeciesProfile) -> Double {
        guard species.ecology == .mycorrhizal else { return 1 }
        let admixture = mean(cell.admixture.map { species.hosts[$0] ?? 0 })
        guard let dominant = cell.dominantSpecies else { return admixture * p.uncertaintyWeight }
        let share = cell.dominantShare.clamped(0, 1)
        return share * (species.hosts[dominant] ?? 0) + (1 - share) * admixture
    }

    func ageFactor(_ cell: CellFeatures, _ species: SpeciesProfile) -> Double {
        guard species.ecology == .mycorrhizal, let curve = species.standAge else { return 1 }
        guard let age = cell.standAge else { return p.unknownAgeFactor }
        return curve.value(at: Double(age))
    }

    func siteFactor(_ cell: CellFeatures, _ species: SpeciesProfile) -> (value: Double, source: StaticFactors.SiteSource) {
        if let code = cell.siteType {
            return (species.tsl[code] ?? 0, .data)
        }
        let fallback = knowledge.sites.fallbackSiteTypes(forGeology: cell.geology)
        guard !fallback.isEmpty else { return (p.missingSiteTsl, .missing) }
        return (mean(fallback.map { species.tsl[$0] ?? 0 }) * p.uncertaintyWeight, .geology)
    }

    func sitePenalty(_ cell: CellFeatures, _ species: SpeciesProfile) -> Double {
        var factor = cell.arableFormerly ? 1 - species.arableFormerlyPenalty : 1
        if let moisture = knowledge.sites.moistureClass(of: cell.siteType),
           !species.moisturePref.isEmpty, !species.moisturePref.contains(moisture) {
            factor *= p.moistureMismatch
        }
        if cell.degraded { factor *= p.degradedFactor }
        return factor
    }

    func terrainFactor(_ cell: CellFeatures, _ species: SpeciesProfile) -> Double {
        let nearEdge = cell.distEdgeM < p.edgeDistanceM
        var factor = nearEdge ? 1 + species.terrain.edgeBonus : species.terrain.interiorFactor
        if let structure = cell.standStructure, let bonus = species.structBonus[structure] {
            factor *= bonus
        }
        return factor.clamped(p.terrainMin, p.terrainMax)
    }

    private func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
