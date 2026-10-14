import SwiftUI
import GrzybEngine

/// Black pill CTA – the single primary action per screen.
struct PrimaryPillStyle: ButtonStyle {
    var inverted = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.button)
            .foregroundStyle(inverted ? Theme.Palette.ink : Theme.Palette.canvas)
            .padding(.horizontal, 32)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(inverted ? Theme.Palette.canvas : Theme.Palette.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Soft-cloud pill for the secondary action next to a primary one.
struct SecondaryPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.button)
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, 32)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(Theme.Palette.softCloud, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 44pt circular icon control on soft cloud or canvas.
struct CircleIconButton: View {
    let systemName: String
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? Theme.Palette.canvas : Theme.Palette.ink)
                .frame(width: 44, height: 44)
                .background(filled ? Theme.Palette.ink : Theme.Palette.canvas, in: Circle())
                .overlay(Circle().stroke(Theme.Palette.hairlineSoft, lineWidth: filled ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Filter chip that flips to inverted ink when selected.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var dot: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                Text(title)
                    .font(Theme.Typeface.captionMD)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.Palette.canvas : Theme.Palette.ink)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(isSelected ? Theme.Palette.ink : Theme.Palette.canvas, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? .clear : Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Uppercase display headline in Bebas Neue.
struct DisplayTitle: View {
    let text: String
    var size: CGFloat = 48
    var color: Color = Theme.Palette.ink

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typeface.display(size))
            .foregroundStyle(color)
            .lineSpacing(-size * 0.1)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Section header with hairline below, as in Nike disclosure rows.
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(Theme.Typeface.display(26))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(Theme.Typeface.captionMD)
                        .foregroundStyle(Theme.Palette.mute)
                }
            }
            Hairline()
        }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.Palette.hairlineSoft).frame(height: 1)
    }
}

/// Small pill badge with hairline border.
struct Badge: View {
    let text: String
    var inverted = false

    var body: some View {
        Text(text)
            .font(Theme.Typeface.captionSM)
            .foregroundStyle(inverted ? Theme.Palette.canvas : Theme.Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(inverted ? Theme.Palette.ink : Theme.Palette.canvas, in: Capsule())
            .overlay(Capsule().stroke(inverted ? .clear : Theme.Palette.hairline, lineWidth: 1))
    }
}

/// Score readout: huge Bebas number with band label.
struct ScoreBadge: View {
    let score: Double
    let band: PotentialBand
    var size: CGFloat = 56

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(PolishNumber.integer(score))
                .font(Theme.Typeface.display(size))
                .foregroundStyle(Theme.Palette.ink)
            HStack(spacing: 4) {
                Circle().fill(BandStyle.color(band)).frame(width: 8, height: 8)
                Text(band.label.uppercased())
                    .font(Theme.Typeface.captionSM)
                    .foregroundStyle(Theme.Palette.mute)
            }
        }
    }
}

/// Horizontal bar 0–1 used for multipliers.
struct ValueBar: View {
    let label: String
    let value: Double
    var highlighted = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(label)
                .font(Theme.Typeface.captionMD)
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.softCloud)
                    Capsule().fill(highlighted ? Theme.Palette.signal : Theme.Palette.ink)
                        .frame(width: max(4, geo.size.width * value))
                }
            }
            .frame(height: 8)
            Text(PolishNumber.format(value))
                .font(Theme.Typeface.captionSM.monospacedDigit())
                .foregroundStyle(Theme.Palette.mute)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

/// Uppercase metadata label above a value.
struct MetaItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.Typeface.captionSM)
                .foregroundStyle(Theme.Palette.mute)
            Text(value)
                .font(Theme.Typeface.bodyStrong)
                .foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Transient ink banner at the bottom of the screen.
struct Toast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typeface.captionMD)
            .foregroundStyle(Theme.Palette.canvas)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Palette.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
            .padding(.horizontal, Theme.Spacing.lg)
    }
}

extension View {
    func screenPadding() -> some View {
        padding(.horizontal, Theme.Spacing.lg)
    }
}
