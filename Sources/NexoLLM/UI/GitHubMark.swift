import SwiftUI

/// The GitHub mark (Octicons `mark-github-16`, MIT, used to link to the project on GitHub), drawn from its
/// SVG path so it stays sharp at any size and takes the current foreground style.
struct GitHubMark: Shape {
    private static let d = "M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656"
    private static let unit = SVGPath.parse(d)

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 16
        return Self.unit.applying(CGAffineTransform(scaleX: s, y: s)
            .concatenating(CGAffineTransform(translationX: rect.midX - 8 * s, y: rect.midY - 8 * s)))
    }
}

/// Minimal SVG path-data parser (M L H V C S A Z, absolute and relative).
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens = tokenize(d)[...]
        var cur = CGPoint.zero, start = CGPoint.zero, lastCtrl: CGPoint?
        var cmd: Character = "M"
        func num() -> CGFloat { if case let .number(v)? = tokens.first { tokens.removeFirst(); return v }; return 0 }
        func flag() -> Bool { num() != 0 }
        while let t = tokens.first {
            if case let .command(c) = t { cmd = c; tokens.removeFirst() }
            let rel = cmd.isLowercase
            func pt() -> CGPoint { let x = num(), y = num(); return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }
            switch cmd.uppercased().first! {
            case "M":
                cur = pt(); start = cur; path.move(to: cur); lastCtrl = nil
                cmd = rel ? "l" : "L"   // further pairs are line-tos
            case "L": cur = pt(); path.addLine(to: cur); lastCtrl = nil
            case "H": let x = num(); cur.x = rel ? cur.x + x : x; path.addLine(to: cur); lastCtrl = nil
            case "V": let y = num(); cur.y = rel ? cur.y + y : y; path.addLine(to: cur); lastCtrl = nil
            case "C":
                let c1 = pt(), c2 = pt(), e = pt()
                path.addCurve(to: e, control1: c1, control2: c2); lastCtrl = c2; cur = e
            case "S":
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = pt(), e = pt()
                path.addCurve(to: e, control1: c1, control2: c2); lastCtrl = c2; cur = e
            case "A":
                let rx = num(), ry = num(), rot = num(), large = flag(), sweep = flag()
                let e = pt()
                arc(&path, from: cur, to: e, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                cur = e; lastCtrl = nil
            case "Z":
                path.closeSubpath(); cur = start; lastCtrl = nil
                if case .number? = tokens.first { tokens.removeFirst() }   // malformed: skip
            default:
                tokens.removeFirst()
            }
        }
        return path
    }

    private enum Token { case command(Character), number(CGFloat) }

    private static func tokenize(_ d: String) -> [Token] {
        var out: [Token] = []
        var numberText = ""
        func flush() { if let v = Double(numberText) { out.append(.number(CGFloat(v))) }; numberText = "" }
        for ch in d {
            if ch.isLetter, ch != "e" {
                flush(); out.append(.command(ch))
            } else if ch == "-" {
                if numberText.last == "e" { numberText.append(ch) } else { flush(); numberText = "-" }
            } else if ch == "." {
                if numberText.contains(".") && !numberText.contains("e") { flush() }
                numberText.append(ch)
            } else if ch.isNumber || ch == "e" {
                numberText.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    /// SVG elliptical arc as cubic Béziers (endpoint → center parameterization, SVG spec F.6.5).
    private static func arc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                            rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180, cphi = cos(phi), sphi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cphi * dx + sphi * dy, y1 = -sphi * dx + cphi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cphi * cx1 - sphi * cy1 + (p0.x + p1.x) / 2
        let cy = sphi * cx1 + cphi * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi } else if sweep, delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cphi - ry * sin(t) * sphi, y: cy + rx * cos(t) * sphi + ry * sin(t) * cphi)
        }
        func deriv(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cphi - ry * cos(t) * sphi, y: -rx * sin(t) * sphi + ry * cos(t) * cphi)
        }
        var t = theta1
        for _ in 0..<segments {
            let t2 = t + step
            let a = point(t), b = point(t2), da = deriv(t), db = deriv(t2)
            path.addCurve(to: b, control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                          control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
            t = t2
        }
    }
}
