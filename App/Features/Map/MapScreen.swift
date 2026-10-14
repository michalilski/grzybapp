import GrzybEngine
import GrzybStore
import SwiftUI

/// Home screen: forest map with potential overlay, species chips and day selector.
struct MapScreen: View {
    @Environment(AppModel.self) private var app
    @Binding var tab: RootTab
    @State private var command: MapCommand?
    @State private var showDetails = false

    var body: some View {
        ZStack {
            ForestMapView(
                content: content,
                command: command,
                initialCamera: app.preferences.camera,
                onTap: handleTap,
                onLongPress: { app.startObservation(at: $0) },
                onCameraChange: { center, zoom, _ in app.preferences.saveCamera(center: center, zoom: zoom) }
            )
            .ignoresSafeArea()
            VStack(spacing: 0) {
                MapTopBar(onRegionSelected: fit)
                Spacer()
                MapBottomBar(
                    onCenter: centerOnUser,
                    onAdd: { app.startObservation(at: nil) },
                    onDownload: { tab = .regions }
                )
            }
        }
        .sheet(isPresented: $showDetails, onDismiss: { app.map.selectedCell = nil }) {
            if let index = app.map.selectedCell {
                CellDetailsSheet(cellIndex: index, onNavigate: navigate)
                    .presentationDetents([.fraction(0.48), .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.48)))
                    .presentationCornerRadius(Theme.Radius.field)
            }
        }
        .onAppear(perform: fitIfFirstLaunch)
        .onChange(of: app.map.isBuilding) { _, building in
            #if DEBUG
            if !building, ProcessInfo.processInfo.environment["DEMO_TAB"] == "cell", let session = app.map.session {
                app.map.selectedCell = session.topCells(speciesId: "boletus_edulis", on: app.map.selectedDay, limit: 1).first?.cell.cellIndex
                showDetails = app.map.selectedCell != nil
            }
            #endif
        }
        .onChange(of: app.regions.active?.bdlFetchedAt) { _, fetched in
            if fetched != nil, let region = app.regions.active { fit(region) }
        }
    }

    private var content: MapContent {
        let region = app.regions.active
        return MapContent(
            overlay: app.map.overlay,
            overlayOpacity: app.preferences.fieldMode ? 0.8 : 0.6,
            outlinesURL: region.map { app.services.files.outlinesURL($0.id) },
            showOutlines: !app.preferences.fieldMode,
            observations: app.journal.observations.filter { $0.kind == .found || $0.kind == .empty },
            regionBoxes: app.regions.regions.map(\.bbox),
            selection: app.map.selectedCell.flatMap { app.map.session?.geometry.cellBounds(of: $0) }
        )
    }

    private func handleTap(_ coordinate: Coordinate) {
        guard let index = app.map.cellIndex(at: coordinate) else {
            app.map.selectedCell = nil
            showDetails = false
            return
        }
        app.map.selectedCell = index
        showDetails = true
    }

    private func centerOnUser() {
        guard let location = app.services.location.coordinate else {
            app.toast = "Czekam na sygnał GPS…"
            return
        }
        command = MapCommand(action: .center(location, zoom: 15))
    }

    private func fit(_ region: Region) {
        command = MapCommand(action: .fit(region.bbox))
    }

    private func fitIfFirstLaunch() {
        if app.preferences.camera == nil, let region = app.regions.active { fit(region) }
    }

    private func navigate(_ target: Coordinate) {
        showDetails = false
        app.navigationTarget = target
    }
}

/// Region switcher, status badges and species chips.
private struct MapTopBar: View {
    @Environment(AppModel.self) private var app
    let onRegionSelected: (Region) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                regionMenu
                Spacer()
                statusBadges
                CircleIconButton(systemName: app.preferences.fieldMode ? "sun.max.fill" : "sun.max", filled: app.preferences.fieldMode) {
                    app.preferences.fieldMode.toggle()
                    app.redraw()
                }
            }
            .screenPadding()
            SpeciesChips()
            if let flush = app.map.flushes.first {
                FlushBanner(flush: flush).screenPadding()
            } else if app.map.session != nil, !app.map.isBuilding,
                      Double(app.map.maxScore) < app.services.knowledge.parameters.bands.moderate {
                LowPotentialHint().screenPadding()
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private var regionMenu: some View {
        Menu {
            ForEach(app.regions.regions.filter(\.isDownloaded)) { region in
                Button(region.name) {
                    app.regions.activate(region)
                    onRegionSelected(region)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text((app.regions.active?.name ?? "Grzybowa mapa").uppercased())
                    .font(Theme.Typeface.display(24))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Theme.Palette.canvas, in: Capsule())
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        if app.map.isBuilding {
            Badge(text: "Liczę…")
        } else if app.regions.weatherRefreshing {
            Badge(text: "Pogoda…")
        } else if app.regions.offline {
            Badge(text: "Offline", inverted: true)
        }
    }
}

/// "All edible" chip plus one chip per enabled species.
private struct SpeciesChips: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                FilterChip(title: "Ogólnie", isSelected: app.map.isGeneral) {
                    app.select(filter: Preferences.general)
                }
                FilterChip(title: "Wszystkie jadalne", isSelected: app.preferences.speciesFilter == Preferences.allSpecies) {
                    app.select(filter: Preferences.allSpecies)
                }
                ForEach(app.species.enabled) { species in
                    FilterChip(title: species.namePl, isSelected: app.preferences.speciesFilter == species.id) {
                        app.select(filter: species.id)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }
}

private struct LowPotentialHint: View {
    var body: some View {
        Text("Dziś niski potencjał w całym regionie. Sprawdź kolejne dni albo dotknij las, by zobaczyć dlaczego.")
            .font(Theme.Typeface.captionMD)
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.Palette.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
    }
}

private struct FlushBanner: View {
    @Environment(AppModel.self) private var app
    let flush: FlushForecast

    var body: some View {
        let from = max(0, flush.from - DayStamp.today())
        let to = max(from, flush.to - DayStamp.today())
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
            Text("Wysyp za \(from)–\(to) dni: \(app.species.name(flush.speciesId).lowercased())")
                .font(Theme.Typeface.captionMD)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.Palette.canvas)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Theme.Palette.ink, in: Capsule())
    }
}

/// Day selector, legend and the location / add buttons.
private struct MapBottomBar: View {
    @Environment(AppModel.self) private var app
    let onCenter: () -> Void
    let onAdd: () -> Void
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Spacer()
                CircleIconButton(systemName: "location.fill", action: onCenter)
                CircleIconButton(systemName: "plus", filled: true, action: onAdd)
            }
            .screenPadding()
            if app.regions.active?.isDownloaded == true {
                DaySelector()
            } else {
                DownloadPrompt(onDownload: onDownload)
            }
        }
        .padding(.bottom, Theme.Spacing.sm)
    }
}

private struct DownloadPrompt: View {
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            DisplayTitle(text: "Pobierz region, żeby zobaczyć potencjał", size: 34)
            Text("Apka podpowiada, gdzie szukać. Co zebrałeś, sprawdzasz sam.")
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Palette.charcoal)
            Button("Wybierz region", action: onDownload).buttonStyle(PrimaryPillStyle())
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.Palette.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        .screenPadding()
    }
}

/// Today … +7 days, with legend and weather-age warning.
private struct DaySelector: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(dayTitle.uppercased())
                    .font(Theme.Typeface.display(28))
                Spacer()
                if WeatherService.isStale(app.regions.active) {
                    Label(weatherAge, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typeface.captionSM)
                        .foregroundStyle(Theme.Palette.signal)
                }
                if app.map.isGeneral { HeatLegend() } else { Legend() }
            }
            HStack(spacing: 6) {
                ForEach(0...7, id: \.self) { offset in
                    dayButton(offset)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Palette.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        .screenPadding()
    }

    private func dayButton(_ offset: Int) -> some View {
        let selected = app.preferences.dayOffset == offset
        return Button {
            app.select(dayOffset: offset)
        } label: {
            VStack(spacing: 0) {
                Text(DayLabels.weekday(DayStamp.today().adding(offset)))
                    .font(Theme.Typeface.captionSM)
                Text(offset == 0 ? "DZIŚ" : "+\(offset)")
                    .font(Theme.Typeface.display(18))
            }
            .foregroundStyle(selected ? Theme.Palette.canvas : Theme.Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected ? Theme.Palette.ink : Theme.Palette.softCloud, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var dayTitle: String {
        let day = DayStamp.today().adding(app.preferences.dayOffset)
        return app.preferences.dayOffset == 0 ? "Dziś · \(day.shortPolish)" : "\(DayLabels.weekdayLong(day)) · \(day.shortPolish)"
    }

    private var weatherAge: String {
        guard let fetched = app.regions.active?.weatherFetchedAt else { return "brak pogody" }
        return "pogoda sprzed \(Int(Date().timeIntervalSince(fetched) / 3600)) h"
    }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach([PotentialBand.moderate, .good, .veryGood], id: \.self) { band in
                RoundedRectangle(cornerRadius: 2).fill(BandStyle.color(band)).frame(width: 14, height: 10)
            }
        }
        .accessibilityLabel("Legenda: umiarkowany, dobry, bardzo dobry")
    }
}

/// Gradient bar for the general heatmap.
private struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("mało").font(Theme.Typeface.captionSM).foregroundStyle(Theme.Palette.mute)
            LinearGradient(colors: stride(from: 10.0, through: 100, by: 15).map(color), startPoint: .leading, endPoint: .trailing)
                .frame(width: 56, height: 10)
                .clipShape(Capsule())
            Text("dużo").font(Theme.Typeface.captionSM).foregroundStyle(Theme.Palette.mute)
        }
        .accessibilityLabel("Legenda: ogólny potencjał od małego do dużego")
    }

    private func color(_ value: Double) -> Color {
        let c = HeatRamp.color(at: value)
        return Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255).opacity(max(0.25, c.a / 255))
    }
}

enum DayLabels {
    private static let short = ["ND", "PN", "WT", "ŚR", "CZ", "PT", "SB"]
    private static let long = ["Niedziela", "Poniedziałek", "Wtorek", "Środa", "Czwartek", "Piątek", "Sobota"]

    static func weekday(_ day: DayStamp) -> String {
        short[weekdayIndex(day)]
    }

    static func weekdayLong(_ day: DayStamp) -> String {
        long[weekdayIndex(day)]
    }

    private static func weekdayIndex(_ day: DayStamp) -> Int {
        ((day.value % 7) + 7 + 4) % 7
    }
}
