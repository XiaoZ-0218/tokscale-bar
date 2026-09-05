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

/// Vertical bar chart for hourly or daily costs. Bars at `highlight` index use the brand gradient.
struct BarChart: View {
    let values: [Double]
    var highlight: Int? = nil
    var maxBarHeight: CGFloat = 60

    var body: some View {
        let peak = max(values.max() ?? 0, 0.0001)
        HStack(alignment: .bottom, spacing: values.count > 12 ? 3 : 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: values.count > 12 ? 2 : 4, style: .continuous)
                    .fill(style(for: index))
                    .frame(height: 5 + maxBarHeight * max(value / peak, 0))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func style(for index: Int) -> AnyShapeStyle {
        if index == highlight { return AnyShapeStyle(brandGradient) }
        return AnyShapeStyle(LinearGradient(
            colors: [Color.brandDeep.opacity(0.34), Color.brandDeep.opacity(0.16)],
            startPoint: .top, endPoint: .bottom
        ))
    }
}

/// Smooth area+line chart for the month's daily costs.
struct AreaChart: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, size.width > 0, size.height > 0 else { return }
            let peak = max(values.max() ?? 0, 0.0001)
            let stepX = size.width / CGFloat(values.count - 1)
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * stepX,
                        y: size.height - 3 - (size.height - 8) * CGFloat(value / peak))
            }

            var line = Path()
            line.move(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1]
                let mid = CGPoint(x: (prev.x + points[i].x) / 2, y: (prev.y + points[i].y) / 2)
                line.addQuadCurve(to: mid, control: prev)
            }
            line.addLine(to: points[points.count - 1])

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [Color.brand.opacity(0.35), Color.brand.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))
            context.stroke(line, with: .color(.brand), lineWidth: 1.5)

            if let last = points.last {
                let dot = Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(.brand))
                context.stroke(dot, with: .color(.white), lineWidth: 1.5)
            }
        }
    }
}

/// One horizontal stacked capsule showing cost share per client, with a legend.
struct ClientShareView: View {
    let shares: [(client: String, cost: Double)]
    var currency: AppCurrency = .usd
    var rate: Double = 7.2

    var body: some View {
        let total = max(shares.reduce(0) { $0 + $1.cost }, 0.0001)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.palette[index % Color.palette.count])
                            .frame(width: max(geo.size.width * share.cost / total - 2, 4))
                    }
                }
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
