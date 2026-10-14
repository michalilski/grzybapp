import Foundation
import GrzybEngine
import GrzybStore
import Observation

/// What the map shows: scoring session of the active region, overlay image and selected cell.
@MainActor
@Observable
final class MapModel {
    private let services: AppServices
    private let preferences: Preferences
    private(set) var session: ScoringSession?
    private(set) var overlay: ScoreOverlay?
    private(set) var isBuilding = false
    private(set) var flushes: [FlushForecast] = []
    private(set) var maxScore: Float = 0
    var selectedCell: Int?
    var onSessionBuilt: () -> Void = {}
    private var buildGeneration = 0

    init(services: AppServices, preferences: Preferences) {
        self.services = services
        self.preferences = preferences
    }

    var today: DayStamp { DayStamp.today() }
    var selectedDay: DayStamp { today.adding(preferences.dayOffset) }

    func speciesIds(enabled: [SpeciesProfile]) -> [String] {
        let filter = preferences.speciesFilter
        if filter != Preferences.allSpecies, enabled.contains(where: { $0.id == filter }) { return [filter] }
        return enabled.filter(\.edible).map(\.id)
    }

    /// Rebuilds the session from storage in the background, then redraws the overlay.
    func rebuild(region: Region?, species: [SpeciesProfile], observations: [FieldObservation], enabled: [SpeciesProfile]) {
        buildGeneration += 1
        let generation = buildGeneration
        guard let region, region.isDownloaded else {
            session = nil
            overlay = nil
            return
        }
        isBuilding = true
        let knowledge = services.knowledge
        let regions = services.regions
        let weather = services.weather
        let year = today.year
        Task {
            let built = await Task.detached(priority: .userInitiated) { () -> ScoringSession? in
                guard let cells = try? regions.cells(regionId: region.id),
                      let series = try? weather.series(regionId: region.id) else { return nil }
                return ScoringSession(
                    knowledge: knowledge, species: species, geometry: region.geometry, cells: cells,
                    weather: series, observations: observations, year: year
                )
            }.value
            guard generation == buildGeneration else { return }
            session = built
            isBuilding = false
            flushes = built?.flushForecasts(today: today, speciesIds: enabled.map(\.id)) ?? []
            redraw(enabled: enabled)
            onSessionBuilt()
        }
    }

    func redraw(enabled: [SpeciesProfile]) {
        guard let session else {
            overlay = nil
            return
        }
        let ids = speciesIds(enabled: enabled)
        let day = selectedDay
        let bands = services.knowledge.parameters.bands
        let fieldMode = preferences.fieldMode
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (ScoreOverlay?, Float) in
                let layer = session.layer(on: day, speciesIds: ids)
                return (ScoreRenderer.render(layer, bands: bands, fieldMode: fieldMode), layer.values.max() ?? 0)
            }.value
            overlay = result.0
            maxScore = result.1
        }
    }

    func cellIndex(at coordinate: Coordinate) -> Int? {
        session?.cell(containing: coordinate)?.cellIndex
    }
}
