import GrzybEngine
import GrzybStore
import SwiftUI

/// Species card: rule parameters, lookalikes, calibration log, editing and atlas reset.
struct SpeciesDetailView: View {
    @Environment(AppModel.self) private var app
    let speciesId: String
    @State private var editing = false

    var body: some View {
        if let species = app.species.profile(speciesId) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header(species)
                    if let notice = species.notice {
                        Text(notice).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.signal)
                    }
                    if species.ecology == .mycorrhizal { hosts(species) }
                    sites(species)
                    SeasonTimeline(season: species.season)
                    weather(species)
                    lookalikes(species)
                    calibration(species)
                    Text("Apka nie identyfikuje grzybów. Zbieraj tylko to, co znasz na pewno.")
                        .font(Theme.Typeface.captionMD)
                        .foregroundStyle(Theme.Palette.mute)
                }
                .screenPadding()
                .padding(.bottom, Theme.Spacing.section)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? "Gotowe" : "Edytuj") { editing.toggle() }.foregroundStyle(Theme.Palette.ink)
                }
            }
        }
    }

    private func header(_ s: SpeciesProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            DisplayTitle(text: s.namePl, size: 56)
            Text(s.nameLat).font(Theme.Typeface.bodyStrong).italic().foregroundStyle(Theme.Palette.mute)
            HStack(spacing: Theme.Spacing.sm) {
                Badge(text: s.ecology == .mycorrhizal ? "Mykoryzowy" : "Saprotrof")
                Badge(text: s.edible ? "Jadalny" : "Niejadalny")
                if app.species.hasOverrides(s.id) { Badge(text: "Reguły zmienione", inverted: true) }
            }
        }
    }

    private func hosts(_ s: SpeciesProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Partnerzy drzewni")
            ForEach(s.hosts.sorted { $0.value > $1.value }, id: \.key) { code, value in
                parameterRow(label: app.services.knowledge.codes.treeName(code), value: value, path: .host(code), species: s)
            }
            if let age = s.standAge {
                Text("Wiek drzewostanu: optimum \(Int(age.optLo))–\(Int(age.optHi)) lat (od \(Int(age.min)) do \(Int(age.max)))")
                    .font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.mute)
            }
        }
    }

    private func sites(_ s: SpeciesProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Siedliska")
            ForEach(s.tsl.sorted { $0.value > $1.value }, id: \.key) { code, value in
                parameterRow(label: code, value: value, path: .tsl(code), species: s)
            }
        }
    }

    @ViewBuilder
    private func parameterRow(label: String, value: Double, path: ParameterPath, species: SpeciesProfile) -> some View {
        let atlas = app.species.atlas(species.id).flatMap { path.read(from: $0).first } ?? value
        if editing && atlas > 0 {
            HStack {
                Text(label).font(Theme.Typeface.captionMD).frame(width: 110, alignment: .leading)
                Slider(value: Binding(
                    get: { value },
                    set: { app.species.setParameter(species.id, path: path, value: [($0 * 10).rounded() / 10]) }
                ), in: 0.1...1, step: 0.1)
                .tint(Theme.Palette.ink)
                Text(PolishNumber.format(value)).font(Theme.Typeface.captionSM.monospacedDigit()).frame(width: 32)
            }
        } else {
            ValueBar(label: label, value: value, highlighted: abs(atlas - value) > 0.001)
        }
    }

    private func weather(_ s: SpeciesProfile) -> some View {
        let w = s.weather
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Pogoda")
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.lg, verticalSpacing: Theme.Spacing.md) {
                GridRow {
                    MetaItem(label: "Deszcz", value: "≥ \(Int(w.rainMinMm)) mm, ideał \(Int(w.rainOptMm)) mm")
                    MetaItem(label: "Okno opadu", value: "\(w.windowNear)–\(w.windowFar) dni temu")
                }
                GridRow {
                    MetaItem(label: "Opóźnienie", value: "\(w.lagLo)–\(w.lagHi) dni")
                    MetaItem(label: "Gleba", value: "\(Int(w.soilTempC.optLo))–\(Int(w.soilTempC.optHi)) °C")
                }
                GridRow {
                    MetaItem(label: "Przymrozek", value: "≤ \(Int(w.frostKillC)) °C")
                    MetaItem(label: "Zimne noce", value: w.coldNights.map { "\($0.minCount)× < \(Int($0.maxTminC)) °C" } ?? "–")
                }
            }
        }
    }

    @ViewBuilder
    private func lookalikes(_ s: SpeciesProfile) -> some View {
        if !s.lookalikes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Uważaj na")
                ForEach(s.lookalikes, id: \.self) { look in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(look.name).font(Theme.Typeface.bodyStrong)
                        Text(look.text).font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.charcoal)
                    }
                }
                Link("Atlas grzybów (Wikipedia)", destination: atlasURL(s))
                    .font(Theme.Typeface.captionMD)
                    .underline()
                    .foregroundStyle(Theme.Palette.ink)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Palette.softCloud)
        }
    }

    private func calibration(_ s: SpeciesProfile) -> some View {
        let entries = app.species.entries(for: s.id)
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Kalibracja", trailing: "\(app.journal.count(speciesId: s.id)) obserwacji")
            if entries.isEmpty {
                Text("Co \(app.services.knowledge.parameters.calibration.everyObservations) obserwacji apka sprawdza, czy reguły zgadzają się z Twoimi znaleziskami.")
                    .font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.mute)
            }
            ForEach(entries) { entry in
                HStack(alignment: .top) {
                    Text(entry.reasonText)
                        .font(Theme.Typeface.captionMD)
                        .strikethrough(entry.reverted)
                        .foregroundStyle(entry.reverted ? Theme.Palette.mute : Theme.Palette.ink)
                    Spacer()
                    if !entry.reverted {
                        Button("Cofnij") { app.species.revert(entry) }
                            .font(Theme.Typeface.captionMD)
                            .foregroundStyle(Theme.Palette.ink)
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
                .overlay(alignment: .bottom) { Hairline() }
            }
            if app.species.hasOverrides(s.id) {
                Button("Przywróć atlas") { app.species.restoreAtlas(s.id) }
                    .buttonStyle(SecondaryPillStyle())
            }
        }
    }

    private func atlasURL(_ s: SpeciesProfile) -> URL {
        let query = s.nameLat.components(separatedBy: " ").prefix(2).joined(separator: "_")
        return URL(string: "https://pl.wikipedia.org/wiki/\(query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query)")!
    }
}

/// Year bar with season window and peak.
private struct SeasonTimeline: View {
    let season: SeasonWindow
    private let months = ["S", "L", "M", "K", "M", "C", "L", "S", "W", "P", "L", "G"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: "Sezon", trailing: "szczyt \(dateText(season.peakLoDoy))–\(dateText(season.peakHiDoy))")
            GeometryReader { geo in
                let scale = geo.size.width / 365
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Palette.softCloud)
                    Rectangle().fill(Theme.Palette.stone)
                        .frame(width: CGFloat(season.endDoy - season.startDoy) * scale)
                        .offset(x: CGFloat(season.startDoy) * scale)
                    Rectangle().fill(Theme.Palette.ink)
                        .frame(width: CGFloat(season.peakHiDoy - season.peakLoDoy) * scale)
                        .offset(x: CGFloat(season.peakLoDoy) * scale)
                    Rectangle().fill(Theme.Palette.signal)
                        .frame(width: 2)
                        .offset(x: CGFloat(DayStamp.today().dayOfYear) * scale)
                }
            }
            .frame(height: 16)
            HStack(spacing: 0) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, m in
                    Text(m).font(Theme.Typeface.captionSM).foregroundStyle(Theme.Palette.mute).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func dateText(_ doy: Int) -> String {
        let c = DayStamp(year: 2026, month: 1, day: 1).adding(doy - 1).components
        return "\(c.day).\(String(format: "%02d", c.month))"
    }
}
