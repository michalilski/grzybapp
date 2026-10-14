import Foundation

public enum KnowledgeError: Error {
    case missingResource(String)
}

/// Atlas knowledge bundled with the engine, plus user overrides applied on top.
public struct KnowledgeBase: Sendable {
    public let atlasSpecies: [SpeciesProfile]
    public let parameters: EngineParameters
    public let sites: SiteProfiles
    public let codes: CodeDictionary
    public let templates: ExplainTemplates

    public init(
        atlasSpecies: [SpeciesProfile],
        parameters: EngineParameters,
        sites: SiteProfiles,
        codes: CodeDictionary,
        templates: ExplainTemplates
    ) {
        self.atlasSpecies = atlasSpecies
        self.parameters = parameters
        self.sites = sites
        self.codes = codes
        self.templates = templates
    }

    public static func bundled() throws -> KnowledgeBase {
        try load(from: try resourceDirectory())
    }

    public static func load(from directory: URL) throws -> KnowledgeBase {
        let loader = JSONResourceLoader(directory: directory)
        return KnowledgeBase(
            atlasSpecies: try loader.load([SpeciesProfile].self, "species.json"),
            parameters: try loader.load(EngineParameters.self, "engine_params.json"),
            sites: try loader.load(SiteProfiles.self, "tsl_profiles.json"),
            codes: try loader.load(CodeDictionary.self, "codes.json"),
            templates: ExplainTemplates(texts: try loader.load([String: String].self, "explain_pl.json"))
        )
    }

    public func species(applying overrides: [ParameterOverride]) -> [SpeciesProfile] {
        let grouped = Dictionary(grouping: overrides, by: \.speciesId)
        return atlasSpecies.map { profile in
            (grouped[profile.id] ?? []).reduce(profile) { $1.apply(to: $0) }
        }
    }

    private static func resourceDirectory() throws -> URL {
        guard let url = Bundle.module.url(forResource: "knowledge", withExtension: nil) else {
            throw KnowledgeError.missingResource("knowledge")
        }
        return url
    }
}

struct JSONResourceLoader {
    let directory: URL

    func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return try JSONDecoder().decode(type, from: data)
    }
}
