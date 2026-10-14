import Foundation
import GrzybEngine
import GrzybStore
import Observation

/// Draft of a new observation, prefilled from the map or a cell sheet.
struct ObservationDraft: Identifiable {
    let id = UUID()
    var coordinate: Coordinate?
    var speciesId: String?
    var kind: ObservationKind = .found
    var editing: FieldObservation?
}

/// Root state: wires child models together and owns cross-cutting flows (observations, calibration, alerts).
@MainActor
@Observable
final class AppModel {
    let services: AppServices
    let preferences: Preferences
    let regions: RegionsModel
    let species: SpeciesModel
    let journal: JournalModel
    let map: MapModel
    var toast: String?
    var draft: ObservationDraft?
    var navigationTarget: Coordinate?

    init(services: AppServices) {
        self.services = services
        preferences = Preferences(store: services.settings)
        regions = RegionsModel(repository: services.regions, downloader: services.downloader, weather: services.weatherService, preferences: preferences)
        species = SpeciesModel(knowledge: services.knowledge, rules: services.rules, preferences: preferences)
        journal = JournalModel(repository: services.observations, exporter: services.exporter, files: services.files)
        map = MapModel(services: services, preferences: preferences)
        regions.onDataChanged = { [weak self] _ in self?.rebuildSession() }
        species.onRulesChanged = { [weak self] in self?.rebuildSession() }
        journal.onObservationsChanged = { [weak self] obs in self?.observationsChanged(obs) }
        map.onSessionBuilt = { [weak self] in self?.notifyFlushIfNeeded() }
    }

    func start() {
        services.location.start()
        #if DEBUG
        seedDemoRegionIfRequested()
        #endif
        rebuildSession()
        Task { await refreshWeather() }
    }

    func refreshWeather(force: Bool = false) async {
        await regions.refreshWeather(force: force)
    }

    func rebuildSession() {
        map.rebuild(region: regions.active, species: species.profiles, observations: journal.observations, enabled: species.enabled)
    }

    func redraw() {
        map.redraw(enabled: species.enabled)
    }

    func select(filter: String) {
        preferences.speciesFilter = filter
        redraw()
    }

    func select(dayOffset: Int) {
        preferences.dayOffset = dayOffset
        redraw()
    }

    // MARK: Observations

    func startObservation(at coordinate: Coordinate?, speciesId: String? = nil, kind: ObservationKind = .found) {
        let filter = map.speciesIds(enabled: species.enabled).count > 1 ? nil : preferences.speciesFilter
        draft = ObservationDraft(coordinate: coordinate ?? services.location.coordinate, speciesId: speciesId ?? filter, kind: kind)
    }

    func edit(_ observation: FieldObservation) {
        draft = ObservationDraft(coordinate: observation.coordinate, speciesId: observation.speciesId, kind: observation.kind, editing: observation)
    }

    /// Stores the observation together with the model's view of that place at that moment.
    func record(_ observation: FieldObservation) {
        var obs = observation
        if obs.factors == nil, let session = map.session, let cell = session.cell(containing: obs.coordinate),
           let snapshot = session.snapshot(cell: cell, speciesId: obs.speciesId, day: obs.day) {
            obs.regionId = regions.active?.id
            obs.cellIndex = cell.cellIndex
            obs.scoreAtTime = snapshot.scoreWithoutPrior
            obs.factors = snapshot.factors
            obs.context = snapshot.context
        }
        journal.save(obs)
    }

    func rate(cellIndex: Int, positive: Bool) {
        guard let cell = map.session?.cell(at: cellIndex) else { return }
        let ids = map.speciesIds(enabled: species.enabled)
        let ranked = map.session?.ranking(at: cellIndex, on: DayStamp.today(), speciesIds: ids) ?? []
        let target = ids.count > 1 ? ranked.first?.species.id : preferences.speciesFilter
        let obs = FieldObservation(
            speciesId: target, kind: positive ? .found : .empty, amount: 1, lon: cell.lon, lat: cell.lat, note: "Ocena podpowiedzi"
        )
        record(obs)
        toast = positive ? "Zapisano: było warto" : "Zapisano: było pusto"
    }

    func applyTerrainFix(_ fix: TerrainOverride?, cellIndex: Int) {
        guard let region = regions.active, let cell = map.session?.cell(at: cellIndex) else { return }
        try? services.regions.setOverride(regionId: region.id, cellIndex: cellIndex, override: fix)
        let obs = FieldObservation(
            regionId: region.id, speciesId: nil, kind: .terrainFix, lon: cell.lon, lat: cell.lat,
            cellIndex: cellIndex, terrainFix: fix
        )
        journal.save(obs)
        toast = fix.map { "Korekta terenu: \(services.knowledge.codes.terrainOverrides[$0.rawValue] ?? $0.rawValue)" } ?? "Usunięto korektę terenu"
    }

    private func observationsChanged(_ observation: FieldObservation?) {
        rebuildSession()
        guard let speciesId = observation?.speciesId else { return }
        let every = services.knowledge.parameters.calibration.everyObservations
        if journal.count(speciesId: speciesId) % every == 0 { calibrate(speciesId: speciesId) }
    }

    @discardableResult
    func calibrate(speciesId: String) -> CalibrationChange? {
        guard let profile = species.profile(speciesId) else { return nil }
        let calibrator = Calibrator(knowledge: services.knowledge)
        guard let change = calibrator.calibrate(species: profile, observations: journal.observations, on: .today()) else { return nil }
        species.apply(change)
        toast = change.reason
        return change
    }

    func calibrateAll() -> Int {
        species.profiles.compactMap { calibrate(speciesId: $0.id) }.count
    }

    #if DEBUG
    private func seedDemoRegionIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-demoRegion") else { return }
        preferences.onboardingDone = true
        if let tab = ProcessInfo.processInfo.environment["DEMO_FILTER"] { preferences.speciesFilter = tab }
        guard regions.regions.isEmpty else { return }
        let bbox = BoundingBox(minLon: 21.33, minLat: 52.02, maxLon: 21.40, maxLat: 52.065)
        regions.add(name: "Celestynów", bbox: bbox, cellSizeM: services.knowledge.parameters.grid.cellSizeM)
    }
    #endif

    // MARK: Notifications

    private func notifyFlushIfNeeded() {
        let today = DayStamp.today().iso
        guard preferences.notificationsEnabled, preferences.lastFlushNotice != today,
              let flush = map.flushes.first, let region = regions.active else { return }
        let from = max(0, flush.from - DayStamp.today())
        let to = max(from, flush.to - DayStamp.today())
        let body = services.knowledge.templates.render("flush_body", [
            "from": String(from), "to": String(to), "species": species.name(flush.speciesId).lowercased(), "region": region.name,
        ])
        services.notifications.notify(title: services.knowledge.templates.render("flush_title"), body: body)
        preferences.lastFlushNotice = today
    }
}
