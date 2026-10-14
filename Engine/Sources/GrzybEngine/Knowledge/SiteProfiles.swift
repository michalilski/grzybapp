import Foundation

/// Rules translating BDL forest site codes (TSL) into engine inputs.
public struct SiteProfiles: Codable, Equatable, Sendable {
    public struct GeologyRule: Codable, Equatable, Sendable {
        public var contains: String
        public var siteTypes: [String]

        enum CodingKeys: String, CodingKey {
            case contains
            case siteTypes = "site_types"
        }
    }

    public var moisture: [String: MoistureClass]
    public var aliases: [String: String]
    public var stripTokens: [String]
    public var geologyFallback: [GeologyRule]
    public var forestTypeSpecies: [String: String]

    enum CodingKeys: String, CodingKey {
        case moisture, aliases
        case stripTokens = "strip_tokens"
        case geologyFallback = "geology_fallback"
        case forestTypeSpecies = "forest_type_species"
    }

    public func normalizedSiteType(_ raw: String?) -> String? {
        guard let code = raw?.trimmingCharacters(in: .whitespaces), !code.isEmpty else { return nil }
        if let alias = aliases[code] { return alias }
        return stripTokens.reduce(code) { $0.replacingOccurrences(of: $1, with: "") }
    }

    public func moistureClass(of siteType: String?) -> MoistureClass? {
        guard let code = normalizedSiteType(siteType) else { return nil }
        return moisture[code]
    }

    public func fallbackSiteTypes(forGeology geology: String?) -> [String] {
        guard let geology, !geology.isEmpty else { return [] }
        return geologyFallback.first { geology.contains($0.contains) }?.siteTypes ?? []
    }

    public func speciesCodes(forForestType forestType: String?) -> [String] {
        guard let forestType else { return [] }
        return forestType
            .split(whereSeparator: { $0 == "-" || $0 == " " })
            .compactMap { forestTypeSpecies[String($0)] }
    }
}

/// Human-readable names of BDL codes.
public struct CodeDictionary: Codable, Equatable, Sendable {
    public var treeSpecies: [String: String]
    public var treeSpeciesGenitive: [String: String]
    public var siteTypes: [String: String]
    public var moisture: [String: String]
    public var standStructure: [String: String]
    public var terrainOverrides: [String: String]

    enum CodingKeys: String, CodingKey {
        case moisture
        case treeSpecies = "tree_species"
        case treeSpeciesGenitive = "tree_species_genitive"
        case siteTypes = "site_types"
        case standStructure = "stand_structure"
        case terrainOverrides = "terrain_overrides"
    }

    public func treeName(_ code: String?) -> String {
        guard let code else { return "–" }
        return treeSpecies[code] ?? code
    }

    public func siteName(_ code: String?) -> String {
        guard let code else { return "–" }
        return siteTypes[code] ?? code
    }

    public static func normalizedTreeCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.split(separator: ".").first ?? Substring(trimmed))
    }
}
