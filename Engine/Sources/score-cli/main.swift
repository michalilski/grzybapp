import Foundation
import GrzybData
import GrzybEngine

struct CLIOptions {
    var region: String
    var date: DayStamp
    var species: String
    var limit: Int

    init(arguments: [String]) throws {
        var values: [String: String] = [:]
        var iterator = arguments.dropFirst().makeIterator()
        while let flag = iterator.next() {
            guard flag.hasPrefix("--"), let value = iterator.next() else { throw CLIError.usage }
            values[String(flag.dropFirst(2))] = value
        }
        guard let region = values["region"] else { throw CLIError.usage }
        self.region = region
        date = values["date"].flatMap { DayStamp(iso: $0) } ?? .today()
        species = values["species"] ?? "boletus_edulis"
        limit = values["limit"].flatMap { Int($0) } ?? 10
    }
}

enum CLIError: Error, CustomStringConvertible {
    case usage
    case unknownSpecies(String)

    var description: String {
        switch self {
        case .usage: "Użycie: score-cli --region <katalog fixture> [--date RRRR-MM-DD] [--species id] [--limit n]"
        case .unknownSpecies(let id): "Nieznany gatunek: \(id)"
        }
    }
}

struct ReportPrinter {
    let session: ScoringSession

    func print(species: SpeciesProfile, date: DayStamp, limit: Int) {
        Swift.print("\(species.namePl) – \(date.iso) – \(session.cells.count) komórek lasu")
        for (rank, entry) in session.topCells(speciesId: species.id, on: date, limit: limit).enumerated() {
            let score = entry.score
            Swift.print(String(format: "\n#%d  komórka %d  (%.5f, %.5f)  indeks %.0f – %@", rank + 1, entry.cell.cellIndex, entry.cell.lat, entry.cell.lon, score.score, score.band.label))
            for reason in score.reasons {
                Swift.print("   \(symbol(reason.kind)) \(reason.text)")
            }
        }
    }

    private func symbol(_ kind: Reason.Kind) -> String {
        switch kind {
        case .positive: "✓"
        case .negative: "✗"
        case .info: "ℹ"
        case .prior: "★"
        }
    }
}

do {
    let options = try CLIOptions(arguments: CommandLine.arguments)
    let knowledge = try KnowledgeBase.bundled()
    let fixture = try FixtureRegion(directory: URL(fileURLWithPath: options.region), knowledge: knowledge)
    let session = fixture.session(knowledge: knowledge, year: options.date.year)
    guard let species = session.profile(options.species) else { throw CLIError.unknownSpecies(options.species) }
    ReportPrinter(session: session).print(species: species, date: options.date, limit: options.limit)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
