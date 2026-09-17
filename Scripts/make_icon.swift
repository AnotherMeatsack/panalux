// Renders Packaging/AppIcon.icns. Run: swift Scripts/make_icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// Apple icon grid: 824pt body centered in 1024 with a continuous corner.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
NSColor(calibratedWhite: 0.1, alpha: 1).setFill()
shape.fill()
ctx.restoreGState()

shape.addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.075, blue: 0.09, alpha: 1)
])!.draw(in: body, angle: -90)

// Top sheen.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), .clear])!
    .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

// Knob row.
let knobY: CGFloat = 690
for i in 0..<6 {
    let x = 222 + CGFloat(i) * 116
    let r: CGFloat = 34
    let knob = NSBezierPath(ovalIn: CGRect(x: x - r, y: knobY - r, width: r * 2, height: r * 2))
    NSGradient(colors: [NSColor(calibratedWhite: 0.36, alpha: 1), NSColor(calibratedWhite: 0.14, alpha: 1)])!
        .draw(in: knob, angle: -90)
    NSColor(calibratedWhite: 0.0, alpha: 0.6).setStroke()
    knob.lineWidth = 3
    knob.stroke()
    let tick = NSBezierPath()
    tick.move(to: CGPoint(x: x, y: knobY + 6))
    tick.line(to: CGPoint(x: x, y: knobY + r - 6))
    tick.lineWidth = 7
    tick.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.85).setStroke()
    tick.stroke()
}

// Three trackballs with colored rings — lift, gamma, gain.
let accents: [NSColor] = [
    NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.20, alpha: 1),
    NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.35, alpha: 1),
    NSColor(calibratedRed: 0.32, green: 0.70, blue: 1.00, alpha: 1)
]
let ballY: CGFloat = 400
for (i, accent) in accents.enumerated() {
    let cx = 282 + CGFloat(i) * 230
    let ringR: CGFloat = 104
    let ring = NSBezierPath(ovalIn: CGRect(x: cx - ringR, y: ballY - ringR, width: ringR * 2, height: ringR * 2))
    NSGradient(colors: [NSColor(calibratedWhite: 0.30, alpha: 1), NSColor(calibratedWhite: 0.10, alpha: 1)])!
        .draw(in: ring, angle: -90)

    let arc = NSBezierPath()
    arc.appendArc(withCenter: CGPoint(x: cx, y: ballY), radius: ringR - 10, startAngle: 200, endAngle: 340 + CGFloat(i) * 40, clockwise: false)
    arc.lineWidth = 12
    arc.lineCapStyle = .round
    accent.setStroke()
    arc.stroke()

    let ballR: CGFloat = 70
    let ball = NSBezierPath(ovalIn: CGRect(x: cx - ballR, y: ballY - ballR, width: ballR * 2, height: ballR * 2))
    NSGradient(colors: [
        NSColor(calibratedWhite: 0.32, alpha: 1),
        NSColor(calibratedWhite: 0.03, alpha: 1)
    ])!.draw(in: ball, relativeCenterPosition: NSPoint(x: -0.35, y: 0.45))
    let glint = NSBezierPath(ovalIn: CGRect(x: cx - 38, y: ballY + 18, width: 34, height: 22))
    NSColor.white.withAlphaComponent(0.55).setFill()
    glint.fill()
}

// Status pill — the notch readout.
let pill = NSBezierPath(roundedRect: CGRect(x: 342, y: 176, width: 340, height: 64), xRadius: 32, yRadius: 32)
NSColor.white.withAlphaComponent(0.12).setFill()
pill.fill()
let fill = NSBezierPath(roundedRect: CGRect(x: 362, y: 200, width: 190, height: 16), xRadius: 8, yRadius: 8)
accents[0].setFill()
fill.fill()

image.unlockFocus()

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("Packaging/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func write(_ px: Int, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}

for base in [16, 32, 128, 256, 512] {
    write(base, "icon_\(base)x\(base).png")
    write(base * 2, "icon_\(base)x\(base)@2x.png")
}
write(1024, "../AppIcon-1024.png")
print("Wrote \(iconset.path)")
