import AppKit

// Renders the TokscaleBar app icon (hand-drawn single-line bolt on a light
// superellipse plate) as a full .iconset, then iconutil packs the .icns.
// usage: swift scripts/render-icon.swift <output.icns>

let outIcns = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func canvas(_ file: String, points: CGFloat, scale: CGFloat, draw: (CGFloat) -> Void) {
    let px = points * scale
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(px)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])?
        .write(to: URL(fileURLWithPath: "\(iconset)/\(file)"))
}

// Apple icon plates are superellipses, not circular-arc roundrects.
func superellipse(in r: NSRect, n: CGFloat = 4.6) -> NSBezierPath {
    let path = NSBezierPath()
    let a = r.width / 2, cx = r.midX, cy = r.midY, e = 2.0 / n
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let p = NSPoint(x: cx + a * pow(abs(c), e) * (c >= 0 ? 1 : -1),
                        y: cy + a * pow(abs(s), e) * (s >= 0 ? 1 : -1))
        i == 0 ? path.move(to: p) : path.line(to: p)
    }
    path.close()
    return path
}

// Single-line bolt centerline; the wide flat jog is what reads "lightning".
let boltNorm = [(0.58, 1.0), (0.34, 0.54), (0.66, 0.57), (0.42, 0.0)]

func drawBolt(px: CGFloat, points: CGFloat) {
    let h = points * 500 / 1024
    let w = h * 0.62
    // a leaning bolt's visual centroid sits right of center; nudge left
    let box = NSRect(x: (points - w) / 2 - points * 0.008, y: (points - h) / 2,
                     width: w, height: h)
    // optical sizing: relative stroke grows as the point size shrinks
    let rel: CGFloat = points >= 256 ? 0.042 : points >= 128 ? 0.052
        : points >= 64 ? 0.062 : points >= 32 ? 0.070 : 0.082
    let b = NSBezierPath()
    for (i, np) in boltNorm.enumerated() {
        let p = NSPoint(x: (box.minX + CGFloat(np.0) * box.width) * (px / points),
                        y: (box.minY + CGFloat(np.1) * box.height) * (px / points))
        i == 0 ? b.move(to: p) : b.line(to: p)
    }
    b.lineWidth = px * rel
    b.lineCapStyle = .round
    b.lineJoinStyle = .round
    NSColor(white: 0.12, alpha: 1).setStroke()
    b.stroke()
}

func drawIcon(px: CGFloat, points: CGFloat) {
    let margin = px * 100 / 1024
    let plate = superellipse(in: NSRect(x: margin, y: margin,
                                        width: px - 2 * margin, height: px - 2 * margin))
    NSGradient(colors: [NSColor(white: 1.0, alpha: 1), NSColor(white: 0.916, alpha: 1)])?
        .draw(in: plate, angle: 90)
    drawBolt(px: px, points: points)
}

for pt in [16.0, 32.0, 128.0, 256.0, 512.0] as [CGFloat] {
    for scale in [1.0, 2.0] as [CGFloat] {
        let name = "icon_\(Int(pt))x\(Int(pt))\(scale == 2 ? "@2x" : "").png"
        canvas(name, points: pt, scale: scale) { px in drawIcon(px: px, points: pt) }
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", outIcns]
try! task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote \(outIcns)")
