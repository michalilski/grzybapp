import Foundation

public enum OverrideSource: String, Codable, Sendable {
    case user
    case calibration
}

/// Single editable species parameter addressed by a path such as `tsl.Bśw` or `season.start_doy`.
public struct ParameterPath: Hashable, Sendable, CustomStringConvertible {
    public let group: String
    public let key: String

    public init(group: String, key: String) {
        self.group = group
        self.key = key
    }

    public init?(_ raw: String) {
        let parts = raw.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        self.init(group: parts[0], key: parts[1])
    }

    public var description: String { "\(group).\(key)" }

    public static func tsl(_ code: String) -> ParameterPath { ParameterPath(group: "tsl", key: code) }
    public static func host(_ code: String) -> ParameterPath { ParameterPath(group: "hosts", key: code) }
    public static let seasonStart = ParameterPath(group: "season", key: "start_doy")
    public static let seasonEnd = ParameterPath(group: "season", key: "end_doy")
    public static let lagDays = ParameterPath(group: "weather", key: "lag_days")

    public func read(from profile: SpeciesProfile) -> [Double] {
        switch (group, key) {
        case ("tsl", _): return [profile.tsl[key] ?? 0]
        case ("hosts", _): return [profile.hosts[key] ?? 0]
        case ("season", "start_doy"): return [Double(profile.season.startDoy)]
        case ("season", "peak_lo_doy"): return [Double(profile.season.peakLoDoy)]
        case ("season", "peak_hi_doy"): return [Double(profile.season.peakHiDoy)]
        case ("season", "end_doy"): return [Double(profile.season.endDoy)]
        case ("weather", "lag_days"): return profile.weather.lagDays.map(Double.init)
        case ("weather", "rain_min_mm"): return [profile.weather.rainMinMm]
        case ("weather", "rain_opt_mm"): return [profile.weather.rainOptMm]
        default: return []
        }
    }

    public func write(_ value: [Double], to profile: SpeciesProfile) -> SpeciesProfile {
        guard let first = value.first else { return profile }
        var p = profile
        switch (group, key) {
        case ("tsl", _): p.tsl[key] = first
        case ("hosts", _): p.hosts[key] = first
        case ("season", "start_doy"): p.season.startDoy = Int(first)
        case ("season", "peak_lo_doy"): p.season.peakLoDoy = Int(first)
        case ("season", "peak_hi_doy"): p.season.peakHiDoy = Int(first)
        case ("season", "end_doy"): p.season.endDoy = Int(first)
        case ("weather", "lag_days"): p.weather.lagDays = value.map { Int($0) }
        case ("weather", "rain_min_mm"): p.weather.rainMinMm = first
        case ("weather", "rain_opt_mm"): p.weather.rainOptMm = first
        default: break
        }
        return p
    }
}

/// Patch on top of atlas knowledge, created by the user or by calibration.
public struct ParameterOverride: Codable, Equatable, Sendable {
    public var speciesId: String
    public var path: String
    public var value: [Double]
    public var source: OverrideSource
    public var changedAt: Date

    public init(speciesId: String, path: String, value: [Double], source: OverrideSource, changedAt: Date) {
        self.speciesId = speciesId
        self.path = path
        self.value = value
        self.source = source
        self.changedAt = changedAt
    }

    public func apply(to profile: SpeciesProfile) -> SpeciesProfile {
        guard let parsed = ParameterPath(path) else { return profile }
        return parsed.write(value, to: profile)
    }
}
