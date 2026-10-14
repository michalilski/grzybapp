import GrzybEngine
import SwiftUI

/// Species catalogue with filter toggles, plus settings and about.
struct SpeciesListView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    DisplayTitle(text: "Gatunki i reguły", size: 64)
                    VStack(spacing: 0) {
                        ForEach(app.species.profiles) { species in
                            NavigationLink(value: species.id) { SpeciesRow(species: species) }
                                .buttonStyle(.plain)
                        }
                    }
                    SettingsSection()
                    NavigationLink("O aplikacji i licencje") { AboutView() }
                        .buttonStyle(SecondaryPillStyle())
                }
                .screenPadding()
                .padding(.bottom, Theme.Spacing.section)
            }
            .navigationDestination(for: String.self) { SpeciesDetailView(speciesId: $0) }
        }
    }
}

private struct SpeciesRow: View {
    @Environment(AppModel.self) private var app
    let species: SpeciesProfile

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(species.namePl).font(Theme.Typeface.bodyStrong)
                Text(species.nameLat).font(Theme.Typeface.captionMD).italic().foregroundStyle(Theme.Palette.mute)
            }
            Spacer()
            if app.species.hasOverrides(species.id) { Badge(text: "Zmienione") }
            Toggle("", isOn: Binding(get: { app.species.isEnabled(species.id) }, set: { app.species.setEnabled(species.id, $0) }))
                .labelsHidden()
                .tint(Theme.Palette.ink)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Palette.mute)
        }
        .padding(.vertical, Theme.Spacing.lg)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
    }
}

/// Field mode, notifications and on-demand calibration.
private struct SettingsSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var prefs = app.preferences
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: "Ustawienia")
            Toggle(isOn: $prefs.fieldMode) {
                setting("Tryb terenowy", "Jaśniejsze pasma, bez konturów wydzieleń, ekran nie gaśnie.")
            }
            .onChange(of: prefs.fieldMode) { app.redraw() }
            Toggle(isOn: Binding(get: { prefs.notificationsEnabled }, set: setNotifications)) {
                setting("Powiadomienia o wysypie", "Najwyżej jedno dziennie, liczone lokalnie.")
            }
            Button("Kalibruj teraz") {
                let count = app.calibrateAll()
                if count == 0 { app.toast = "Za mało obserwacji, by zmienić reguły" }
            }
            .buttonStyle(SecondaryPillStyle())
            Button("Odśwież pogodę") { Task { await app.refreshWeather(force: true) } }
                .buttonStyle(SecondaryPillStyle())
        }
        .tint(Theme.Palette.ink)
    }

    private func setting(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Typeface.bodyStrong)
            Text(detail).font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.mute)
        }
    }

    private func setNotifications(_ enabled: Bool) {
        app.preferences.notificationsEnabled = enabled
        guard enabled else { return }
        Task {
            if !(await app.services.notifications.requestPermission()) {
                app.preferences.notificationsEnabled = false
                app.toast = "Włącz powiadomienia w Ustawieniach iOS"
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                DisplayTitle(text: "O aplikacji", size: 56)
                Text("Apka podpowiada, gdzie szukać. Co zebrałeś, sprawdzasz sam.")
                    .font(Theme.Typeface.headingMD)
                Text("Indeks potencjału 0–100 liczony jest z jawnych reguł: partner drzewny, wiek drzewostanu, siedlisko, sezon, opad z opóźnieniem, temperatura gleby, przymrozki i Twoje obserwacje. To nie jest skalibrowana miara – pokazuje kierunek, nie pewność. Wszystko liczy się na telefonie, bez konta i serwera.")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.charcoal)
                SectionHeader(title: "Źródła danych")
                source("Bank Danych o Lasach", "Drzewostany i siedliska leśne (warstwy 66, 67, 20). Dane otwarte, © Lasy Państwowe.")
                source("Open-Meteo", "Pogoda i temperatura gleby. CC BY 4.0, użytek niekomercyjny.")
                source("OpenStreetMap / OpenFreeMap", "Podkład mapy. © współtwórcy OpenStreetMap, licencja ODbL.")
                source("MapLibre Native", "Silnik mapy. Licencja BSD-2.")
                source("GRDB.swift", "Baza SQLite. Licencja MIT.")
                source("Bebas Neue", "Krój nagłówków. SIL Open Font License.")
                Text("Apka nie identyfikuje grzybów. Zbieraj tylko to, co znasz na pewno.")
                    .font(Theme.Typeface.bodyStrong)
                    .foregroundStyle(Theme.Palette.signal)
            }
            .screenPadding()
            .padding(.bottom, Theme.Spacing.section)
        }
    }

    private func source(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Typeface.bodyStrong)
            Text(detail).font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.mute)
        }
    }
}
