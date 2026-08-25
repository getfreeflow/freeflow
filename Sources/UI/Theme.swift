import AppKit
import SwiftUI

/// shadcn/ui's design tokens, ported to native macOS.
///
/// The component library itself is React + Tailwind and can't be used in SwiftUI,
/// but its *tokens* transfer exactly: shadcn's oklch neutrals are Tailwind's neutral
/// scale, so each one has a precise sRGB equivalent. Colors are declared as dynamic
/// NSColors so the whole app follows the system appearance for free.
///
/// Reference: https://ui.shadcn.com/docs/theming
enum Theme {

    // MARK: - Semantic colors

    static let background      = dynamic(light: 0xFFFFFF, dark: 0x0A0A0A)
    static let foreground      = dynamic(light: 0x0A0A0A, dark: 0xFAFAFA)

    static let card            = dynamic(light: 0xFFFFFF, dark: 0x171717)
    static let cardForeground  = dynamic(light: 0x0A0A0A, dark: 0xFAFAFA)

    static let popover         = dynamic(light: 0xFFFFFF, dark: 0x171717)

    static let primary         = dynamic(light: 0x171717, dark: 0xEBEBEB)
    static let primaryForeground = dynamic(light: 0xFAFAFA, dark: 0x171717)

    static let secondary       = dynamic(light: 0xF5F5F5, dark: 0x262626)
    static let secondaryForeground = dynamic(light: 0x171717, dark: 0xFAFAFA)

    static let muted           = dynamic(light: 0xF5F5F5, dark: 0x262626)
    static let mutedForeground = dynamic(light: 0x737373, dark: 0xA3A3A3)

    static let accent          = dynamic(light: 0xF5F5F5, dark: 0x262626)

    static let destructive     = dynamic(light: 0xDC2626, dark: 0xEF4444)
    static let success         = dynamic(light: 0x16A34A, dark: 0x22C55E)
    static let warning         = dynamic(light: 0xD97706, dark: 0xF59E0B)

    static let border          = dynamic(light: 0xE5E5E5, dark: 0x2E2E2E)
    static let input           = dynamic(light: 0xE5E5E5, dark: 0x333333)
    static let ring            = dynamic(light: 0xA3A3A3, dark: 0x8E8E8E)

    // MARK: - Radius (shadcn --radius: 0.625rem = 10px)

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 10
        static let xl: CGFloat = 14
        static let pill: CGFloat = 999
    }

    // MARK: - Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Type scale

    enum Typography {
        static let title = Font.system(size: 20, weight: .semibold)
        static let heading = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let small = Font.system(size: 12, weight: .regular)
        static let caption = Font.system(size: 11, weight: .regular)
        static let captionMedium = Font.system(size: 11, weight: .medium)
        static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    }

    // MARK: - Helpers

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
