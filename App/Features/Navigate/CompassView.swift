import GrzybEngine
import SwiftUI

/// In-app compass: arrow to the target and distance, using GPS and heading only.
struct CompassView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let target: Coordinate

    var body: some View {
        let location = app.services.location
        VStack(spacing: Theme.Spacing.xl) {
            HStack {
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            Spacer()
            if let here = location.coordinate {
                let distance = here.distanceMeters(to: target)
                let rotation = here.bearingDegrees(to: target) - (location.headingDegrees ?? 0)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 160, weight: .bold))
                    .foregroundStyle(distance < 30 ? Theme.Palette.success : Theme.Palette.canvas)
                    .rotationEffect(.degrees(rotation))
                    .animation(.easeOut(duration: 0.2), value: rotation)
                Text(distanceText(distance))
                    .font(Theme.Typeface.display(120))
                    .foregroundStyle(Theme.Palette.canvas)
                Text(distance < 30 ? "JESTEŚ NA MIEJSCU" : "KIERUNEK \(Int(here.bearingDegrees(to: target)))°")
                    .font(Theme.Typeface.display(28))
                    .foregroundStyle(Theme.Palette.stone)
                if location.headingDegrees == nil {
                    Text("Brak kompasu – strzałka wskazuje względem północy.")
                        .font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.stone)
                }
            } else {
                DisplayTitle(text: "Szukam sygnału GPS…", size: 48, color: Theme.Palette.canvas)
            }
            Spacer()
            if let accuracy = location.accuracyM {
                Text("Dokładność GPS ±\(Int(accuracy)) m").font(Theme.Typeface.captionMD).foregroundStyle(Theme.Palette.stone)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.ink)
        .onAppear { location.startHeading() }
        .onDisappear { location.stopHeading() }
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1000 ? "\(PolishNumber.format(meters / 1000)) KM" : "\(Int(meters)) M"
    }
}
