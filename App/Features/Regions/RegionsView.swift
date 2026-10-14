import GrzybEngine
import GrzybStore
import SwiftUI

/// List of working regions with download state, data years and actions.
struct RegionsView: View {
    @Environment(AppModel.self) private var app
    @State private var drawing = false
    @State private var pendingDelete: Region?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    DisplayTitle(text: "Regiony", size: 64)
                    Text("Region to prostokąt do 30 × 30 km. Po pobraniu działa bez zasięgu: las, siedliska, pogoda i mapa.")
                        .font(Theme.Typeface.body)
                        .foregroundStyle(Theme.Palette.charcoal)
                    Button("Dodaj region") { drawing = true }
                        .buttonStyle(PrimaryPillStyle())
                    VStack(spacing: 0) {
                        ForEach(app.regions.regions) { region in
                            RegionRow(region: region, onDelete: { pendingDelete = region })
                        }
                    }
                }
                .screenPadding()
                .padding(.bottom, Theme.Spacing.section)
            }
            .fullScreenCover(isPresented: $drawing) { RegionDrawView() }
            .confirmationDialog(
                "Usunąć region \(pendingDelete?.name ?? "")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Usuń region i mapę offline", role: .destructive) {
                    if let region = pendingDelete { app.regions.delete(region) }
                }
            } message: {
                Text("Twoje obserwacje zostaną zachowane.")
            }
        }
    }
}

private struct RegionRow: View {
    @Environment(AppModel.self) private var app
    let region: Region
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.name.uppercased()).font(Theme.Typeface.display(30))
                    Text(sizeText).font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.mute)
                }
                Spacer()
                if app.regions.active?.id == region.id { Badge(text: "Aktywny", inverted: true) }
                menu
            }
            if let stage = app.regions.stage(region.id), stage != .done {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if let fraction = stage.fraction {
                        ProgressView(value: fraction).tint(Theme.Palette.ink)
                    }
                    Text(stage.label).font(Theme.Typeface.captionSM).foregroundStyle(stage.fraction == nil ? Theme.Palette.signal : Theme.Palette.mute)
                }
            }
            HStack {
                MetaItem(label: "Dane BDL", value: dataYears)
                MetaItem(label: "Pogoda", value: region.weatherFetchedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "–")
            }
        }
        .padding(.vertical, Theme.Spacing.lg)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .onTapGesture { if region.isDownloaded { app.regions.activate(region) } }
    }

    private var menu: some View {
        Menu {
            if region.isDownloaded { Button("Ustaw jako aktywny", systemImage: "checkmark") { app.regions.activate(region) } }
            Button("Odśwież dane BDL", systemImage: "arrow.triangle.2.circlepath") { app.regions.download(region) }
            Button("Odśwież pogodę", systemImage: "cloud.rain") { Task { await app.regions.refreshWeather(region) } }
            Button("Usuń", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 44, height: 44)
        }
    }

    private var sizeText: String {
        let km = "\(PolishNumber.format(region.bbox.widthMeters / 1000)) × \(PolishNumber.format(region.bbox.heightMeters / 1000)) km"
        let mb = region.sizeBytes > 0 ? " · \(PolishNumber.format(Double(region.sizeBytes) / 1_048_576)) MB" : ""
        return km + mb
    }

    private var dataYears: String {
        guard let lo = region.bdlYearMin, let hi = region.bdlYearMax else { return region.isDownloaded ? "–" : "nie pobrano" }
        return lo == hi ? "\(lo)" : "\(lo)–\(hi)"
    }
}

/// Full-screen map with a fixed frame: the visible rectangle becomes the region.
struct RegionDrawView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var visible: BoundingBox?
    @State private var name = ""

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForestMapView(
                    content: MapContent(regionBoxes: app.regions.regions.map(\.bbox)),
                    initialCamera: initialCamera,
                    onCameraChange: { _, _, box in visible = box }
                )
                .ignoresSafeArea()
                frameOverlay(in: geo.size)
                VStack {
                    header
                    Spacer()
                    footer
                }
            }
        }
    }

    private var initialCamera: (center: Coordinate, zoom: Double) {
        if let location = app.services.location.coordinate { return (location, 11) }
        return app.preferences.camera ?? (Coordinate(lon: 21.36, lat: 52.04), 10)
    }

    private static let frameInset: CGFloat = 0.1

    private func frameOverlay(in size: CGSize) -> some View {
        let w = size.width * (1 - 2 * Self.frameInset)
        return Rectangle()
            .stroke(Theme.Palette.ink, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            .frame(width: w, height: w)
            .background(Theme.Palette.ink.opacity(0.05))
            .allowsHitTesting(false)
    }

    /// The square frame as a geographic box, derived from the visible bounds.
    private var selection: BoundingBox? {
        guard let visible else { return nil }
        let lonSpan = visible.maxLon - visible.minLon
        let insetLon = lonSpan * Self.frameInset
        let side = lonSpan - 2 * insetLon
        let centerLat = (visible.minLat + visible.maxLat) / 2
        let latSide = side * cos(centerLat * .pi / 180)
        return BoundingBox(
            minLon: visible.minLon + insetLon, minLat: centerLat - latSide / 2,
            maxLon: visible.maxLon - insetLon, maxLat: centerLat + latSide / 2
        )
    }

    private var maxMeters: Double { app.services.knowledge.parameters.grid.maxRegionKm * 1000 }

    private var isValid: Bool {
        guard let s = selection else { return false }
        return s.widthMeters <= maxMeters * 1.01 && s.heightMeters <= maxMeters * 1.01 && s.widthMeters >= 1000
    }

    private var header: some View {
        HStack {
            CircleIconButton(systemName: "xmark") { dismiss() }
            Spacer()
            Text("NOWY REGION").font(Theme.Typeface.display(28))
                .padding(.horizontal, 16).frame(height: 44)
                .background(Theme.Palette.canvas, in: Capsule())
        }
        .screenPadding()
        .padding(.top, Theme.Spacing.sm)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let s = selection {
                HStack {
                    MetaItem(label: "Rozmiar", value: "\(PolishNumber.format(s.widthMeters / 1000)) × \(PolishNumber.format(s.heightMeters / 1000)) km")
                    MetaItem(label: "Szacunkowo", value: "\(PolishNumber.integer(RegionDownloader.estimatedMegabytes(for: s))) MB")
                }
                if !isValid {
                    Text("Przybliż mapę – region może mieć najwyżej 30 × 30 km.")
                        .font(Theme.Typeface.captionMD)
                        .foregroundStyle(Theme.Palette.signal)
                }
            }
            TextField("Nazwa, np. Las pod Celestynowem", text: $name)
                .font(Theme.Typeface.body)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Theme.Palette.softCloud, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
            Button("Pobierz region", action: save)
                .buttonStyle(PrimaryPillStyle())
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.4)
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.Palette.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        .screenPadding()
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func save() {
        guard let s = selection, isValid else { return }
        let title = name.trimmingCharacters(in: .whitespaces)
        app.regions.add(name: title.isEmpty ? "Region \(app.regions.regions.count + 1)" : title, bbox: s, cellSizeM: app.services.knowledge.parameters.grid.cellSizeM)
        dismiss()
    }
}
