// Renders the NexoLLM app icon: an accent squircle with a text cursor followed by ghost text.
//   swift scripts/make-icon.swift Resources/AppIcon.icns [preview.png]
import AppKit

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "Resources/AppIcon.icns"

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // macOS icon grid: 824 pt body centered in 1024, continuous corners.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186 * s, yRadius: 186 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(red: 0.35, green: 0.42, blue: 0.95, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Gentle top-to-bottom shading so the tile doesn't look flat at small sizes.
    NSGradient(starting: NSColor(red: 0.45, green: 0.52, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.28, green: 0.33, blue: 0.86, alpha: 1))!.draw(in: shape, angle: -90)

    // Text cursor (I-beam).
    NSColor.white.setFill()
    let cx = 352 * s, top = 700 * s, bottom = 324 * s, stem = 34 * s, serif = 120 * s, bar = 30 * s
    NSBezierPath(roundedRect: NSRect(x: cx - stem / 2, y: bottom, width: stem, height: top - bottom),
                 xRadius: stem / 2, yRadius: stem / 2).fill()
    for y in [top - bar, bottom] {
        NSBezierPath(roundedRect: NSRect(x: cx - serif / 2, y: y, width: serif, height: bar),
                     xRadius: bar / 2, yRadius: bar / 2).fill()
    }
    // Ghost text after the cursor: the suggestion.
    NSColor.white.withAlphaComponent(0.42).setFill()
    let h = 64 * s
    NSBezierPath(roundedRect: NSRect(x: 442 * s, y: 548 * s, width: 300 * s, height: h), xRadius: h / 2, yRadius: h / 2).fill()
    NSColor.white.withAlphaComponent(0.26).setFill()
    NSBezierPath(roundedRect: NSRect(x: 442 * s, y: 412 * s, width: 196 * s, height: h), xRadius: h / 2, yRadius: h / 2).fill()

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
if args.count > 2 { try! render(1024).write(to: URL(fileURLWithPath: args[2])) }
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", output]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(output)" : "iconutil failed")
