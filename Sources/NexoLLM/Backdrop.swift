import AppKit
import ScreenCaptureKit

/// Is the text field under the caret light or dark? The ghost text has to contrast with the *page*,
/// not with the system appearance: a white web page in Safari while macOS is in dark mode made the
/// suggestion invisible.
///
/// Cost: one tiny capture (≈60×20 pt next to the caret, NexoLLM's own windows excluded) per text field,
/// off the main thread, only when a suggestion is shown in a field not measured in the last minute.
/// Needs Screen Recording; without it (or with screen reading set to Never) the ghost uses a neutral grey
/// that is readable on both light and dark pages.
final class Backdrop {
    static let shared = Backdrop()

    enum Tone: Equatable { case unknown, light, dark }

    private struct Sample { let tone: Tone; let date: Date }
    private var samples: [String: Sample] = [:]
    private var pending = Set<String>()

    /// Cached tone for a field; starts a measurement when missing/stale and calls `onChange` (main thread)
    /// if the measured tone differs from what was returned.
    func tone(for key: String, caretAX: CGRect, onChange: @escaping (Tone) -> Void) -> Tone {
        let cached = samples[key]
        if let cached, Date().timeIntervalSince(cached.date) < 60 { return cached.tone }
        guard Settings.shared.prefs.screenMode == .smart, CGPreflightScreenCaptureAccess(),
              pending.insert(key).inserted else { return cached?.tone ?? .unknown }
        let previous = cached?.tone ?? .unknown
        let rect = CGRect(x: caretAX.maxX + 3, y: caretAX.minY, width: 60, height: max(8, caretAX.height))
        Task.detached(priority: .utility) {
            let tone = await Backdrop.measure(rect)
            await MainActor.run {
                let b = Backdrop.shared
                b.pending.remove(key)
                guard tone != .unknown else { return }
                b.samples[key] = Sample(tone: tone, date: Date())
                if b.samples.count > 32 {
                    let old = b.samples.sorted { $0.value.date < $1.value.date }.prefix(8).map(\.key)
                    old.forEach { b.samples[$0] = nil }
                }
                if tone != previous { onChange(tone) }
            }
        }
        return previous
    }

    func removeAll() { samples = [:] }

    private static func measure(_ rect: CGRect) async -> Tone {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: rect.minX, y: rect.midY)) }) else { return .unknown }
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let local = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            .intersection(CGRect(origin: .zero, size: display.frame.size))
        guard local.width >= 4, local.height >= 4 else { return .unknown }
        config.sourceRect = local
        config.width = 24
        config.height = 8
        config.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return .unknown }
        return Self.tone(of: image)
    }

    /// Average relative luminance of a (small) image.
    static func tone(of image: CGImage) -> Tone {
        let w = 24, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .unknown }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
        }
        let mean = sum / Double(w * h) / 255
        return mean > 0.5 ? .light : .dark
    }
}
