import Foundation
import GrzybEngine

/// Client for Bank Danych o Lasach ArcGIS REST layers (stands 66/67, sites 20).
public struct BDLClient: Sendable {
    public enum Layer: Sendable {
        case stateStands, otherStands, sites

        var path: String {
            switch self {
            case .stateStands: "Mapa_drzewostanow/MapServer/66"
            case .otherStands: "Mapa_drzewostanow/MapServer/67"
            case .sites: "Mapa_siedlisk/MapServer/20"
            }
        }

        var orderField: String {
            self == .sites ? "site_type_id" : "subarea_id"
        }

        var outFields: String {
            switch self {
            case .stateStands, .otherStands:
                "subarea_id,adress_forest,species_cd,part_cd,species_age,stand_struct_cd,a_year"
            case .sites:
                "site_type_id,site_type_cd,soil_subtype_cd,moisture_cd,degradation_cd,arable_formerly,forest_type_cd,geol_depos,soil_species,a_year"
            }
        }
    }

    public static let baseURL = URL(string: "http://mapserver.bdl.lasy.gov.pl/arcgis/rest/services")!
    public let session: URLSession
    public let pageSize: Int

    public init(session: URLSession = .shared, pageSize: Int = 1000) {
        self.session = session
        self.pageSize = pageSize
    }

    public func fetch(_ layer: Layer, bbox: BoundingBox) async throws -> [GeoFeature] {
        var features: [GeoFeature] = []
        var offset = 0
        while true {
            let batch = try GeoJSONParser.features(from: try await page(layer, bbox: bbox, offset: offset))
            features += batch
            guard batch.count >= pageSize else { break }
            offset += pageSize
        }
        return features
    }

    func queryURL(_ layer: Layer, bbox: BoundingBox, offset: Int) -> URL {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(layer.path + "/query"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "geometry", value: "\(bbox.minLon),\(bbox.minLat),\(bbox.maxLon),\(bbox.maxLat)"),
            URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "outSR", value: "4326"),
            URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
            URLQueryItem(name: "outFields", value: layer.outFields),
            URLQueryItem(name: "orderByFields", value: layer.orderField),
            URLQueryItem(name: "resultOffset", value: String(offset)),
            URLQueryItem(name: "resultRecordCount", value: String(pageSize)),
            URLQueryItem(name: "geometryPrecision", value: "6"),
            URLQueryItem(name: "maxAllowableOffset", value: "0.00003"),
            URLQueryItem(name: "f", value: "geojson"),
        ]
        return components.url!
    }

    private func page(_ layer: Layer, bbox: BoundingBox, offset: Int) async throws -> Data {
        var request = URLRequest(url: queryURL(layer, bbox: bbox, offset: offset))
        request.timeoutInterval = 90
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DataError.http(http.statusCode)
        }
        return data
    }
}

/// Converts BDL GeoJSON features into engine records.
public enum BDLRecordMapper {
    public static func stand(_ f: GeoFeature, layer: ForestLayer) -> StandRecord? {
        guard let id = f.string("subarea_id") else { return nil }
        let share = f.string("part_cd").flatMap(Double.init).map { $0 / 10 } ?? 1
        return StandRecord(
            id: "\(layer.rawValue)-\(id)",
            layer: layer,
            address: f.string("adress_forest"),
            dominantSpecies: CodeDictionary.normalizedTreeCode(f.string("species_cd")),
            dominantShare: min(1, max(0, share)),
            age: f.int("species_age"),
            structure: f.string("stand_struct_cd"),
            dataYear: f.int("a_year"),
            shape: f.shape
        )
    }

    public static func site(_ f: GeoFeature) -> SiteRecord? {
        guard let id = f.string("site_type_id") else { return nil }
        return SiteRecord(
            id: "site-\(id)",
            siteType: f.string("site_type_cd"),
            soilSubtype: f.string("soil_subtype_cd"),
            moistureCode: f.string("moisture_cd"),
            geology: f.string("geol_depos"),
            soilSpecies: f.string("soil_species"),
            arableFormerly: f.string("arable_formerly") == "T",
            degraded: f.string("degradation_cd")?.hasPrefix("Z") ?? false,
            forestType: f.string("forest_type_cd"),
            dataYear: f.int("a_year"),
            shape: f.shape
        )
    }
}
