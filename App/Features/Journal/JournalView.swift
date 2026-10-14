import GrzybEngine
import GrzybStore
import SwiftUI
import UniformTypeIdentifiers

/// Observation journal with season summary, find calendar and export/import.
struct JournalView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: String?
    @State private var shareURL: URL?
    @State private var importing = false

    private var year: Int { DayStamp.today().year }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    DisplayTitle(text: "Dziennik", size: 64)
                    filters
                    SeasonCard(summary: app.journal.summary(year: year, speciesId: filter), year: year)
                    SeasonHeatmap(findsByDay: app.journal.summary(year: year, speciesId: filter).findsByDay, year: year)
                    list
                }
                .screenPadding()
                .padding(.bottom, Theme.Spacing.section)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { exportMenu } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], onCompletion: handleImport)
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url]).presentationDetents([.medium])
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                FilterChip(title: "Wszystkie", isSelected: filter == nil) { filter = nil }
                ForEach(app.species.profiles.filter { id in app.journal.observations.contains { $0.speciesId == id.id } }) { species in
                    FilterChip(title: species.namePl, isSelected: filter == species.id) { filter = species.id }
                }
            }
        }
    }

    private var filtered: [FieldObservation] {
        app.journal.observations.filter { filter == nil || $0.speciesId == filter }
    }

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Obserwacje", trailing: "\(filtered.count)")
            if filtered.isEmpty {
                Text("Przytrzymaj palec na mapie albo użyj „+”, żeby dodać pierwsze znalezisko.")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.mute)
                    .padding(.vertical, Theme.Spacing.lg)
            }
            ForEach(filtered) { obs in
                ObservationRow(observation: obs)
                    .contentShape(Rectangle())
                    .onTapGesture { if obs.kind != .terrainFix { app.edit(obs) } }
                    .contextMenu {
                        if obs.kind != .terrainFix { Button("Edytuj") { app.edit(obs) } }
                        Button("Pokaż drogę") { app.navigationTarget = obs.coordinate }
                        Button("Usuń", role: .destructive) { app.journal.delete(obs) }
                    }
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("Eksport JSON (kopia zapasowa)", systemImage: "square.and.arrow.up") { shareURL = try? app.journal.exportJSON() }
            Button("Eksport GPX", systemImage: "map") {
                shareURL = try? app.journal.exportGPX(names: Dictionary(uniqueKeysWithValues: app.species.profiles.map { ($0.id, $0.namePl) }))
            }
            Button("Import JSON", systemImage: "square.and.arrow.down") { importing = true }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(Theme.Palette.ink)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        do {
            let regions = try app.journal.importJSON(from: url)
            app.species.reload()
            app.regions.reload()
            regions.forEach(app.regions.download)
            app.toast = "Zaimportowano. Regiony pobierają się ponownie."
        } catch {
            app.toast = "Nie udało się zaimportować pliku"
        }
    }
}

private struct ObservationRow: View {
    @Environment(AppModel.self) private var app
    let observation: FieldObservation

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Typeface.bodyStrong)
                Text(subtitle).font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.mute)
                if let note = observation.note { Text(note).font(Theme.Typeface.captionSM).foregroundStyle(Theme.Palette.charcoal).lineLimit(2) }
            }
            Spacer()
            if let score = observation.scoreAtTime {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(PolishNumber.integer(score)).font(Theme.Typeface.display(26))
                    Text("INDEKS").font(Theme.Typeface.captionSM).foregroundStyle(Theme.Palette.mute)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.md)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = app.journal.photo(observation.photoPath) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 56, height: 56).clipped()
        } else {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(observation.kind == .found ? Theme.Palette.canvas : Theme.Palette.ink)
                .frame(width: 56, height: 56)
                .background(observation.kind == .found ? Theme.Palette.ink : Theme.Palette.softCloud)
        }
    }

    private var icon: String {
        switch observation.kind {
        case .found: "checkmark"
        case .empty: "xmark"
        case .terrainFix: "exclamationmark.bubble"
        case .rating: "hand.thumbsup"
        }
    }

    private var title: String {
        switch observation.kind {
        case .found: app.species.name(observation.speciesId)
        case .empty: "Pusto · " + (observation.speciesId.map { app.species.name($0) } ?? "nic")
        case .terrainFix: "Korekta: " + (observation.terrainFix.map { app.services.knowledge.codes.terrainOverrides[$0.rawValue] ?? $0.rawValue } ?? "usunięta")
        case .rating: "Ocena"
        }
    }

    private var subtitle: String {
        let amount = observation.kind == .found ? ["pojedyncze", "kilka", "dużo"][max(0, min(2, observation.amount - 1))] + " · " : ""
        return amount + observation.observedAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }
}

/// Black summary card for the current season.
private struct SeasonCard: View {
    @Environment(AppModel.self) private var app
    let summary: SeasonSummary
    let year: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("SEZON \(String(year))").font(Theme.Typeface.display(28)).foregroundStyle(Theme.Palette.stone)
            HStack(alignment: .bottom, spacing: Theme.Spacing.xl) {
                stat(summary.finds, "znalezisk")
                stat(summary.empties, "pustych wyjść")
                if let lag = summary.medianDaysAfterRain { stat(lag, "dni po deszczu (mediana)") }
            }
            if !summary.topSpecies.isEmpty {
                Text(summary.topSpecies.map { "\(app.species.name($0.id)) ×\($0.count)" }.joined(separator: " · "))
                    .font(Theme.Typeface.captionMD)
                    .foregroundStyle(Theme.Palette.canvas)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .background(Theme.Palette.ink)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(Theme.Typeface.display(56)).foregroundStyle(Theme.Palette.canvas)
            Text(label.uppercased()).font(Theme.Typeface.captionSM).foregroundStyle(Theme.Palette.stone)
        }
    }
}

/// Calendar heatmap of finds per day of year (weeks × weekdays).
struct SeasonHeatmap: View {
    let findsByDay: [Int: Int]
    let year: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Kalendarz znalezisk")
            Canvas { context, size in
                let first = DayStamp(year: year, month: 1, day: 1)
                let offset = (first.value + 3) % 7
                let weeks = 53
                let cell = min(size.width / CGFloat(weeks), size.height / 7)
                for doy in 1...366 {
                    let day = first.adding(doy - 1)
                    guard day.year == year else { break }
                    let slot = doy - 1 + offset
                    let rect = CGRect(x: CGFloat(slot / 7) * cell, y: CGFloat(slot % 7) * cell, width: cell - 1.5, height: cell - 1.5)
                    context.fill(Path(rect), with: .color(color(findsByDay[doy] ?? 0)))
                }
            }
            .frame(height: 64)
            HStack {
                Text("STY").frame(maxWidth: .infinity, alignment: .leading)
                Text("KWI").frame(maxWidth: .infinity, alignment: .leading)
                Text("LIP").frame(maxWidth: .infinity, alignment: .leading)
                Text("PAŹ").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Theme.Typeface.captionSM)
            .foregroundStyle(Theme.Palette.mute)
        }
    }

    private func color(_ count: Int) -> Color {
        switch count {
        case 0: Theme.Palette.softCloud
        case 1: Theme.Palette.stone
        case 2...3: Theme.Palette.charcoal
        default: Theme.Palette.ink
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
