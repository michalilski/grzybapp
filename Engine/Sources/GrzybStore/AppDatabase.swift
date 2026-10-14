import Foundation
import GRDB

/// SQLite database with schema migrations; all user data lives here.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: url.path))
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try createRegions(db)
            try createForest(db)
            try createGrid(db)
            try createWeather(db)
            try createUserData(db)
        }
        return migrator
    }

    private static func createRegions(_ db: Database) throws {
        try db.create(table: "regions") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("minLon", .double).notNull()
            t.column("minLat", .double).notNull()
            t.column("maxLon", .double).notNull()
            t.column("maxLat", .double).notNull()
            t.column("cellSizeM", .double).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("bdlFetchedAt", .datetime)
            t.column("bdlYearMin", .integer)
            t.column("bdlYearMax", .integer)
            t.column("weatherFetchedAt", .datetime)
            t.column("sizeBytes", .integer).notNull().defaults(to: 0)
            t.column("tilesReady", .boolean).notNull().defaults(to: false)
        }
    }

    private static func createForest(_ db: Database) throws {
        try db.create(table: "stands") { t in
            t.column("id", .text).notNull()
            t.column("regionId", .text).notNull().references("regions", onDelete: .cascade)
            t.column("layer", .text).notNull()
            t.column("address", .text)
            t.column("dominantSpecies", .text)
            t.column("dominantShare", .double).notNull()
            t.column("age", .integer)
            t.column("structure", .text)
            t.column("dataYear", .integer)
            t.primaryKey(["regionId", "id"])
        }
        try db.create(table: "sites") { t in
            t.column("id", .text).notNull()
            t.column("regionId", .text).notNull().references("regions", onDelete: .cascade)
            t.column("siteType", .text)
            t.column("soilSubtype", .text)
            t.column("moistureCode", .text)
            t.column("geology", .text)
            t.column("soilSpecies", .text)
            t.column("arableFormerly", .boolean).notNull()
            t.column("degraded", .boolean).notNull()
            t.column("forestType", .text)
            t.column("dataYear", .integer)
            t.primaryKey(["regionId", "id"])
        }
    }

    private static func createGrid(_ db: Database) throws {
        try db.create(table: "grid_cells") { t in
            t.column("regionId", .text).notNull().references("regions", onDelete: .cascade)
            t.column("cellIndex", .integer).notNull()
            t.column("lon", .double).notNull()
            t.column("lat", .double).notNull()
            t.column("standId", .text)
            t.column("dominantSpecies", .text)
            t.column("dominantShare", .double).notNull()
            t.column("admixture", .text).notNull()
            t.column("standAge", .integer)
            t.column("standYear", .integer)
            t.column("standStructure", .text)
            t.column("siteId", .text)
            t.column("siteType", .text)
            t.column("geology", .text)
            t.column("forestType", .text)
            t.column("arableFormerly", .boolean).notNull()
            t.column("degraded", .boolean).notNull()
            t.column("siteYear", .integer)
            t.column("distEdgeM", .double).notNull()
            t.column("override", .text)
            t.primaryKey(["regionId", "cellIndex"])
        }
    }

    private static func createWeather(_ db: Database) throws {
        try db.create(table: "weather_days") { t in
            t.column("regionId", .text).notNull().references("regions", onDelete: .cascade)
            t.column("day", .text).notNull()
            t.column("precipMm", .double).notNull()
            t.column("tminC", .double)
            t.column("tmaxC", .double)
            t.column("soilTempC", .double)
            t.column("soilMoisture", .double)
            t.column("humidity", .double)
            t.column("isForecast", .boolean).notNull()
            t.primaryKey(["regionId", "day"])
        }
    }

    private static func createUserData(_ db: Database) throws {
        try db.create(table: "observations") { t in
            t.primaryKey("id", .text)
            t.column("regionId", .text)
            t.column("speciesId", .text)
            t.column("kind", .text).notNull()
            t.column("amount", .integer).notNull()
            t.column("lon", .double).notNull()
            t.column("lat", .double).notNull()
            t.column("cellIndex", .integer)
            t.column("observedAt", .datetime).notNull().indexed()
            t.column("photoPath", .text)
            t.column("note", .text)
            t.column("scoreAtTime", .double)
            t.column("factors", .jsonText)
            t.column("context", .jsonText)
            t.column("terrainFix", .text)
        }
        try db.create(table: "species_overrides") { t in
            t.column("speciesId", .text).notNull()
            t.column("path", .text).notNull()
            t.column("value", .jsonText).notNull()
            t.column("source", .text).notNull()
            t.column("changedAt", .datetime).notNull()
            t.primaryKey(["speciesId", "path"])
        }
        try db.create(table: "calibration_log") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("speciesId", .text).notNull()
            t.column("parameter", .text).notNull()
            t.column("oldValue", .jsonText).notNull()
            t.column("newValue", .jsonText).notNull()
            t.column("reasonText", .text).notNull()
            t.column("observationIds", .jsonText).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("reverted", .boolean).notNull().defaults(to: false)
        }
        try db.create(table: "settings") { t in
            t.primaryKey("key", .text)
            t.column("value", .text).notNull()
        }
    }
}
