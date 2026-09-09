import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static let brand = Color(hex: 0x30D158)
    static let brandDeep = Color(hex: 0x0E9F6E)
    /// Deep base of the hero gradient; reads as "forest", not "neon".
    static let brandInk = Color(hex: 0x07362A)

    /// Distinct palette for per-client breakdowns.
    static let palette: [Color] = [
        Color(hex: 0x30D158), Color(hex: 0x40C8E0), Color(hex: 0xFF9F0A),
        Color(hex: 0xBF5AF2), Color(hex: 0xFF375F), Color(hex: 0x64D2FF),
        Color(hex: 0x98989D),
    ]
}

let brandGradient = LinearGradient(
    colors: [Color.brand, Color.brandDeep],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

/// Hero gradient with real depth: dark ink base rising into brand green.
let heroGradient = LinearGradient(
    colors: [Color.brandDeep, Color.brandInk],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

/// The standard content card: a real surface (system control background)
/// + hairline edge, one corner radius. Hand-tuned primary-opacity fills
/// look muddy over the popover's vibrancy; semantic colors stay crisp.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

extension View {
    func card(radius: CGFloat = 14) -> some View { modifier(CardStyle(radius: radius)) }
}
