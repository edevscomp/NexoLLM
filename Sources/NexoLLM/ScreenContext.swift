import AppKit
import Vision
import ScreenCaptureKit

/// On-demand, local-only screen context: screenshot of the frontmost window -> Vision OCR -> the lines
/// most relevant to where you're typing. Only the extracted text is kept (≈1 KB per window, in memory);
/// the image is released right after OCR. Nothing is stored on disk or sent anywhere.
///
/// There is no timer: a capture is only ever considered while the user is writing, and only when
/// `reason(...)` says the cached text is missing or no longer describes what's on screen.
final class ScreenContext: ObservableObject {
    static let shared = ScreenContext()
    @Published private(set) var latestText: String = ""
    @Published private(set) var lastCapturedAt: Date? = nil
    @Published private(set) var isCapturing: Bool = false

    /// Policy knobs. Battery values capture less often.
    struct Tunables {
        /// Global floor between two captures, whatever happens (app switching, many fields…).
        var cooldown: TimeInterval
        /// Coming back to a field: its cached text is reused if younger than this.
        var reuseWindow: TimeInterval
        /// Drift: caret moved this many characters since the capture (typed a lot, or jumped elsewhere)…
        var driftChars: Int
        /// …or this many points vertically (scrolled to another part of the document)…
        var driftPoints: CGFloat
        /// …and the user has paused typing at least this long. Never captures mid-burst.
        var driftPause: TimeInterval

        static let pluggedIn = Tunables(cooldown: 10, reuseWindow: 120, driftChars: 300, driftPoints: 250, driftPause: 2.5)
        static let battery = Tunables(cooldown: 20, reuseWindow: 240, driftChars: 450, driftPoints: 350, driftPause: 3.5)
        static var current: Tunables { Power.onBattery ? battery : pluggedIn }
    }

    struct Snapshot {
        let text: String
        let date: Date
        /// Caret position (UTF-16 offset) and vertical position when the capture was taken.
        let caret: Int
        let caretY: CGFloat
        /// Taken because the user asked (capture shortcut): kept longer, and given more room in the prompt.
        var manual = false
    }

    enum Reason: String {
        case firstLook = "first look"   // nothing cached for this field yet
        case wake                       // first keystroke after an idle period
        case revisit                    // back to a field whose snapshot is old
        case drift                      // wrote a lot / moved far, now pausing
        case manual                     // the user pressed the capture shortcut
    }

    /// Fields with a cached snapshot, most recent last. Text only, bounded.
    private var snapshots: [String: Snapshot] = [:]
    private var order: [String] = []
    /// Last manual capture per app: lends its context to any field of that app for a few minutes
    /// (e.g. captured while reading, then started typing in another field).
    private var pinned: [pid_t: Snapshot] = [:]
    /// How long manual captures stay valid.
    static let manualLifetime: TimeInterval = 600
    private let maxEntries = 8
    private var lastCapture = Date.distantPast
    /// A capture started or ended (the menu bar icon shows when the screen is being read).
    var onStateChange: (() -> Void)?
    /// A capture that never returns (ScreenCaptureKit can hang after sleep) is abandoned after 8 s.
    private var inFlightSince: Date?
    var inFlight: Bool {
        guard let since = inFlightSince else { return false }
        if Date().timeIntervalSince(since) > 8 {
            Log.info("screen: capture timed out — abandoned")
            inFlightSince = nil
            DispatchQueue.main.async { ScreenContext.shared.onStateChange?() }
            return false
        }
        return true
    }

    func snapshot(_ key: String) -> Snapshot? { snapshots[key] }

    /// The newest screen text held in memory (Privacy Inspector).
    var latestPreview: Snapshot? { Self.newest(Array(snapshots.values) + Array(pinned.values)) }

    static func newest(_ all: [Snapshot]) -> Snapshot? {
        all.filter { !$0.text.isEmpty }.max { $0.date < $1.date }
    }

    /// Cached text for a field (nil if none or empty).
    func text(for key: String) -> String? {
        guard let t = snapshots[key]?.text, !t.isEmpty else { return nil }
        return t
    }

    /// Seconds before another capture is allowed (0 = now).
    func cooldownRemaining(_ t: Tunables = .current, now: Date = Date()) -> TimeInterval {
        max(0, t.cooldown - now.timeIntervalSince(lastCapture))
    }

    /// Manual capture of an app, if recent enough.
    func pinned(pid: pid_t, now: Date = Date()) -> Snapshot? {
        guard let s = pinned[pid], now.timeIntervalSince(s.date) < Self.manualLifetime, !s.text.isEmpty else { return nil }
        return s
    }

    /// Drops snapshots older than `age` (called when the app goes idle). Manual ones live longer.
    func prune(olderThan age: TimeInterval) {
        let now = Date()
        for (k, s) in snapshots where now.timeIntervalSince(s.date) > (s.manual ? max(age, Self.manualLifetime) : age) {
            snapshots[k] = nil
        }
        order.removeAll { snapshots[$0] == nil }
        pinned = pinned.filter { now.timeIntervalSince($0.value.date) < Self.manualLifetime }
    }

    func removeAll() {
        snapshots = [:]
        order = []
        pinned = [:]
        latestText = ""
        lastCapturedAt = nil
    }

    /// Triggers an immediate full-screen OCR scan from the Settings UI monitor box.
    func captureNowForMonitor() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? ProcessInfo.processInfo.processIdentifier
        let center = NSScreen.main.map { CGRect(x: $0.frame.midX, y: $0.frame.midY, width: 1, height: 18) }
            ?? CGRect(x: 600, y: 400, width: 1, height: 18)
        _ = capture(key: "monitor:\(pid)", pid: pid, fieldAX: nil, caretAX: center, caret: -1, reason: .manual) { _, _ in }
    }

    /// Text held in memory, for Settings → Clear Cache.
    var bytes: Int { (snapshots.values.map(\.text) + pinned.values.map(\.text)).reduce(0) { $0 + $1.utf8.count } }

    // MARK: Policy (pure, unit-tested)

    static func drifted(_ s: Snapshot, caret: Int, caretY: CGFloat, _ t: Tunables) -> Bool {
        abs(caret - s.caret) >= t.driftChars || abs(caretY - s.caretY) >= t.driftPoints
    }

    /// Why a new capture is needed for this field, or nil if the cached text is still good.
    /// - Parameters:
    ///   - wokeAt: start of the current writing burst (first keystroke after being idle).
    ///   - revisit: the user just came (back) to this field from another one.
    ///   - atPause: the user has paused typing (drift is only acted upon during pauses).
    static func reason(snapshot: Snapshot?, now: Date, caret: Int, caretY: CGFloat, wokeAt: Date?,
                       revisit: Bool, atPause: Bool, _ t: Tunables) -> Reason? {
        guard let s = snapshot else { return .firstLook }
        if let w = wokeAt, s.date < w { return .wake }
        if revisit, now.timeIntervalSince(s.date) > t.reuseWindow { return .revisit }
        if atPause, drifted(s, caret: caret, caretY: caretY, t) { return .drift }
        return nil
    }

    // MARK: Capture

    /// Starts a capture unless one is running or the global cooldown hasn't elapsed (returns false then).
    /// `onDone(text, changed)` always runs on the main thread; `changed` is false when the text is close to
    /// the field's previous snapshot, so an unchanged screen never invalidates the model's prompt cache.
    /// Manual captures (the user asked) skip the cooldown, read more of the window and use accurate OCR.
    /// `fieldAX == nil && caret < 0` means "no text field": the whole window is read.
    @discardableResult
    func capture(key: String, pid: pid_t, fieldAX: CGRect?, caretAX: CGRect, caret: Int, reason: Reason,
                 onDone: @escaping (_ text: String, _ changed: Bool) -> Void) -> Bool {
        let manual = reason == .manual
        guard !inFlight, manual || cooldownRemaining() <= 0, CGPreflightScreenCaptureAccess() else { return false }
        let started = Date()
        inFlightSince = started
        isCapturing = true
        lastCapture = started   // failures count too: never retry in a tight loop
        onStateChange?()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let fast = Power.onBattery && !manual
        Task.detached(priority: manual ? .userInitiated : .utility) {
            let text = await ScreenContext.capture(pid: pid, fieldAX: fieldAX, caretAX: caretAX, scale: scale, fast: fast,
                                                   wide: manual)
            await MainActor.run {
                let sc = ScreenContext.shared   // singleton: no capture of `self` across the detached task
                sc.isCapturing = false
                if sc.inFlightSince == started { sc.inFlightSince = nil; sc.onStateChange?() }
                let previous = sc.snapshots[key]
                // Failed/blank capture: remember it anyway so we don't retry on every keystroke.
                let new = Snapshot(text: text ?? "", date: Date(), caret: caret, caretY: caretAX.midY, manual: manual)
                sc.store(key, new)
                if manual, !new.text.isEmpty { sc.pinned[pid] = new }
                if !new.text.isEmpty {
                    sc.latestText = new.text
                    sc.lastCapturedAt = new.date
                }
                let changed = previous.map { ScreenContext.similarity($0.text, new.text) < 0.85 } ?? !new.text.isEmpty
                Log.write(String(format: "screen: %@ → %d chars in %.0fms%@", reason.rawValue, new.text.count,
                                 Date().timeIntervalSince(started) * 1000, text == nil ? " (failed)" : changed ? " (changed)" : " (same)"))
                if CommandLine.arguments.contains("--probe"), let text {
                    Log.write("screen sample [\(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?")]: \(String(reflecting: String(text.prefix(300))))")
                }
                onDone(new.text, changed)
            }
        }
        return true
    }

    private func store(_ key: String, _ s: Snapshot) {
        if snapshots[key] != nil { order.removeAll { $0 == key } }
        snapshots[key] = s
        order.append(key)
        while order.count > maxEntries { snapshots[order.removeFirst()] = nil }
        if !s.text.isEmpty {
            latestText = s.text
            lastCapturedAt = s.date
        }
    }

    // MARK: Capture + OCR

    private static func capture(pid: pid_t, fieldAX: CGRect?, caretAX: CGRect, scale: CGFloat, fast: Bool,
                                wide: Bool = false) async -> String? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let nexoWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
            let caretPoint = CGPoint(x: caretAX.midX, y: caretAX.midY)

            // Capture the entire active display (excluding NexoLLM's own overlays) so all visible windows
            // (e.g. a book/PDF, Obsidian, WhatsApp, TextEdit, browsers) are read together across the screen.
            if let display = content.displays.first(where: { $0.frame.contains(caretPoint) }) ?? content.displays.first {
                let dFrame = display.frame
                let config = SCStreamConfiguration()
                config.width = Int(dFrame.width * min(scale, 2))
                config.height = Int(dFrame.height * min(scale, 2))
                config.showsCursor = false
                let filter = SCContentFilter(display: display, excludingWindows: nexoWindows)
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                    let lines = try recognizeLines(in: image, frame: dFrame, fast: false)
                    return select(lines, fieldAX: fieldAX, caretAX: caretAX, budget: wide ? 6000 : 4200)
                }
            }

            // Fallback to single-window capture if display capture is unavailable.
            let owned = content.windows.filter { $0.owningApplication?.processID == pid && $0.frame.width > 150 && $0.frame.height > 80 }
            let normal = owned.filter { $0.isOnScreen && $0.windowLayer == 0 }
            let candidates = normal.isEmpty ? owned : normal
            guard let window = candidates.first(where: { $0.frame.contains(caretPoint) })
                    ?? candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                return nil
            }
            let win = window.frame
            let config = SCStreamConfiguration()
            config.width = Int(win.width * scale)
            config.height = Int(win.height * scale)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                   configuration: config)
            let lines = try recognizeLines(in: image, frame: win, fast: fast)
            return select(lines, fieldAX: fieldAX, caretAX: caretAX, budget: wide ? 6000 : 4200)
        } catch {
            Log.write("screen: error \(error.localizedDescription)")
            return nil
        }
    }

    /// OCR of an arbitrary screen region (used by the interactive drag-to-select Web Lookup overlay).
    static func recognizeRegion(_ rectAX: CGRect) async -> String? {
        guard rectAX.width > 10, rectAX.height > 8, CGPreflightScreenCaptureAccess() else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            // Exclude only floating overlay panels (`windowLayer != 0`), keeping normal windows (like NexoLLM Settings) visible.
            let overlayWindows = content.windows.filter { $0.owningApplication?.processID == ownPID && $0.windowLayer != 0 }
            let center = CGPoint(x: rectAX.midX, y: rectAX.midY)
            guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else { return nil }
            let dFrame = display.frame
            let padded = rectAX.insetBy(dx: -8, dy: -6)
            let minX = max(0, padded.minX - dFrame.minX)
            let minY = max(0, padded.minY - dFrame.minY)
            let maxX = min(dFrame.width, padded.maxX - dFrame.minX)
            let maxY = min(dFrame.height, padded.maxY - dFrame.minY)
            let local = CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
            guard local.width > 8, local.height > 8 else { return nil }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let config = SCStreamConfiguration()
            config.sourceRect = local
            config.width = max(16, Int(local.width * scale))
            config.height = max(16, Int(local.height * scale))
            config.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: overlayWindows)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let isCompactSelection = rectAX.width < 260 && rectAX.height < 75
            let lines = try recognizeRegionLines(in: image, frame: local, languageCorrection: !isCompactSelection)
            let fallbackLines = lines.isEmpty && isCompactSelection
                ? (try? recognizeRegionLines(in: image, frame: local, languageCorrection: true)) ?? []
                : lines
            let ordered = fallbackLines.sorted { abs($0.1.minY - $1.1.minY) < 6 ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY }
            let joined = ordered.map(\.0).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        } catch {
            return nil
        }
    }

    private static func preferredRecognitionLanguages() -> [String] {
        let primary = Settings.shared.prefs.exampleLanguage.localeIdentifier
        let all = ["en-US", "it-IT", "es-ES", "fr-FR", "de-DE", "pt-PT"].map { $0 }
        let normPrimary = primary.replacingOccurrences(of: "_", with: "-")
        return [normPrimary] + all.filter { $0 != normPrimary }
    }

    private static func recognizeRegionLines(in image: CGImage, frame: CGRect, languageCorrection: Bool) throws -> [(String, CGRect)] {
        try autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = languageCorrection
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }
            request.recognitionLanguages = preferredRecognitionLanguages()
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { obs in
                guard let s = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                      s.count >= 2, s.contains(where: { $0.isLetter }) else { return nil }
                let bb = obs.boundingBox
                let r = CGRect(x: frame.minX + bb.minX * frame.width,
                               y: frame.minY + (1 - bb.maxY) * frame.height,
                               width: bb.width * frame.width,
                               height: bb.height * frame.height)
                return (s, r)
            }
        }
    }

    private static func recognizeLines(in image: CGImage, frame: CGRect, fast: Bool) throws -> [(String, CGRect)] {
        try autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = fast ? .fast : .accurate
            request.usesLanguageCorrection = true
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }
            request.recognitionLanguages = preferredRecognitionLanguages()
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { obs in
                guard let s = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces),
                      s.count >= 2, s.contains(where: { $0.isLetter }) else { return nil }
                let bb = obs.boundingBox
                let r = CGRect(x: frame.minX + bb.minX * frame.width,
                               y: frame.minY + (1 - bb.maxY) * frame.height,
                               width: bb.width * frame.width, height: bb.height * frame.height)
                return (s, r)
            }
        }
    }

    /// Drops the immediate line at the caret (already in the prompt) and menu bar chrome, keeping both
    /// side-by-side reference windows (e.g. a book/PDF next to Obsidian) and nearby context in reading order.
    static func select(_ lines: [(String, CGRect)], fieldAX: CGRect?, caretAX: CGRect, budget: Int = 1600) -> String? {
        var pool = lines.filter { $0.1.minY > 28 }   // skip the macOS status bar at the very top of the screen
        if let f = fieldAX, f.width > 0, f.height > 0, f.height < 160 {
            pool = pool.filter { !$0.1.insetBy(dx: 2, dy: 2).intersects(f) }
        } else {
            // Only skip the line at the caret inside the same horizontal column so side-by-side windows stay intact.
            pool = pool.filter { line in
                let sameRow = line.1.maxY > caretAX.minY - 2 && line.1.minY < caretAX.maxY + 2
                let sameCol = abs(line.1.midX - caretAX.midX) < 280
                return !(sameRow && sameCol)
            }
        }
        let scored = pool.map { line -> (Double, String, CGRect) in
            let sameCol = abs(line.1.midX - caretAX.midX) < 340
            if !sameCol {
                // Side-by-side reference window (book, PDF, browser): high priority, ordered top-to-bottom.
                return (Double(max(0, line.1.minY - 40)) * 0.45, line.0, line.1)
            }
            let dy = Double(caretAX.midY - line.1.midY)
            let distance = dy >= 0 ? dy : -dy * 2.2
            return (distance, line.0, line.1)
        }.sorted { $0.0 < $1.0 }
        var chosen: [(String, CGRect)] = []
        var total = 0
        for (_, text, rect) in scored {
            if total + text.count > budget { continue }
            chosen.append((text, rect)); total += text.count + 1
            if total >= budget - 20 { break }
        }
        guard !chosen.isEmpty else { return nil }
        let ordered = chosen.sorted { a, b in
            let colA = Int(a.1.midX / 420), colB = Int(b.1.midX / 420)
            if colA != colB { return colA < colB }
            return abs(a.1.minY - b.1.minY) < 4 ? a.1.minX < b.1.minX : a.1.minY < b.1.minY
        }
        return ordered.map(\.0).joined(separator: "\n")
    }

    /// Dynamically selects the lines from the full-screen snapshot (`fullText`) that best match the words
    /// the user is currently typing in `draft` (plus ±2 surrounding lines for paragraph continuity),
    /// while keeping the recent active-window context. If you're typing in WhatsApp about a note open in
    /// TextEdit or a book in Preview, those matching lines from the other window are automatically pulled in.
    static func relevantExcerpt(from fullText: String, forDraft draft: String, budget: Int = 2000) -> String {
        guard fullText.count > budget else { return fullText }
        let lines = fullText.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return String(fullText.suffix(budget)) }

        let draftTail = String(draft.suffix(260)).lowercased()
        let draftWords = Set(
            draftTail.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 3 }
        )
        guard !draftWords.isEmpty else { return String(fullText.suffix(budget)) }

        var rawScores = [Int](repeating: 0, count: lines.count)
        for (idx, line) in lines.enumerated() {
            let lineWords = Set(line.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            rawScores[idx] = lineWords.intersection(draftWords).count * 10
        }

        // Propagate score to ±2 neighboring lines so full sentences/paragraphs around a keyword match stay intact.
        var expandedScores = rawScores
        for idx in 0..<lines.count where rawScores[idx] > 0 {
            for delta in -2...2 where delta != 0 {
                let n = idx + delta
                if n >= 0, n < lines.count {
                    expandedScores[n] = max(expandedScores[n], rawScores[idx] - abs(delta) * 3)
                }
            }
        }

        // Rank lines by topic relevance first, then prefer lines near the end (active window / bottom of reading order).
        let rankedIndices = (0..<lines.count).sorted { a, b in
            if expandedScores[a] != expandedScores[b] { return expandedScores[a] > expandedScores[b] }
            return a > b
        }

        var chosenIndices: [Int] = []
        var total = 0
        for idx in rankedIndices {
            let len = lines[idx].count + 1
            if total + len > budget { continue }
            chosenIndices.append(idx)
            total += len
            if total >= budget - 24 { break }
        }
        chosenIndices.sort()
        return chosenIndices.map { lines[$0] }.joined(separator: "\n")
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let sa = Set(a.lowercased().split(whereSeparator: { !$0.isLetter })), sb = Set(b.lowercased().split(whereSeparator: { !$0.isLetter }))
        guard !sa.isEmpty || !sb.isEmpty else { return 1 }
        return Double(sa.intersection(sb).count) / Double(sa.union(sb).count)
    }
}
