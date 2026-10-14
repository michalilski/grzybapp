import Foundation

/// Calendar day counted as days since 1970-01-01, independent of time zones.
public struct DayStamp: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(year: Int, month: Int, day: Int) {
        value = Self.daysFromCivil(year: year, month: month, day: day)
    }

    public init?(iso: String) {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public init(date: Date, timeZone: TimeZone = .warsaw) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public static func today() -> DayStamp {
        DayStamp(date: Date())
    }

    public var components: (year: Int, month: Int, day: Int) {
        Self.civilFromDays(value)
    }

    public var year: Int { components.year }

    public var dayOfYear: Int {
        value - DayStamp(year: year, month: 1, day: 1).value + 1
    }

    public var iso: String {
        let c = components
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    public var shortPolish: String {
        let c = components
        return "\(c.day).\(String(format: "%02d", c.month)).\(c.year)"
    }

    public var description: String { iso }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(value) * 86_400 + 12 * 3600)
    }

    public func adding(_ days: Int) -> DayStamp {
        DayStamp(value + days)
    }

    public static func - (lhs: DayStamp, rhs: DayStamp) -> Int {
        lhs.value - rhs.value
    }

    public static func < (lhs: DayStamp, rhs: DayStamp) -> Bool {
        lhs.value < rhs.value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let stamp = DayStamp(iso: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid day \(text)")
        }
        self = stamp
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }

    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}

public extension TimeZone {
    static let warsaw = TimeZone(identifier: "Europe/Warsaw") ?? .current
}
