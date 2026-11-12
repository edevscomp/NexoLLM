// Renders the Retina DMG installer background (660×420 pt @1x + 1320×840 px @2x multi-DPI TIFF).
//   swift scripts/make-dmg-background.swift <out.tiff> [preview.png] [version]
import AppKit

let args = CommandLine.arguments
let outTiff = args.count > 1 ? args[1] : "build/dmg-background.tiff"
let outPreview = args.count > 2 ? args[2] : nil
let version = args.count > 3 ? args[3] : "0.9.0"

let widthPt: CGFloat = 660
let heightPt: CGFloat = 420

func renderPNG(scale: CGFloat) -> Data {
    let pxW = Int(widthPt * scale)
    let pxH = Int(heightPt * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxW,
        pixelsHigh: pxH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: widthPt, height: heightPt)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let rect = NSRect(x: 0, y: 0, width: widthPt, height: heightPt)

    // 1. Deep Aurora Midnight base gradient
    let bgGrad = NSGradient(colors: [
        NSColor(srgbRed: 0.075, green: 0.082, blue: 0.125, alpha: 1.0),
        NSColor(srgbRed: 0.102, green: 0.114, blue: 0.176, alpha: 1.0),
        NSColor(srgbRed: 0.082, green: 0.090, blue: 0.141, alpha: 1.0),
    ], atLocations: [0.0, 0.52, 1.0], colorSpace: .sRGB)!
    bgGrad.draw(in: rect, angle: -35)

    // 2. Soft Aurora radial glows (top-left indigo-violet, bottom-right mint-cyan, center accent)
    func drawGlow(x: CGFloat, y: CGFloat, radius: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat, alpha: CGFloat) {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [
            CGColor(srgbRed: r, green: g, blue: b, alpha: alpha),
            CGColor(srgbRed: r, green: g, blue: b, alpha: 0.0),
        ] as CFArray
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
            cg.drawRadialGradient(
                grad,
                startCenter: CGPoint(x: x, y: y), startRadius: 0,
                endCenter: CGPoint(x: x, y: y), endRadius: radius,
                options: .drawsAfterEndLocation
            )
        }
    }

    drawGlow(x: 150, y: 340, radius: 290, r: 0.353, g: 0.420, b: 0.949, alpha: 0.24)
    drawGlow(x: 515, y: 120, radius: 260, r: 0.267, g: 0.784, b: 0.667, alpha: 0.15)
    drawGlow(x: 330, y: 215, radius: 190, r: 0.455, g: 0.396, b: 0.965, alpha: 0.14)

    // 3. Subtle dot-grid texture across the canvas
    NSColor.white.withAlphaComponent(0.025).setFill()
    stride(from: CGFloat(24), to: widthPt - 12, by: 24).forEach { gx in
        stride(from: CGFloat(24), to: heightPt - 12, by: 24).forEach { gy in
            NSBezierPath(ovalIn: NSRect(x: gx - 0.75, y: gy - 0.75, width: 1.5, height: 1.5)).fill()
        }
    }

    // 4. Header: Perfectly centered Mini NexoLLM squircle badge + Title + Subtitle
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 21, weight: .bold),
        .foregroundColor: NSColor.white,
        .kern: -0.3,
    ]
    let titleStr = NSString(string: "NexoLLM")
    let titleSize = titleStr.size(withAttributes: titleAttrs)
    let badgeSize: CGFloat = 30
    let headerGap: CGFloat = 10
    let headerTotalW = badgeSize + headerGap + titleSize.width
    let badgeX = (widthPt - headerTotalW) / 2
    let badgeY: CGFloat = 356

    let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeSize, height: badgeSize)
    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 7.5, yRadius: 7.5)
    NSGradient(
        starting: NSColor(srgbRed: 0.46, green: 0.53, blue: 1.0, alpha: 1.0),
        ending: NSColor(srgbRed: 0.29, green: 0.35, blue: 0.88, alpha: 1.0)
    )!.draw(in: badgePath, angle: -90)

    // Mini I-beam + ghost bars inside header badge
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: badgeX + 9.5, y: badgeY + 8, width: 2.2, height: 14), xRadius: 1.1, yRadius: 1.1).fill()
    NSBezierPath(roundedRect: NSRect(x: badgeX + 7.2, y: badgeY + 20.2, width: 6.8, height: 1.8), xRadius: 0.9, yRadius: 0.9).fill()
    NSBezierPath(roundedRect: NSRect(x: badgeX + 7.2, y: badgeY + 8, width: 6.8, height: 1.8), xRadius: 0.9, yRadius: 0.9).fill()
    NSColor.white.withAlphaComponent(0.48).setFill()
    NSBezierPath(roundedRect: NSRect(x: badgeX + 14.5, y: badgeY + 15.8, width: 10.5, height: 3.0), xRadius: 1.5, yRadius: 1.5).fill()
    NSColor.white.withAlphaComponent(0.30).setFill()
    NSBezierPath(roundedRect: NSRect(x: badgeX + 14.5, y: badgeY + 10.8, width: 7.2, height: 3.0), xRadius: 1.5, yRadius: 1.5).fill()

    titleStr.draw(at: NSPoint(x: badgeX + badgeSize + headerGap, y: badgeY + 2.5), withAttributes: titleAttrs)

    let subStyle = NSMutableParagraphStyle()
    subStyle.alignment = .center
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.72, green: 0.76, blue: 0.88, alpha: 0.88),
        .paragraphStyle: subStyle,
    ]
    NSString(string: "Drag NexoLLM to Applications to install")
        .draw(in: NSRect(x: 80, y: 320, width: widthPt - 160, height: 22), withAttributes: subAttrs)

    // 5. Frosted Glass Drop Zone Wells for NexoLLM.app (x=185) and Applications (x=475)
    // Finder icon positions: {185, 210} and {475, 210} from top -> y_appkit center ≈ 202
    func drawDropWell(centerX: CGFloat, centerY: CGFloat, accentBorder: Bool) {
        let w: CGFloat = 164
        let h: CGFloat = 176
        let r = NSRect(x: centerX - w / 2, y: centerY - h / 2, width: w, height: h)
        let path = NSBezierPath(roundedRect: r, xRadius: 24, yRadius: 24)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        NSColor(srgbRed: 0.14, green: 0.16, blue: 0.24, alpha: 0.72).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        let glassGrad = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.09),
            NSColor.white.withAlphaComponent(0.03),
        ])!
        glassGrad.draw(in: path, angle: -90)

        let strokeColor = accentBorder
            ? NSColor(srgbRed: 0.42, green: 0.49, blue: 0.98, alpha: 0.45)
            : NSColor.white.withAlphaComponent(0.14)
        strokeColor.setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }

    drawDropWell(centerX: 185, centerY: 202, accentBorder: true)
    drawDropWell(centerX: 475, centerY: 202, accentBorder: false)

    // 6. Center Connector Pill with triple glowing chevrons (x=330, y=206)
    let pillW: CGFloat = 78
    let pillH: CGFloat = 34
    let pillRect = NSRect(x: 330 - pillW / 2, y: 206 - pillH / 2, width: pillW, height: pillH)
    let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillH / 2, yRadius: pillH / 2)
    NSColor(srgbRed: 0.353, green: 0.420, blue: 0.949, alpha: 0.18).setFill()
    pillPath.fill()
    NSColor(srgbRed: 0.45, green: 0.52, blue: 1.0, alpha: 0.40).setStroke()
    pillPath.lineWidth = 1.0
    pillPath.stroke()

    let alphas: [CGFloat] = [0.42, 0.70, 1.0]
    let offsets: [CGFloat] = [-16, 0, 16]
    for (idx, dx) in offsets.enumerated() {
        let cx = 330 + dx
        let cy: CGFloat = 206
        let chev = NSBezierPath()
        chev.move(to: NSPoint(x: cx - 3.5, y: cy + 6.5))
        chev.line(to: NSPoint(x: cx + 3.5, y: cy))
        chev.line(to: NSPoint(x: cx - 3.5, y: cy - 6.5))
        chev.lineCapStyle = .round
        chev.lineJoinStyle = .round
        chev.lineWidth = 2.4
        NSColor(srgbRed: 0.62, green: 0.68, blue: 1.0, alpha: alphas[idx]).setStroke()
        chev.stroke()
    }

    // 7. Bottom Feature Pills with crisp vector status dots
    let pills: [(String, NSColor)] = [
        ("100% On-Device AI", NSColor(srgbRed: 0.48, green: 0.56, blue: 1.0, alpha: 1.0)),
        ("AES-256 Encrypted", NSColor(srgbRed: 0.36, green: 0.84, blue: 0.70, alpha: 1.0)),
        ("Ed25519 Signed · v\(version)", NSColor(srgbRed: 0.46, green: 0.78, blue: 0.98, alpha: 1.0)),
    ]

    let pillFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    let gap: CGFloat = 10
    var measured: [(String, NSColor, CGFloat)] = []
    for (label, dotColor) in pills {
        let sz = NSString(string: label).size(withAttributes: [.font: pillFont])
        measured.append((label, dotColor, sz.width + 32))
    }
    let totalW = measured.reduce(0) { $0 + $1.2 } + CGFloat(measured.count - 1) * gap
    var curX = (widthPt - totalW) / 2
    let pillY: CGFloat = 34

    for (label, tint, pw) in measured {
        let pr = NSRect(x: curX, y: pillY, width: pw, height: 24)
        let pp = NSBezierPath(roundedRect: pr, xRadius: 12, yRadius: 12)
        NSColor.white.withAlphaComponent(0.055).setFill()
        pp.fill()
        tint.withAlphaComponent(0.32).setStroke()
        pp.lineWidth = 0.9
        pp.stroke()

        tint.setFill()
        NSBezierPath(ovalIn: NSRect(x: curX + 10.5, y: pillY + 8.5, width: 7, height: 7)).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: pillFont,
            .foregroundColor: NSColor(srgbRed: 0.86, green: 0.89, blue: 0.96, alpha: 0.92),
        ]
        NSString(string: label).draw(at: NSPoint(x: curX + 22, y: pillY + 5), withAttributes: attrs)
        curX += pw + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let tmp1x = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nexo_dmg_1x.png")
let tmp2x = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nexo_dmg_2x.png")
let data1x = renderPNG(scale: 1.0)
let data2x = renderPNG(scale: 2.0)
try! data1x.write(to: tmp1x)
try! data2x.write(to: tmp2x)

if let outPreview {
    try? fm.createDirectory(at: URL(fileURLWithPath: outPreview).deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data2x.write(to: URL(fileURLWithPath: outPreview))
}

try? fm.createDirectory(at: URL(fileURLWithPath: outTiff).deletingLastPathComponent(), withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
p.arguments = ["-cathidpicheck", tmp1x.path, tmp2x.path, "-out", outTiff]
try! p.run()
p.waitUntilExit()
try? fm.removeItem(at: tmp1x)
try? fm.removeItem(at: tmp2x)
if p.terminationStatus != 0 {
    fputs("tiffutil failed\n", stderr)
    exit(1)
}
print("wrote \(outTiff)")
