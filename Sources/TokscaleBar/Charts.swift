import SwiftUI

/// Vertical bar chart for hourly or daily costs. Bars at `highlight` index use
/// the brand gradient. `labels`/`details` (same count as `values`) feed the
/// hover tooltip: title line + pre-formatted value line. Callers format
/// strings because the chart stays currency/locale-agnostic.
struct BarChart: View {
    let values: [Double]
    var highlight: Int? = nil
    var maxBarHeight: CGFloat = 60
    var labels: [String] = []
    var details: [String] = []

    @State private var hovering: Int?

    var body: some View {
        let peak = max(values.max() ?? 0, 0.0001)
        let corner: CGFloat = values.count > 12 ? 2.5 : 4
        HStack(alignment: .bottom, spacing: values.count > 12 ? 3 : 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                UnevenRoundedRectangle(topLeadingRadius: corner, bottomLeadingRadius: 1,
                                       bottomTrailingRadius: 1, topTrailingRadius: corner,
                                       style: .continuous)
                    .fill(style(for: index))
                    .frame(height: 4 + maxBarHeight * max(value / peak, 0))
                    .frame(maxWidth: .infinity)
                    .shadow(color: index == highlight ? Color.brand.opacity(0.5) : .clear,
                            radius: 5, y: 1)
                    .opacity(hovering == nil || hovering == index ? 1 : 0.45)
                    .contentShape(Rectangle())
                    .onHover { hovering = $0 ? index : nil }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: values)
        .animation(.easeOut(duration: 0.1), value: hovering)
        .overlay(alignment: .top) { tooltip }
    }

    /// Floating readout above the hovered bar, clamped so it never clips the
    /// chart's left/right edge.
    @ViewBuilder
    private var tooltip: some View {
        if let index = hovering, values.indices.contains(index) {
            GeometryReader { geo in
                let barWidth = geo.size.width / CGFloat(max(values.count, 1))
                let centerX = barWidth * (CGFloat(index) + 0.5)
                VStack(spacing: 1) {
                    if labels.indices.contains(index) {
                        Text(labels[index])
                            .font(.system(size: 9, weight: .semibold))
                    }
                    if details.indices.contains(index) {
                        Text(details[index])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                .fixedSize()
                .position(x: min(max(centerX, 50), max(geo.size.width - 50, 50)), y: 12)
                .allowsHitTesting(false)
            }
            .transition(.opacity)
        }
    }

    private func style(for index: Int) -> AnyShapeStyle {
        // Hover promotes the touched bar to the brand gradient; the default
        // highlight (today/last) only applies when nothing is hovered.
        if index == hovering ?? highlight { return AnyShapeStyle(brandGradient) }
        return AnyShapeStyle(LinearGradient(
            colors: [Color.primary.opacity(0.2), Color.primary.opacity(0.1)],
            startPoint: .top, endPoint: .bottom
        ))
    }
}

/// One horizontal stacked capsule showing cost share per client, with a legend.
/// The legend renders one row per entry of `shares` and caps nothing itself —
/// callers are responsible for truncating (the dashboard passes top 5 + Other).
struct ClientShareView: View {
    let shares: [(client: String, cost: Double)]
    var currency: AppCurrency = .usd
    var rate: Double = Defaults.usdToCnyRate

    var body: some View {
        let total = max(shares.reduce(0) { $0 + $1.cost }, 0.0001)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        Rectangle()
                            .fill(Color.palette[index % Color.palette.count])
                            // Shaving a fixed 2pt off each segment's
                            // proportional width approximates a gap between
                            // neighbors so adjacent colors stay readable
                            // inside the capsule; the floor keeps tiny shares
                            // from collapsing to nothing.
                            .frame(width: max(geo.size.width * share.cost / total - 2, 4))
                    }
                }
                // Segments are square; the capsule clip owns the outer shape.
                .clipShape(Capsule())
            }
            .frame(height: 10)

            ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.palette[index % Color.palette.count])
                        .frame(width: 6, height: 6)
                    Text(share.client)
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text(Format.cost(share.cost, currency: currency, rate: rate))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(String(format: "%.0f%%", share.cost / total * 100))
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }
}
