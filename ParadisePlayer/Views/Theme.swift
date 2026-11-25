import SwiftUI
import UIKit

/// Design-System, angelehnt an paradisehunter.de:
/// fast schwarzer Hintergrund, cremeweiße Schrift, DM Sans für Titel,
/// Karten mit feiner Linie und 20 pt Radius, Pill-Buttons,
/// Neonverlauf aus dem Logo (Orange, Pink, Violett) als Akzent.
enum Theme {
    // MARK: Farben
    static let background = Color(hex: 0x111013)
    static let surface = Color(hex: 0xF2EFE4).opacity(0.05)
    static let surfaceRaised = Color(hex: 0xF2EFE4).opacity(0.09)
    static let border = Color(hex: 0xF2EFE4).opacity(0.14)

    static let text = Color(hex: 0xF2EFE4)
    static let textBody = Color(hex: 0xF2EFE4).opacity(0.76)
    static let textSecondary = Color(hex: 0xF2EFE4).opacity(0.5)

    static let neonOrange = Color(hex: 0xFF7A1A)
    static let neonPink = Color(hex: 0xF0287A)
    static let violet = Color(hex: 0x7646DD)
    static let cyan = Color(hex: 0x2096C9)
    static let danger = Color(hex: 0xD91842)
    static let star = Color(hex: 0xFFC23D)

    /// Verlauf aus dem Logo, für Wellenform und Akzente.
    static let neonGradient = LinearGradient(
        colors: [neonOrange, neonPink, violet],
        startPoint: .leading, endPoint: .trailing
    )

    // MARK: Maße
    static let radiusCard: CGFloat = 20
    static let radiusField: CGFloat = 12
    static let spacing: CGFloat = 16

    // MARK: Schrift
    /// DM Sans, falls im Projekt eingebunden (siehe README), sonst Systemschrift.
    static func title(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let candidates = weight == .regular
            ? ["DMSans-Regular", "DMSans-Regular_Medium", "DM Sans"]
            : ["DMSans-Medium", "DMSans-Regular_Medium", "DMSans-Regular", "DM Sans"]
        for name in candidates where UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Karte wie auf der Website: leicht abgesetzte Fläche, feine Linie, großer Radius.
struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.spacing
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = Theme.spacing) -> some View { modifier(CardStyle(padding: padding)) }
}

/// Runder Icon-Button im Stil der Website-Buttons.
struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 48
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(filled ? Theme.background : Theme.text)
            .frame(width: size, height: size)
            .background(Circle().fill(filled ? Theme.text : Theme.surfaceRaised))
            .overlay(Circle().strokeBorder(filled ? .clear : Theme.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Pill-Button wie "Contact" auf der Website.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.surfaceRaised
    var foreground: Color = Theme.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(Capsule().fill(tint))
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

nonisolated enum TimeFormat {
    static func string(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
