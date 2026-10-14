import SwiftUI

/// First-launch campaign screen with the safety disclaimer.
struct OnboardingView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Spacer()
            Text("GRZYBOWA MAPA")
                .font(Theme.Typeface.captionMD)
                .foregroundStyle(Theme.Palette.stone)
            Text("SZUKAJ\nTAM, GDZIE\nWARTO.")
                .font(Theme.Typeface.display(96))
                .foregroundStyle(Theme.Palette.canvas)
                .lineSpacing(-14)
            Text("Las, siedlisko, wiek drzewostanu i deszcz sprzed dwóch tygodni – zamienione w indeks potencjału 0–100 z wyjaśnieniem każdej oceny. Bez konta, bez serwera, działa offline.")
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Palette.stone)
            Text("Apka podpowiada, gdzie szukać. Co zebrałeś, sprawdzasz sam.")
                .font(Theme.Typeface.headingMD)
                .foregroundStyle(Theme.Palette.canvas)
            Button("Zaczynamy", action: onStart)
                .buttonStyle(PrimaryPillStyle(inverted: true))
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.Palette.ink.ignoresSafeArea())
    }
}
