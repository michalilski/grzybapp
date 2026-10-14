import Foundation
import GRDB
import GrzybEngine

public struct RegionRepository: Sendable {
    let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    public func all() throws -> [Region] {
        try db.writer.read { try Region.order(Column("createdAt")).fetchAll($0) }
    }

    public func find(_ id: String) throws -> Region? {
        try db.writer.read { try Region.fetchOne($0, key: id) }
    }

    public func save(_ region: Region) throws {
        try db.writer.write { try region.save($0) }
    }

    public func delete(_ id: String) throws {
        try db.writer.write { _ = try Region.deleteOne($0, key: id) }
    }

    /// Replaces forest data and grid of a region in one transaction.
    public func replaceForest(regionId: String, stands: [StandRecord], sites: [SiteRecord], cells: [CellFeatures]) throws {
        try db.writer.write { db in
            let overrides = try previousOverrides(db, regionId: regionId)
            try StandRow.filter(Column("regionId") == regionId).deleteAll(db)
            try SiteRow.filter(Column("regionId") == regionId).deleteAll(db)
            try GridCellRow.filter(Column("regionId") == regionId).deleteAll(db)
            for stand in stands { try StandRow(stand, regionId: regionId).insert(db) }
            for site in sites { try SiteRow(site, regionId: regionId).insert(db) }
            for cell in cells {
                var row = GridCellRow(cell, regionId: regionId)
                row.override = overrides[cell.cellIndex] ?? row.override
                try row.insert(db)
            }
        }
    }

    public func cells(regionId: String) throws -> [CellFeatures] {
        try db.writer.read { db in
            try GridCellRow.filter(Column("regionId") == regionId).order(Column("cellIndex")).fetchAll(db).map(\.features)
        }
    }

    public func setOverride(regionId: String, cellIndex: Int, override: TerrainOverride?) throws {
        try db.writer.write { db in
            try db.execute(
                sql: "UPDATE grid_cells SET override = ? WHERE regionId = ? AND cellIndex = ?",
                arguments: [override?.rawValue, regionId, cellIndex]
            )
        }
    }

    public func stand(regionId: String, id: String) throws -> StandInfo? {
        try db.writer.read { db in
            try StandInfo.fetchOne(db, sql: "SELECT id, address, dataYear FROM stands WHERE regionId = ? AND id = ?", arguments: [regionId, id])
        }
    }

    private func previousOverrides(_ db: Database, regionId: String) throws -> [Int: String] {
        let rows = try Row.fetchAll(db, sql: "SELECT cellIndex, override FROM grid_cells WHERE regionId = ? AND override IS NOT NULL", arguments: [regionId])
        return Dictionary(rows.map { ($0["cellIndex"], $0["override"]) }, uniquingKeysWith: { a, _ in a })
    }
}

public struct WeatherRepository: Sendable {
    let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    /// Upserts days; observed values replace earlier forecasts for the same day.
    public func save(_ days: [WeatherDay], regionId: String) throws {
        try db.writer.write { db in
            for day in days { try WeatherRow(day, regionId: regionId).save(db) }
        }
    }

    public func series(regionId: String) throws -> WeatherSeries {
        let rows = try db.writer.read { try WeatherRow.filter(Column("regionId") == regionId).fetchAll($0) }
        return WeatherSeries(rows.compactMap(\.weatherDay))
    }
}

public struct ObservationRepository: Sendable {
    let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    public func all() throws -> [FieldObservation] {
        try db.writer.read { try FieldObservation.order(Column("observedAt").desc).fetchAll($0) }
    }

    public func save(_ observation: FieldObservation) throws {
        try db.writer.write { try observation.save($0) }
    }

    public func delete(_ id: String) throws {
        try db.writer.write { _ = try FieldObservation.deleteOne($0, key: id) }
    }

    public func count(speciesId: String) throws -> Int {
        try db.writer.read { try FieldObservation.filter(Column("speciesId") == speciesId).fetchCount($0) }
    }
}

public struct SpeciesRuleRepository: Sendable {
    let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    public func overrides() throws -> [ParameterOverride] {
        try db.writer.read { try OverrideRow.order(Column("changedAt")).fetchAll($0).map(\.override) }
    }

    public func save(_ override: ParameterOverride) throws {
        try db.writer.write { try OverrideRow(override).save($0) }
    }

    public func removeOverrides(speciesId: String) throws {
        try db.writer.write { db in
            _ = try OverrideRow.filter(Column("speciesId") == speciesId).deleteAll(db)
            try db.execute(sql: "UPDATE calibration_log SET reverted = 1 WHERE speciesId = ?", arguments: [speciesId])
        }
    }

    public func log(speciesId: String? = nil) throws -> [CalibrationEntry] {
        try db.writer.read { db in
            var request = CalibrationEntry.order(Column("createdAt").desc)
            if let speciesId { request = request.filter(Column("speciesId") == speciesId) }
            return try request.fetchAll(db)
        }
    }

    /// Stores the change as an override and logs it, atomically.
    public func apply(_ change: CalibrationChange, at date: Date = Date()) throws {
        try db.writer.write { db in
            let override = ParameterOverride(
                speciesId: change.speciesId, path: change.parameter, value: change.newValue,
                source: .calibration, changedAt: date
            )
            try OverrideRow(override).save(db)
            var entry = CalibrationEntry(change: change, createdAt: date)
            try entry.insert(db)
        }
    }

    /// Reverts one log entry by restoring its old value as an override.
    public func revert(_ entry: CalibrationEntry, at date: Date = Date()) throws {
        try db.writer.write { db in
            let override = ParameterOverride(
                speciesId: entry.speciesId, path: entry.parameter, value: entry.oldValue,
                source: .user, changedAt: date
            )
            try OverrideRow(override).save(db)
            try db.execute(sql: "UPDATE calibration_log SET reverted = 1 WHERE id = ?", arguments: [entry.id])
        }
    }
}

public struct SettingsRepository: Sendable {
    let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    public func string(_ key: String) -> String? {
        try? db.writer.read { try SettingRow.fetchOne($0, key: key)?.value }
    }

    public func set(_ key: String, _ value: String?) {
        try? db.writer.write { db in
            if let value {
                try SettingRow(key: key, value: value).save(db)
            } else {
                _ = try SettingRow.deleteOne(db, key: key)
            }
        }
    }

    public func bool(_ key: String) -> Bool {
        string(key) == "1"
    }

    public func setBool(_ key: String, _ value: Bool) {
        set(key, value ? "1" : "0")
    }

    public func double(_ key: String) -> Double? {
        string(key).flatMap(Double.init)
    }
}
