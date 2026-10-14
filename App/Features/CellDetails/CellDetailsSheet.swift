import Charts
import GrzybEngine
import GrzybStore
import SwiftUI

/// Bottom sheet for a tapped grid cell: species ranking, reasons, source data, recent rain and actions.
struct CellDetailsSheet: View {
    @Environment(AppModel.self) private var app
    let cellIndex: Int
    let onNavigate: (Coordinate) -> Void
    @State private var expanded: String?

    var body: some View {
        ScrollView {
            if let session = app.map.session, let cell = session.cell(at: cellIndex) {
                content(session: session, cell: cell)
            } else {
                Text("Brak danych dla tego miejsca").padding()
            }
        }
        .background(Theme.Palette.canvas)
    }

    private func content(session: ScoringSession, cell: CellFeatures) -> some View {
        let ranking = session.ranking(at: cellIndex, on: app.map.selectedDay, speciesIds: app.species.enabled.map(\.id))
        return VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            header(ranking.first, cell: cell)
            actions(cell: cell, ranking: ranking)
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Ranking gatunków", trailing: app.map.selectedDay.shortPolish)
                ForEach(ranking.filter { $0.score >= 1 || $0.id == expanded }) { score in
                    SpeciesScoreRow(score: score, isExpanded: expanded == score.id) {
                        withAnimation(.snappy) { expanded = expanded == score.id ? nil : score.id }
                    }
                }
                if ranking.allSatisfy({ $0.score < 1 }) {
                    Text("Żaden gatunek nie ma tu dziś potencjału.")
                        .font(Theme.Typeface.body)
                        .foregroundStyle(Theme.Palette.mute)
                        .padding(.vertical, Theme.Spacing.lg)
                }
            }
            SourceDataSection(cell: cell)
            RainChart(weather: session.weather, day: app.map.selectedDay)
            Text("Apka nie identyfikuje grzybów. Zbieraj tylko to, co znasz na pewno.")
                .font(Theme.Typeface.captionSM)
                .foregroundStyle(Theme.Palette.mute)
        }
        .padding(Theme.Spacing.xl)
        .onAppear { expanded = expanded ?? ranking.first?.id }
    }

    private func header(_ best: SpeciesScore?, cell: CellFeatures) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("WARTO SPRAWDZIĆ")
                    .font(Theme.Typeface.captionSM)
                    .foregroundStyle(Theme.Palette.mute)
                DisplayTitle(text: best?.species.namePl ?? "Brak potencjału", size: 40)
                Text(app.services.knowledge.codes.siteName(cell.effective.siteType) + " · " + app.services.knowledge.codes.treeName(cell.dominantSpecies))
                    .font(Theme.Typeface.captionMD)
                    .foregroundStyle(Theme.Palette.mute)
            }
            Spacer()
            if let best { ScoreBadge(score: best.score, band: best.band, size: 64) }
        }
    }

    private func actions(cell: CellFeatures, ranking: [SpeciesScore]) -> some View {
        let target = app.preferences.speciesFilter == Preferences.allSpecies ? ranking.first?.id : app.preferences.speciesFilter
        return VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Button("Znalazłem") { app.startObservation(at: cell.coordinate, speciesId: target, kind: .found) }
                    .buttonStyle(PrimaryPillStyle())
                Button("Pusto") { app.startObservation(at: cell.coordinate, speciesId: target, kind: .empty) }
                    .buttonStyle(SecondaryPillStyle())
            }
            HStack(spacing: Theme.Spacing.sm) {
                CircleIconButton(systemName: "hand.thumbsup") { app.rate(cellIndex: cellIndex, positive: true) }
                CircleIconButton(systemName: "hand.thumbsdown") { app.rate(cellIndex: cellIndex, positive: false) }
                terrainMenu(cell: cell)
                Spacer()
                Button {
                    onNavigate(cell.coordinate)
                } label: {
                    Label("Nawiguj", systemImage: "location.north.line.fill")
                }
                .buttonStyle(SecondaryPillStyle())
                .frame(width: 150)
            }
        }
    }

    private func terrainMenu(cell: CellFeatures) -> some View {
        Menu {
            ForEach(TerrainOverride.allCases, id: \.self) { fix in
                Button(app.services.knowledge.codes.terrainOverrides[fix.rawValue] ?? fix.rawValue) {
                    app.applyTerrainFix(fix, cellIndex: cellIndex)
                }
            }
            if cell.override != nil {
                Button("Usuń korektę", role: .destructive) { app.applyTerrainFix(nil, cellIndex: cellIndex) }
            }
        } label: {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 44, height: 44)
                .background(Theme.Palette.canvas, in: Circle())
                .overlay(Circle().stroke(Theme.Palette.hairlineSoft, lineWidth: 1))
        }
        .accessibilityLabel("Oznacz korektę terenu")
    }
}

/// One species with its index; expands into the list of reasons.
private struct SpeciesScoreRow: View {
    let score: SpeciesScore
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button(action: toggle) {
                HStack(spacing: Theme.Spacing.md) {
                    Circle().fill(BandStyle.color(score.band)).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(score.species.namePl).font(Theme.Typeface.bodyStrong)
                        Text(score.band.label).font(Theme.Typeface.captionSM).foregroundStyle(Theme.Palette.mute)
                    }
                    Spacer()
                    Text(PolishNumber.integer(score.score))
                        .font(Theme.Typeface.display(30))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Theme.Palette.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(score.reasons, id: \.self) { ReasonRow(reason: $0) }
                    if let notice = score.species.notice {
                        Text(notice)
                            .font(Theme.Typeface.captionMD)
                            .foregroundStyle(Theme.Palette.signal)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, Theme.Spacing.lg)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

struct ReasonRow: View {
    let reason: Reason

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(symbol)
                .font(Theme.Typeface.bodyStrong)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(reason.text)
                .font(Theme.Typeface.captionMD)
                .foregroundStyle(Theme.Palette.charcoal)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var symbol: String {
        switch reason.kind {
        case .positive: "✓"
        case .negative: "✗"
        case .info: "ℹ"
        case .prior: "★"
        }
    }

    private var color: Color {
        switch reason.kind {
        case .positive: Theme.Palette.success
        case .negative: Theme.Palette.signal
        case .info: Theme.Palette.mute
        case .prior: Theme.Palette.ink
        }
    }
}

/// Stand and site attributes from BDL, with data year.
private struct SourceDataSection: View {
    @Environment(AppModel.self) private var app
    let cell: CellFeatures

    var body: some View {
        let codes = app.services.knowledge.codes
        let c = cell.effective
        let stand = c.standId.flatMap { id in app.regions.active.flatMap { try? app.services.regions.stand(regionId: $0.id, id: id) } }
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Dane źródłowe")
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.lg, verticalSpacing: Theme.Spacing.md) {
                GridRow {
                    MetaItem(label: "Drzewostan", value: c.dominantSpecies.map { "\(codes.treeName($0)) \(PolishNumber.integer(c.dominantShare * 100)) %" } ?? "brak danych")
                    MetaItem(label: "Wiek", value: c.standAge.map { "\($0) lat" } ?? "–")
                }
                GridRow {
                    MetaItem(label: "Siedlisko", value: codes.siteName(c.siteType))
                    MetaItem(label: "Typ lasu", value: c.forestType ?? "–")
                }
                GridRow {
                    MetaItem(label: "Rok danych", value: [c.standYear, c.siteYear].compactMap { $0.map(String.init) }.joined(separator: " / "))
                    MetaItem(label: "Do skraju", value: c.distEdgeM < 1e8 ? "\(PolishNumber.integer(c.distEdgeM)) m" : "–")
                }
                if let address = stand?.address {
                    GridRow {
                        MetaItem(label: "Adres leśny", value: address)
                            .gridCellColumns(2)
                    }
                }
            }
            if c.arableFormerly { Badge(text: "Grunt porolny") }
            if let fix = c.override { Badge(text: "Korekta: \(codes.terrainOverrides[fix.rawValue] ?? fix.rawValue)", inverted: true) }
        }
    }
}

/// Daily precipitation for the 21 days before the selected day.
struct RainChart: View {
    let weather: WeatherSeries
    let day: DayStamp

    var body: some View {
        let days = weather.range(from: day.adding(-20), to: day)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Opad – 21 dni", trailing: "\(PolishNumber.integer(days.reduce(0) { $0 + $1.precipMm })) mm")
            if days.isEmpty {
                Text("Brak danych pogodowych").font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.mute)
            } else {
                Chart(days, id: \.day) { d in
                    BarMark(x: .value("Dzień", d.day.date, unit: .day), y: .value("mm", d.precipMm))
                        .foregroundStyle(d.isForecast ? Theme.Palette.stone : Theme.Palette.ink)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.day().month(.defaultDigits)) } }
                .frame(height: 120)
            }
        }
    }
}
