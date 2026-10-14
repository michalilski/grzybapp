import Foundation
import GrzybEngine

/// Forest data of a whole region, deduplicated across download tiles.
public struct RegionForestData: Sendable {
    public var stands: [StandRecord]
    public var sites: [SiteRecord]

    public var dataYears: ClosedRange<Int>? {
        let years = stands.compactMap(\.dataYear) + sites.compactMap(\.dataYear)
        guard let lo = years.min(), let hi = years.max() else { return nil }
        return lo...hi
    }
}

public struct FetchProgress: Sendable {
    public var completed: Int
    public var total: Int

    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}

/// Downloads stands and sites for a region tile by tile, with limited concurrency.
public struct RegionFetcher: Sendable {
    public let client: BDLClient
    public let tileMeters: Double
    public let concurrency: Int

    public init(client: BDLClient = BDLClient(), tileMeters: Double = 5000, concurrency: Int = 4) {
        self.client = client
        self.tileMeters = tileMeters
        self.concurrency = concurrency
    }

    private struct Job: Sendable {
        let layer: BDLClient.Layer
        let bbox: BoundingBox
    }

    private enum JobResult: Sendable {
        case stands([StandRecord])
        case sites([SiteRecord])
    }

    public func fetch(bbox: BoundingBox, progress: @escaping @Sendable (FetchProgress) -> Void) async throws -> RegionForestData {
        let tiles = bbox.tiles(sizeMeters: tileMeters)
        let jobs = tiles.flatMap { tile in
            [Job(layer: .stateStands, bbox: tile), Job(layer: .otherStands, bbox: tile), Job(layer: .sites, bbox: tile)]
        }
        var stands: [String: StandRecord] = [:]
        var sites: [String: SiteRecord] = [:]
        var completed = 0
        progress(FetchProgress(completed: 0, total: jobs.count))
        try await withThrowingTaskGroup(of: JobResult.self) { group in
            var pending = jobs.makeIterator()
            for _ in 0..<concurrency {
                if let job = pending.next() { group.addTask { try await run(job) } }
            }
            while let result = try await group.next() {
                switch result {
                case .stands(let list): list.forEach { stands[$0.id] = stands[$0.id] ?? $0 }
                case .sites(let list): list.forEach { sites[$0.id] = sites[$0.id] ?? $0 }
                }
                completed += 1
                progress(FetchProgress(completed: completed, total: jobs.count))
                if let job = pending.next() { group.addTask { try await run(job) } }
            }
        }
        return RegionForestData(
            stands: stands.values.sorted { $0.id < $1.id },
            sites: sites.values.sorted { $0.id < $1.id }
        )
    }

    private func run(_ job: Job) async throws -> JobResult {
        let features = try await client.fetch(job.layer, bbox: job.bbox)
        switch job.layer {
        case .stateStands: return .stands(features.compactMap { BDLRecordMapper.stand($0, layer: .stateForest) })
        case .otherStands: return .stands(features.compactMap { BDLRecordMapper.stand($0, layer: .otherForest) })
        case .sites: return .sites(features.compactMap(BDLRecordMapper.site))
        }
    }
}

/// Writes stand outlines as a compact GeoJSON FeatureCollection for the map.
public enum OutlineWriter {
    public static func geoJSON(stands: [StandRecord]) throws -> Data {
        let features: [[String: Any]] = stands.map { stand in
            [
                "type": "Feature",
                "properties": ["id": stand.id],
                "geometry": [
                    "type": "MultiPolygon",
                    "coordinates": stand.shape.polygons.map { polygon in
                        polygon.rings.map { ring in ring.map { [round6($0.lon), round6($0.lat)] } }
                    },
                ],
            ]
        }
        return try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": features])
    }

    private static func round6(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}
