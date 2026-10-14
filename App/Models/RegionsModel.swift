import Foundation
import GrzybEngine
import GrzybStore
import Observation

/// Working regions, their downloads and weather freshness.
@MainActor
@Observable
final class RegionsModel {
    private let repository: RegionRepository
    private let downloader: RegionDownloader
    private let weather: WeatherService
    private let preferences: Preferences
    private(set) var regions: [Region] = []
    private(set) var stages: [String: DownloadStage] = [:]
    private(set) var weatherRefreshing = false
    private(set) var offline = false
    var onDataChanged: (String) -> Void = { _ in }

    init(repository: RegionRepository, downloader: RegionDownloader, weather: WeatherService, preferences: Preferences) {
        self.repository = repository
        self.downloader = downloader
        self.weather = weather
        self.preferences = preferences
        reload()
    }

    var active: Region? {
        regions.first { $0.id == preferences.activeRegionId } ?? regions.first { $0.isDownloaded }
    }

    func reload() {
        regions = (try? repository.all()) ?? []
    }

    func stage(_ id: String) -> DownloadStage? {
        stages[id]
    }

    func activate(_ region: Region) {
        preferences.activeRegionId = region.id
        onDataChanged(region.id)
    }

    func add(name: String, bbox: BoundingBox, cellSizeM: Double) {
        let region = Region(name: name, bbox: bbox, cellSizeM: cellSizeM)
        try? repository.save(region)
        reload()
        preferences.activeRegionId = region.id
        download(region)
    }

    func download(_ region: Region) {
        stages[region.id] = .forest(0)
        Task {
            do {
                try await downloader.download(region) { [weak self] stage in
                    self?.stages[region.id] = stage
                    if stage == .done { self?.reload() }
                }
                reload()
                onDataChanged(region.id)
            } catch {
                stages[region.id] = .failed("Nie udało się pobrać: \(error.localizedDescription)")
            }
        }
    }

    func delete(_ region: Region) {
        try? downloader.delete(region)
        stages[region.id] = nil
        if preferences.activeRegionId == region.id { preferences.activeRegionId = nil }
        reload()
        onDataChanged(region.id)
    }

    func refreshWeather(force: Bool = false) async {
        let targets = regions.filter { force ? $0.isDownloaded : weather.needsRefresh($0) }
        guard !targets.isEmpty, !weatherRefreshing else { return }
        weatherRefreshing = true
        defer { weatherRefreshing = false }
        var failures = 0
        for region in targets {
            do {
                try await weather.refresh(region)
                onDataChanged(region.id)
            } catch {
                failures += 1
            }
        }
        offline = failures == targets.count
        reload()
    }

    func refreshWeather(_ region: Region) async {
        weatherRefreshing = true
        defer { weatherRefreshing = false }
        do {
            try await weather.refresh(region)
            offline = false
        } catch {
            offline = true
        }
        reload()
        onDataChanged(region.id)
    }
}
