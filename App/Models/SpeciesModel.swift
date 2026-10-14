import Foundation
import GrzybEngine
import GrzybStore
import Observation

/// Effective species rules (atlas + overrides), filter toggles and the calibration log.
@MainActor
@Observable
final class SpeciesModel {
    private let knowledge: KnowledgeBase
    private let rules: SpeciesRuleRepository
    private let preferences: Preferences
    private(set) var profiles: [SpeciesProfile] = []
    private(set) var overrides: [ParameterOverride] = []
    private(set) var log: [CalibrationEntry] = []
    var onRulesChanged: () -> Void = {}

    init(knowledge: KnowledgeBase, rules: SpeciesRuleRepository, preferences: Preferences) {
        self.knowledge = knowledge
        self.rules = rules
        self.preferences = preferences
        reload()
    }

    var enabled: [SpeciesProfile] {
        profiles.filter { !preferences.disabledSpecies.contains($0.id) }
    }

    func profile(_ id: String?) -> SpeciesProfile? {
        profiles.first { $0.id == id }
    }

    func atlas(_ id: String) -> SpeciesProfile? {
        knowledge.atlasSpecies.first { $0.id == id }
    }

    func name(_ id: String?) -> String {
        profile(id)?.namePl ?? "Nic"
    }

    func isEnabled(_ id: String) -> Bool {
        !preferences.disabledSpecies.contains(id)
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled { preferences.disabledSpecies.remove(id) } else { preferences.disabledSpecies.insert(id) }
        if !enabled, preferences.speciesFilter == id { preferences.speciesFilter = Preferences.allSpecies }
        onRulesChanged()
    }

    func entries(for id: String) -> [CalibrationEntry] {
        log.filter { $0.speciesId == id }
    }

    func hasOverrides(_ id: String) -> Bool {
        overrides.contains { $0.speciesId == id }
    }

    func setParameter(_ id: String, path: ParameterPath, value: [Double]) {
        let override = ParameterOverride(speciesId: id, path: path.description, value: value, source: .user, changedAt: Date())
        try? rules.save(override)
        reloadAndNotify()
    }

    func restoreAtlas(_ id: String) {
        try? rules.removeOverrides(speciesId: id)
        reloadAndNotify()
    }

    func revert(_ entry: CalibrationEntry) {
        try? rules.revert(entry)
        reloadAndNotify()
    }

    func apply(_ change: CalibrationChange) {
        try? rules.apply(change)
        reloadAndNotify()
    }

    func reload() {
        overrides = (try? rules.overrides()) ?? []
        log = (try? rules.log()) ?? []
        profiles = knowledge.species(applying: overrides)
    }

    private func reloadAndNotify() {
        reload()
        onRulesChanged()
    }
}
