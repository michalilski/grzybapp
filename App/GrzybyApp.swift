import GrzybEngine
import SwiftUI

@main
struct GrzybyApp: App {
    @State private var boot = AppBoot()

    var body: some Scene {
        WindowGroup {
            switch boot.result {
            case .success(let app):
                RootView().environment(app)
            case .failure(let error):
                Text("Nie udało się uruchomić: \(error.localizedDescription)").padding()
            }
        }
    }
}

@MainActor
struct AppBoot {
    let result: Result<AppModel, Error>

    init() {
        result = Result { AppModel(services: try AppServices()) }
    }
}

enum RootTab: Hashable {
    case map, journal, regions, species
}

/// Tab shell; hosts global sheets (observation form, compass) and toasts.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: RootTab = .map

    var body: some View {
        @Bindable var app = app
        Group {
            if app.preferences.onboardingDone {
                tabs
            } else {
                OnboardingView { app.preferences.onboardingDone = true }
            }
        }
        .tint(Theme.Palette.ink)
        .sheet(item: $app.draft) { AddObservationView(draft: $0) }
        .fullScreenCover(item: Binding(
            get: { app.navigationTarget.map(NavigationTarget.init) },
            set: { app.navigationTarget = $0?.coordinate }
        )) { CompassView(target: $0.coordinate) }
        .overlay(alignment: .bottom) { toast }
        .onAppear {
            app.start()
            applyIdleTimer()
            #if DEBUG
            applyDemoTab()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.refreshWeather() } }
        }
        .onChange(of: app.preferences.fieldMode) { applyIdleTimer() }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            MapScreen(tab: $tab)
                .tabItem { Label("Mapa", systemImage: "map") }
                .tag(RootTab.map)
            JournalView()
                .tabItem { Label("Dziennik", systemImage: "book.closed") }
                .tag(RootTab.journal)
            RegionsView()
                .tabItem { Label("Regiony", systemImage: "square.dashed") }
                .tag(RootTab.regions)
            SpeciesListView()
                .tabItem { Label("Gatunki", systemImage: "leaf") }
                .tag(RootTab.species)
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let text = app.toast {
            Toast(text: text)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(3.5))
                    withAnimation { app.toast = nil }
                }
                .onTapGesture { app.toast = nil }
        }
    }

    #if DEBUG
    private func applyDemoTab() {
        switch ProcessInfo.processInfo.environment["DEMO_TAB"] {
        case "journal": tab = .journal
        case "regions": tab = .regions
        case "species": tab = .species
        default: break
        }
    }
    #endif

    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = app.preferences.fieldMode
    }
}

private struct NavigationTarget: Identifiable {
    let coordinate: Coordinate
    var id: String { "\(coordinate.lat),\(coordinate.lon)" }
}
