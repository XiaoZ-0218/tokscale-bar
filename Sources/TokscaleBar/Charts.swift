import SwiftUI

/// Vertical bar chart for hourly or daily costs. Bars at `highlight` index use the brand gradient.
struct BarChart: View {
    let values: [Double]
    var highlight: Int? = nil
    var maxBarHeight: CGFloat = 60

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
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: values)
    }

    private func style(for index: Int) -> AnyShapeStyle {
        if index == highlight { return AnyShapeStyle(brandGradient) }
        return AnyShapeStyle(LinearGradient(
            colors: [Color.brandDeep.opacity(0.3), Color.brandDeep.opacity(0.13)],
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
            context.stroke(line, with: .color(.brand.opacity(0.22)), lineWidth: 5)
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
    var rate: Double = Defaults.usdToCnyRate

    var body: some View {
        let total = max(shares.reduce(0) { $0 + $1.cost }, 0.0001)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                        Rectangle()
                            .fill(Color.palette[index % Color.palette.count])
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
