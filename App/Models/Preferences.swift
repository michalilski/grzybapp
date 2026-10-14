import Foundation
import GrzybEngine
import GrzybStore
import Observation

/// User preferences persisted in the `settings` table; the map remembers species, zoom and day.
@MainActor
@Observable
final class Preferences {
    static let allSpecies = "all"
    static let general = "general"

    private let store: SettingsRepository

    var onboardingDone: Bool { didSet { store.setBool("onboarding_done", onboardingDone) } }
    var fieldMode: Bool { didSet { store.setBool("field_mode", fieldMode) } }
    var notificationsEnabled: Bool { didSet { store.setBool("notifications", notificationsEnabled) } }
    var activeRegionId: String? { didSet { store.set("active_region", activeRegionId) } }
    var speciesFilter: String { didSet { store.set("species_filter", speciesFilter) } }
    var dayOffset: Int { didSet { store.set("day_offset", String(dayOffset)) } }
    var disabledSpecies: Set<String> { didSet { store.set("disabled_species", disabledSpecies.sorted().joined(separator: ",")) } }
    var lastFlushNotice: String? { didSet { store.set("last_flush_notice", lastFlushNotice) } }

    init(store: SettingsRepository) {
        self.store = store
        onboardingDone = store.bool("onboarding_done")
        fieldMode = store.bool("field_mode")
        notificationsEnabled = store.bool("notifications")
        activeRegionId = store.string("active_region")
        speciesFilter = store.string("species_filter") ?? Self.general
        dayOffset = Int(store.string("day_offset") ?? "0") ?? 0
        disabledSpecies = Set((store.string("disabled_species") ?? "").split(separator: ",").map(String.init))
        lastFlushNotice = store.string("last_flush_notice")
        if store.string("general_default_v1") == nil {
            speciesFilter = Self.general
            store.set("general_default_v1", "1")
        }
    }

    var camera: (center: Coordinate, zoom: Double)? {
        guard let lat = store.double("camera_lat"), let lon = store.double("camera_lon"), let zoom = store.double("camera_zoom") else {
            return nil
        }
        return (Coordinate(lon: lon, lat: lat), zoom)
    }

    func saveCamera(center: Coordinate, zoom: Double) {
        store.set("camera_lat", String(center.lat))
        store.set("camera_lon", String(center.lon))
        store.set("camera_zoom", String(zoom))
    }
}
