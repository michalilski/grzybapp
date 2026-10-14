import Foundation
import GrzybData
import GrzybEngine
import GrzybStore

enum DownloadStage: Equatable {
    case forest(Double)
    case grid
    case weather
    case tiles(Double)
    case done
    case failed(String)

    var label: String {
        switch self {
        case .forest(let f): "Dane lasu \(Int(f * 100)) %"
        case .grid: "Liczenie siatki"
        case .weather: "Pogoda"
        case .tiles(let f): "Mapa offline \(Int(f * 100)) %"
        case .done: "Gotowe"
        case .failed(let message): message
        }
    }

    var fraction: Double? {
        switch self {
        case .forest(let f): f * 0.7
        case .grid: 0.75
        case .weather: 0.85
        case .tiles(let f): 0.9 + f * 0.1
        case .done: 1
        case .failed: nil
        }
    }

    var isActive: Bool {
        switch self {
        case .done, .failed: false
        default: true
        }
    }
}

/// Downloads BDL layers, builds the static grid, fetches weather and starts the offline tile pack.
@MainActor
final class RegionDownloader {
    private let knowledge: KnowledgeBase
    private let regions: RegionRepository
    private let files: AppFiles
    private let weather: WeatherService
    private let tiles: OfflineTilesService
    private let fetcher = RegionFetcher()

    init(knowledge: KnowledgeBase, regions: RegionRepository, files: AppFiles, weather: WeatherService, tiles: OfflineTilesService) {
        self.knowledge = knowledge
        self.regions = regions
        self.files = files
        self.weather = weather
        self.tiles = tiles
    }

    func download(_ region: Region, progress: @escaping @MainActor (DownloadStage) -> Void) async throws {
        progress(.forest(0))
        let forest = try await fetcher.fetch(bbox: region.bbox) { p in
            Task { @MainActor in progress(.forest(p.fraction)) }
        }
        progress(.grid)
        try await buildAndStore(region: region, forest: forest)
        progress(.weather)
        try? await weather.refresh(region)
        var updated = try regions.find(region.id) ?? region
        updated.bdlFetchedAt = Date()
        updated.bdlYearMin = forest.dataYears?.lowerBound
        updated.bdlYearMax = forest.dataYears?.upperBound
        updated.sizeBytes = files.directorySize(files.regionDirectory(region.id)) + estimatedDatabaseBytes(forest)
        try regions.save(updated)
        progress(.tiles(0))
        tiles.download(regionId: region.id, bbox: region.bbox) { fraction in
            progress(fraction >= 1 ? .done : .tiles(fraction))
        }
    }

    func delete(_ region: Region) throws {
        tiles.remove(regionId: region.id)
        try? FileManager.default.removeItem(at: files.regionDirectory(region.id))
        try regions.delete(region.id)
    }

    private func buildAndStore(region: Region, forest: RegionForestData) async throws {
        let builder = GridBuilder(sites: knowledge.sites)
        let geometry = region.geometry
        let repository = regions
        let outlinesURL = files.outlinesURL(region.id)
        try await Task.detached(priority: .userInitiated) {
            let cells = builder.build(geometry: geometry, stands: forest.stands, siteRecords: forest.sites)
            try repository.replaceForest(regionId: region.id, stands: forest.stands, sites: forest.sites, cells: cells)
            try FileManager.default.createDirectory(at: outlinesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try OutlineWriter.geoJSON(stands: forest.stands).write(to: outlinesURL)
        }.value
    }

    private func estimatedDatabaseBytes(_ forest: RegionForestData) -> Int {
        (forest.stands.count + forest.sites.count) * 200
    }

    static func estimatedMegabytes(for bbox: BoundingBox) -> Double {
        let km2 = bbox.widthMeters * bbox.heightMeters / 1_000_000
        return km2 * 0.12 + OfflineTilesService.estimatedTileCount(bbox) * 0.03
    }
}

/// Fetches Open-Meteo for a region centroid and stores daily aggregates.
@MainActor
final class WeatherService {
    private let client: OpenMeteoClient
    private let repository: WeatherRepository
    private let regions: RegionRepository
    static let refreshInterval: TimeInterval = 6 * 3600
    static let staleInterval: TimeInterval = 36 * 3600

    init(client: OpenMeteoClient, repository: WeatherRepository, regions: RegionRepository) {
        self.client = client
        self.repository = repository
        self.regions = regions
    }

    func refresh(_ region: Region) async throws {
        let days = try await client.fetch(at: region.bbox.center)
        try repository.save(days, regionId: region.id)
        var updated = try regions.find(region.id) ?? region
        updated.weatherFetchedAt = Date()
        try regions.save(updated)
    }

    func needsRefresh(_ region: Region, now: Date = Date()) -> Bool {
        guard region.isDownloaded else { return false }
        guard let fetched = region.weatherFetchedAt else { return true }
        return now.timeIntervalSince(fetched) > Self.refreshInterval
    }

    static func isStale(_ region: Region?, now: Date = Date()) -> Bool {
        guard let fetched = region?.weatherFetchedAt else { return true }
        return now.timeIntervalSince(fetched) > staleInterval
    }
}
