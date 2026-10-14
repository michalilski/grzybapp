import Foundation
import GrzybData
import GrzybEngine
import GrzybStore

/// Composition root: database, repositories, clients and knowledge shared by the whole app.
@MainActor
final class AppServices {
    let knowledge: KnowledgeBase
    let database: AppDatabase
    let regions: RegionRepository
    let weather: WeatherRepository
    let observations: ObservationRepository
    let rules: SpeciesRuleRepository
    let settings: SettingsRepository
    let exporter: ExportService
    let files: AppFiles
    let downloader: RegionDownloader
    let weatherService: WeatherService
    let location: LocationService
    let notifications: NotificationService
    let offlineTiles: OfflineTilesService

    init() throws {
        files = AppFiles()
        knowledge = try KnowledgeBase.bundled()
        database = try AppDatabase.open(at: files.databaseURL)
        regions = RegionRepository(database)
        weather = WeatherRepository(database)
        observations = ObservationRepository(database)
        rules = SpeciesRuleRepository(database)
        settings = SettingsRepository(database)
        exporter = ExportService(database)
        weatherService = WeatherService(client: OpenMeteoClient(), repository: weather, regions: regions)
        offlineTiles = OfflineTilesService()
        downloader = RegionDownloader(
            knowledge: knowledge, regions: regions, files: files, weather: weatherService, tiles: offlineTiles
        )
        location = LocationService()
        notifications = NotificationService()
    }
}

/// Locations of files kept outside SQLite: stand outlines, photos, exports.
struct AppFiles: Sendable {
    let root: URL

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Grzyby", isDirectory: true)
        for dir in [root, photosDirectory, exportDirectory, regionsDirectory] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    var databaseURL: URL { root.appendingPathComponent("grzyby.sqlite") }
    var photosDirectory: URL { root.appendingPathComponent("photos", isDirectory: true) }
    var exportDirectory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true) }
    var regionsDirectory: URL { root.appendingPathComponent("regions", isDirectory: true) }

    func regionDirectory(_ id: String) -> URL {
        regionsDirectory.appendingPathComponent(id, isDirectory: true)
    }

    func outlinesURL(_ regionId: String) -> URL {
        regionDirectory(regionId).appendingPathComponent("stands.geojson")
    }

    func photoURL(_ name: String) -> URL {
        photosDirectory.appendingPathComponent(name)
    }

    func directorySize(_ url: URL) -> Int {
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total = 0
        while let file = enumerator?.nextObject() as? URL {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}
