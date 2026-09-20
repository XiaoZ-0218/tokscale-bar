import AppKit
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
/// Builds made with an SDK older than macOS 26 always take the frosted path.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 14

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // SwiftUI's `.glassEffect` renders its content invisible inside
            // this app's hosted popover/preview window (observed on macOS
            // 27.2), so the card background is the AppKit primitive instead.
            content
                .background(GlassCardBackground(cornerRadius: radius))
        } else {
            frosted(content)
        }
        #else
        frosted(content)
        #endif
    }

    private func frosted(_ content: Content) -> some View {
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

extension View {
    func card(radius: CGFloat = 14) -> some View { modifier(CardStyle(radius: radius)) }
}

/// AppKit-backed Liquid Glass card background. `NSGlassEffectView` is the
/// primitive SwiftUI's `glassEffect` wraps, but hosting it directly keeps the
/// card's content visible in this app (see CardStyle). Only compiled with the
/// Xcode 26 toolchain — the symbol doesn't exist in older SDKs, so availability
/// annotations alone don't save us there.
#if compiler(>=6.2)
@available(macOS 26.0, *)
struct GlassCardBackground: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
    }
}
#endif
