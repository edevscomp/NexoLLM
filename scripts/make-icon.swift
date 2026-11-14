// Renders the NexoLLM app icon (squircle + minimalist vector mark).
//   swift scripts/make-icon.swift [Resources/AppIcon.icns] [preview.png] [--variant a|b|ab]
import AppKit

let args = CommandLine.arguments
let variant: String = {
    if let idx = args.firstIndex(of: "--variant"), idx + 1 < args.count { return args[idx + 1] }
    return "ab"
}()
let positional = Array(args.dropFirst()).enumerated().compactMap { i, a -> String? in
    if a == "--variant" { return nil }
    if i > 0 && args[i] == "--variant" { return nil }
    return a
}
let output = positional.first ?? "Resources/AppIcon.icns"
let preview = positional.count > 1 ? positional[1] : nil

func drawTiltedCapsule(center: CGPoint, width: CGFloat, height: CGFloat, angleDeg: CGFloat, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let xform = NSAffineTransform()
    xform.translateX(by: center.x, yBy: center.y)
    xform.rotate(byDegrees: -angleDeg)
    xform.concat()
    color.setFill()
    let rect = NSRect(x: -width / 2, y: -height / 2, width: width, height: height)
    NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawDot(center: CGPoint, diameter: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)).fill()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186 * s, yRadius: 186 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.36)
    shadow.shadowBlurRadius = 26 * s
    shadow.shadowOffset = NSSize(width: 0, height: -11 * s)
    shadow.set()
    NSColor(red: 0.12, green: 0.14, blue: 0.28, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(red: 0.27, green: 0.33, blue: 0.88, alpha: 1),
        NSColor(red: 0.14, green: 0.17, blue: 0.52, alpha: 1),
        NSColor(red: 0.09, green: 0.10, blue: 0.28, alpha: 1)
    ], atLocations: [0.0, 0.58, 1.0], colorSpace: .deviceRGB)!.draw(in: shape, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3 * s, dy: 3 * s), xRadius: 183 * s, yRadius: 183 * s)
    rim.lineWidth = 6 * s
    NSColor.white.withAlphaComponent(0.16).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    switch variant {
    case "a":
        drawTiltedCapsule(center: p(330, 512), width: 68 * s, height: 408 * s, angleDeg: 0, color: .white)
        for (x, a) in [(480, 0.92), (608, 0.54), (736, 0.25)] as [(CGFloat, CGFloat)] {
            drawDot(center: p(x, 594), diameter: 84 * s, color: NSColor.white.withAlphaComponent(a))
        }
        for (x, a) in [(480, 0.68), (608, 0.34)] as [(CGFloat, CGFloat)] {
            drawDot(center: p(x, 430), diameter: 84 * s, color: NSColor.white.withAlphaComponent(a))
        }
    case "b":
        drawTiltedCapsule(center: p(426, 512), width: 86 * s, height: 430 * s, angleDeg: 16, color: .white)
        drawTiltedCapsule(center: p(608, 492), width: 86 * s, height: 326 * s, angleDeg: 16, color: NSColor.white.withAlphaComponent(0.42))
    default: // "ab"
        let angle: CGFloat = 15
        let tanA = tan(angle * .pi / 180)
        drawTiltedCapsule(center: p(336, 512), width: 72 * s, height: 420 * s, angleDeg: angle, color: .white)
        let topShift = (592 - 512) * tanA, botShift = (432 - 512) * tanA
        for (x, a) in [(484, 0.92), (610, 0.54), (736, 0.25)] as [(CGFloat, CGFloat)] {
            drawDot(center: p(x + topShift, 592), diameter: 82 * s, color: NSColor.white.withAlphaComponent(a))
        }
        for (x, a) in [(484, 0.68), (610, 0.34)] as [(CGFloat, CGFloat)] {
            drawDot(center: p(x + botShift, 432), diameter: 82 * s, color: NSColor.white.withAlphaComponent(a))
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if let preview { try! render(1024).write(to: URL(fileURLWithPath: preview)) }
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", output]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(output) (variant: \(variant))" : "iconutil failed")
