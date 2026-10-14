import Foundation
import GrzybEngine
import GrzybStore
import Observation
import UIKit

/// Season summary shown above the journal list.
struct SeasonSummary {
    var finds: Int
    var empties: Int
    var topSpecies: [(id: String, count: Int)]
    var medianDaysAfterRain: Int?
    var findsByDay: [Int: Int]
}

/// User observations: list, edit, export and import.
@MainActor
@Observable
final class JournalModel {
    private let repository: ObservationRepository
    private let exporter: ExportService
    private let files: AppFiles
    private(set) var observations: [FieldObservation] = []
    var onObservationsChanged: (FieldObservation?) -> Void = { _ in }

    init(repository: ObservationRepository, exporter: ExportService, files: AppFiles) {
        self.repository = repository
        self.exporter = exporter
        self.files = files
        reload()
    }

    func reload() {
        observations = (try? repository.all()) ?? []
    }

    func save(_ observation: FieldObservation) {
        try? repository.save(observation)
        reload()
        onObservationsChanged(observation)
    }

    func delete(_ observation: FieldObservation) {
        try? repository.delete(observation.id)
        if let path = observation.photoPath { try? FileManager.default.removeItem(at: files.photoURL(path)) }
        reload()
        onObservationsChanged(nil)
    }

    func count(speciesId: String) -> Int {
        observations.filter { $0.speciesId == speciesId && ($0.kind == .found || $0.kind == .empty) }.count
    }

    func savePhoto(_ image: UIImage, id: String) -> String? {
        let name = "\(id).jpg"
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        try? data.write(to: files.photoURL(name))
        return name
    }

    func photo(_ name: String?) -> UIImage? {
        name.flatMap { UIImage(contentsOfFile: files.photoURL($0).path) }
    }

    func summary(year: Int, speciesId: String?) -> SeasonSummary {
        let inYear = observations.filter { $0.day.year == year && (speciesId == nil || $0.speciesId == speciesId) }
        let finds = inYear.filter { $0.kind == .found }
        let counts = Dictionary(grouping: finds.compactMap(\.speciesId), by: { $0 }).mapValues(\.count)
        let lags = finds.compactMap { $0.context?.daysSinceRainEvent }.sorted()
        return SeasonSummary(
            finds: finds.count,
            empties: inYear.filter { $0.kind == .empty }.count,
            topSpecies: counts.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) },
            medianDaysAfterRain: lags.isEmpty ? nil : lags[lags.count / 2],
            findsByDay: Dictionary(grouping: finds, by: { $0.day.dayOfYear }).mapValues(\.count)
        )
    }

    func exportJSON() throws -> URL {
        let url = try exportURL(name: "grzyby-export-\(DayStamp.today().iso).json")
        try exporter.exportJSON().write(to: url)
        return url
    }

    func exportGPX(names: [String: String]) throws -> URL {
        let url = try exportURL(name: "grzyby-\(DayStamp.today().iso).gpx")
        try exporter.exportGPX(observations: observations, speciesNames: names).write(to: url)
        return url
    }

    func importJSON(from url: URL) throws -> [Region] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let regions = try exporter.importJSON(Data(contentsOf: url))
        reload()
        onObservationsChanged(nil)
        return regions
    }

    private func exportURL(name: String) throws -> URL {
        try FileManager.default.createDirectory(at: files.exportDirectory, withIntermediateDirectories: true)
        return files.exportDirectory.appendingPathComponent(name)
    }
}
