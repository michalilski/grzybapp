import Foundation
import GrzybEngine

public enum DataError: Error, LocalizedError {
    case invalidResponse(String)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail): "Nieprawidłowa odpowiedź serwera: \(detail)"
        case .http(let code): "Błąd serwera (HTTP \(code))"
        }
    }
}

/// GeoJSON feature with raw properties and parsed polygon geometry.
public struct GeoFeature {
    public let properties: [String: Any]
    public let shape: Shape

    public func string(_ key: String) -> String? {
        guard let value = properties[key] else { return nil }
        let text = (value as? String) ?? (value as? NSNumber)?.stringValue
        let trimmed = text?.trimmingCharacters(in: .whitespaces)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    public func int(_ key: String) -> Int? {
        (properties[key] as? NSNumber)?.intValue ?? string(key).flatMap { Int($0) }
    }
}

public enum GeoJSONParser {
    public static func features(from data: Data) throws -> [GeoFeature] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DataError.invalidResponse("brak obiektu GeoJSON")
        }
        if let error = root["error"] as? [String: Any] {
            throw DataError.invalidResponse(error["message"] as? String ?? "błąd ArcGIS")
        }
        let features = root["features"] as? [[String: Any]] ?? []
        return features.compactMap(feature)
    }

    private static func feature(_ json: [String: Any]) -> GeoFeature? {
        guard let geometry = json["geometry"] as? [String: Any], let shape = shape(geometry) else { return nil }
        return GeoFeature(properties: json["properties"] as? [String: Any] ?? [:], shape: shape)
    }

    static func shape(_ geometry: [String: Any]) -> Shape? {
        let type = geometry["type"] as? String
        let coordinates = geometry["coordinates"]
        switch type {
        case "Polygon":
            return (coordinates as? [[[Double]]]).flatMap(polygon).flatMap { Shape(polygons: [$0]) }
        case "MultiPolygon":
            let polygons = (coordinates as? [[[[Double]]]])?.compactMap(polygon) ?? []
            return Shape(polygons: polygons)
        default:
            return nil
        }
    }

    private static func polygon(_ rings: [[[Double]]]) -> Polygon? {
        Polygon(rings: rings.map { ring in ring.compactMap { $0.count >= 2 ? Coordinate(lon: $0[0], lat: $0[1]) : nil } })
    }
}
