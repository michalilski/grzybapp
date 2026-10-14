import SwiftUI
import GrzybEngine

/// Design tokens adapted from the Nike DESIGN.md: monochrome chrome, pill geometry, uppercase display type.
enum Theme {
    enum Palette {
        static let ink = Color(hex: 0x111111)
        static let canvas = Color.white
        static let softCloud = Color(hex: 0xF5F5F5)
        static let charcoal = Color(hex: 0x39393B)
        static let mute = Color(hex: 0x707072)
        static let stone = Color(hex: 0x9E9EA0)
        static let hairline = Color(hex: 0xCACACB)
        static let hairlineSoft = Color(hex: 0xE5E5E5)
        static let signal = Color(hex: 0xD30005)
        static let success = Color(hex: 0x007D48)
        static let info = Color(hex: 0x1151FF)
        static let forest = Color(hex: 0x0A7281)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 30
        static let section: CGFloat = 48
    }

    enum Radius {
        static let field: CGFloat = 24
        static let pill: CGFloat = 30
    }

    enum Typeface {
        static func display(_ size: CGFloat) -> Font {
            .custom("BebasNeue-Regular", size: size, relativeTo: .largeTitle)
        }

        static let headingXL = Font.system(size: 32, weight: .medium)
        static let headingLG = Font.system(size: 24, weight: .medium)
        static let headingMD = Font.system(size: 16, weight: .medium)
        static let body = Font.system(size: 16, weight: .regular)
        static let bodyStrong = Font.system(size: 16, weight: .medium)
        static let button = Font.system(size: 16, weight: .medium)
        static let captionMD = Font.system(size: 14, weight: .medium)
        static let captionSM = Font.system(size: 12, weight: .medium)
    }
}

/// Colors of the four potential bands; the low band is never drawn.
enum BandStyle {
    static func color(_ band: PotentialBand) -> Color {
        switch band {
        case .low: Theme.Palette.stone
        case .moderate: Color(hex: 0xF2C200)
        case .good: Color(hex: 0xFF6A00)
        case .veryGood: Theme.Palette.signal
        }
    }

    static func rgba(_ band: PotentialBand, fieldMode: Bool) -> (UInt8, UInt8, UInt8, UInt8)? {
        switch band {
        case .low: nil
        case .moderate: fieldMode ? (255, 214, 0, 255) : (242, 194, 0, 255)
        case .good: fieldMode ? (255, 120, 0, 255) : (255, 106, 0, 255)
        case .veryGood: fieldMode ? (255, 0, 20, 255) : (211, 0, 5, 255)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
