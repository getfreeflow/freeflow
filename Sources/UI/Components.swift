import SwiftUI

// MARK: - Button

/// Mirrors shadcn's button variants and size scale (h-8 / h-9 / h-10).
struct ShButtonStyle: ButtonStyle {

    enum Variant {
        case primary, secondary, outline, ghost, destructive
    }

    enum Size {
        case sm, md, lg

        var height: CGFloat {
            switch self {
            case .sm: return 28
            case .md: return 32
            case .lg: return 38
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .sm: return 10
            case .md: return 14
            case .lg: return 20
            }
        }

        var font: Font {
            switch self {
            case .sm: return Theme.Typography.captionMedium
            case .md, .lg: return Theme.Typography.bodyMedium
            }
        }
    }

    var variant: Variant = .primary
    var size: Size = .md
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonContent(configuration: configuration, variant: variant, size: size, fullWidth: fullWidth)
    }

    private struct ButtonContent: View {
        let configuration: ButtonStyleConfiguration
        let variant: Variant
        let size: Size
        let fullWidth: Bool

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(size.font)
                .padding(.horizontal, size.horizontalPadding)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: size.height)
                .foregroundStyle(foreground)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: variant == .outline ? 1 : 0)
                )
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .contentShape(Rectangle())
        }

        private var foreground: Color {
            switch variant {
            case .primary: return Theme.primaryForeground
            case .secondary: return Theme.secondaryForeground
            case .outline, .ghost: return Theme.foreground
            case .destructive: return .white
            }
        }

        private var background: some View {
            let pressed = configuration.isPressed
            let color: Color
            switch variant {
            case .primary: color = Theme.primary
            case .secondary: color = Theme.secondary
            case .outline: color = .clear
            case .ghost: color = pressed ? Theme.accent : .clear
            case .destructive: color = Theme.destructive
            }
            return color.opacity(pressed && variant != .ghost ? 0.85 : 1)
        }
    }
}

extension ButtonStyle where Self == ShButtonStyle {
    static var shPrimary: ShButtonStyle { ShButtonStyle(variant: .primary) }
    static var shSecondary: ShButtonStyle { ShButtonStyle(variant: .secondary) }
    static var shOutline: ShButtonStyle { ShButtonStyle(variant: .outline) }
    static var shGhost: ShButtonStyle { ShButtonStyle(variant: .ghost) }
}

// MARK: - Card

struct ShCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Badge

struct ShBadge: View {
    enum Tone { case neutral, success, warning, danger }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(Theme.Typography.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(foreground.opacity(0.12))
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Theme.mutedForeground
        case .success: return Theme.success
        case .warning: return Theme.warning
        case .danger: return Theme.destructive
        }
    }
}

// MARK: - Separator

struct ShSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }
}

// MARK: - Text field

struct ShTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(Theme.Typography.body)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.input, lineWidth: 1)
            )
    }
}

// MARK: - Section label

struct ShSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.caption)
            .tracking(0.6)
            .foregroundStyle(Theme.mutedForeground)
    }
}

// MARK: - Row used across Settings

struct ShSettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.md)
            control
        }
    }
}

// MARK: - Live level meter

/// Bars that react to mic input, so it's obvious at a glance that FreeFlow is
/// actually hearing you rather than silently recording nothing.
struct LevelMeter: View {
    let level: Float
    var barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(Theme.foreground.opacity(isActive(index) ? 0.9 : 0.18))
                    .frame(width: 3, height: height(for: index))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }

    private func isActive(_ index: Int) -> Bool {
        Float(index) / Float(barCount) < level
    }

    private func height(for index: Int) -> CGFloat {
        // Tallest in the middle, so it reads as a waveform rather than a bar chart.
        let distanceFromCenter = abs(Double(index) - Double(barCount - 1) / 2)
        let base = 8.0 + (Double(barCount) / 2 - distanceFromCenter) * 3
        let boost = isActive(index) ? Double(level) * 8 : 0
        return CGFloat(base + boost)
    }
}
