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

/// The standard content card. macOS 26+ gets real Liquid Glass; older systems
/// get a frosted fallback — a vibrancy-adjacent surface with a top edge
/// highlight that fakes the glass rim. Callers keep one modifier either way.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 14

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
                .background(Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.white.opacity(0.1), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: radius * 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .allowsHitTesting(false)
                }
        }
    }
}

extension View {
    func card(radius: CGFloat = 14) -> some View { modifier(CardStyle(radius: radius)) }
}
