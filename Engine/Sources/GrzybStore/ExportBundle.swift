import Foundation
import GRDB
import GrzybEngine

/// Portable backup: observations, rule overrides, calibration log and region list (without BDL data).
public struct ExportBundle: Codable, Equatable, Sendable {
    public struct RegionStub: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var bbox: BoundingBox
        public var cellSizeM: Double
    }

    public var version: Int
    public var exportedAt: Date
    public var observations: [FieldObservation]
    public var overrides: [ParameterOverride]
    public var calibrationLog: [CalibrationEntry]
    public var regions: [RegionStub]
}

public struct ExportService: Sendable {
    let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    public func makeBundle(now: Date = Date()) throws -> ExportBundle {
        try db.writer.read { db in
            ExportBundle(
                version: 1,
                exportedAt: now,
                observations: try FieldObservation.order(Column("observedAt")).fetchAll(db),
                overrides: try OverrideRow.fetchAll(db).map(\.override),
                calibrationLog: try CalibrationEntry.order(Column("createdAt")).fetchAll(db),
                regions: try Region.fetchAll(db).map {
                    ExportBundle.RegionStub(id: $0.id, name: $0.name, bbox: $0.bbox, cellSizeM: $0.cellSizeM)
                }
            )
        }
    }

    public func exportJSON(now: Date = Date()) throws -> Data {
        try Self.encoder.encode(makeBundle(now: now))
    }

    /// Merges a bundle into the database; returns regions that need their BDL data downloaded again.
    @discardableResult
    public func importJSON(_ data: Data) throws -> [Region] {
        let bundle = try Self.decoder.decode(ExportBundle.self, from: data)
        return try db.writer.write { db in
            for obs in bundle.observations { try obs.save(db) }
            for override in bundle.overrides { try OverrideRow(override).save(db) }
            for entry in bundle.calibrationLog {
                var copy = entry
                copy.id = nil
                try copy.insert(db)
            }
            var created: [Region] = []
            for stub in bundle.regions where try Region.fetchOne(db, key: stub.id) == nil {
                let region = Region(id: stub.id, name: stub.name, bbox: stub.bbox, cellSizeM: stub.cellSizeM)
                try region.insert(db)
                created.append(region)
            }
            return created
        }
    }

    public func exportGPX(observations: [FieldObservation], speciesNames: [String: String]) -> Data {
        let iso = ISO8601DateFormatter()
        let points = observations.map { obs in
            let name = obs.speciesId.flatMap { speciesNames[$0] } ?? (obs.kind == .empty ? "Pusto" : "Obserwacja")
            return """
              <wpt lat="\(obs.lat)" lon="\(obs.lon)"><time>\(iso.string(from: obs.observedAt))</time><name>\(escape(name))</name><desc>\(escape(obs.note ?? ""))</desc></wpt>
            """
        }
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Grzybowa mapa" xmlns="http://www.topografix.com/GPX/1/1">
        \(points.joined(separator: "\n"))
        </gpx>
        """
        return Data(gpx.utf8)
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
