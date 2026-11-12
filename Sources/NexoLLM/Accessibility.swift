import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Snapshot of the focused text field around the caret.
struct TextContext {
    let pid: pid_t
    let bundleID: String
    let appName: String
    let element: AXUIElement
    let caretLocation: Int
    /// Text before the caret (at most ~3000 UTF-16 units).
    let prefix: String
    /// Absolute UTF-16 offset of `prefix`'s first character in the field.
    let prefixStart: Int
    /// Up to 300 UTF-16 units after the caret.
    let after: String
    /// True when nothing but whitespace follows the caret on the current line.
    let atLineEnd: Bool
    /// Caret rectangle in AX/Quartz global coordinates (origin top-left of main screen).
    let caretRect: CGRect
    let fontSize: CGFloat?
    /// Frame of the focused text element (AX coordinates), if available.
    let fieldFrame: CGRect?
    /// A canvas editor (Google Docs) whose text isn't exposed: the controller supplies what was typed.
    var canvasEditor = false
    /// Stable-ish identity of the focused field (pid + element hash).
    var fieldKey: String { "\(pid)-\(CFHash(element))" }
}

enum AX {
    static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.3)   // never hang on a frozen app
        return el
    }()

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private static var enhancedPIDs: [pid_t: Date] = [:]

    /// Electron/Chromium apps only expose their text tree when asked — and can silently drop it again
    /// (window closed/reopened, renderer restarted). `force` re-asks (at most every 2 s per app), so a lost
    /// tree heals itself instead of needing a NexoLLM restart.
    static func enableManualAccessibility(_ pid: pid_t, force: Bool = false) {
        if let last = enhancedPIDs[pid], !force || Date().timeIntervalSince(last) < 2 { return }
        enhancedPIDs[pid] = Date()
        if enhancedPIDs.count > 64 { enhancedPIDs = enhancedPIDs.filter { NSRunningApplication(processIdentifier: $0.key) != nil } }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static var enhancedUIPIDs = Set<pid_t>()

    /// iWork apps build the accessibility tree of a document's text only after an assistive client sets
    /// `AXEnhancedUserInterface` (the call reports "unsupported" but takes effect). Done at most once per
    /// process, and only for apps whose focused element is a canvas without text — never globally, since
    /// the flag can slow down window animations. Returns true when it was just enabled.
    static func enableEnhancedUserInterface(_ pid: pid_t, app name: String) -> Bool {
        guard enhancedUIPIDs.insert(pid).inserted else { return false }
        if enhancedUIPIDs.count > 64 { enhancedUIPIDs = enhancedUIPIDs.filter { NSRunningApplication(processIdentifier: $0) != nil } }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        Log.info("ax: enabled the document text tree of \(name) (enhanced accessibility)")
        return true
    }

    static let browserBundles: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
                                              "com.google.Chrome.canary", "company.thebrowser.Browser", "com.brave.Browser",
                                              "com.microsoft.edgemac", "org.mozilla.firefox", "com.operasoftware.Opera",
                                              "com.vivaldi.Vivaldi"]

    /// Frame of the app's focused window (AX coordinates).
    static func windowFrame(_ pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let w = attr(app, kAXFocusedWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return elementFrame(w as! AXUIElement)
    }

    /// Google Docs draws its text on a canvas and hides it from Accessibility (unless its screen reader
    /// mode is on): recognized by the window title.
    static func isGoogleDocs(_ pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let w = attr(app, kAXFocusedWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID(),
              let title = attr(w as! AXUIElement, kAXTitleAttribute) as? String else { return false }
        return title.contains("Google Docs") || title.contains("Documenti Google")
    }

    /// A web text field nested inside the focused web area.
    private static func textChild(_ el: AXUIElement) -> AXUIElement? {
        guard let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        return kids.prefix(12).first { k in
            let role = attr(k, kAXRoleAttribute) as? String ?? ""
            return attr(k, kAXSelectedTextRangeAttribute) != nil && (role == "AXTextArea" || role == "AXTextField" || role == "AXWebArea")
        }
    }

    /// An empty context for a canvas editor, with the caret near the bottom of the page.
    private static func canvasContext(_ app: NSRunningApplication, _ el: AXUIElement) -> TextContext? {
        let pid = app.processIdentifier
        guard let f = elementFrame(el).flatMap({ $0.width > 120 && $0.height > 60 ? $0 : nil }) ?? windowFrame(pid) else {
            return fail("canvas editor without a frame")
        }
        return TextContext(pid: pid, bundleID: app.bundleIdentifier ?? "", appName: app.localizedName ?? "", element: el,
                           caretLocation: 0, prefix: "", prefixStart: 0, after: "", atLineEnd: true,
                           caretRect: CGRect(x: f.midX - 60, y: f.maxY - 64, width: 0, height: 18),
                           fontSize: nil, fieldFrame: f, canvasEditor: true)
    }

    // MARK: Attribute helpers

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func param(_ el: AXUIElement, _ name: String, _ range: CFRange) -> CFTypeRef? {
        var r = range
        guard let rv = AXValueCreate(.cfRange, &r) else { return nil }
        var v: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(el, name as CFString, rv, &v) == .success ? v : nil
    }

    private static func string(_ el: AXUIElement, _ range: CFRange) -> String? {
        guard range.length > 0 else { return "" }
        return param(el, kAXStringForRangeParameterizedAttribute, range) as? String
    }

    private static func bounds(_ el: AXUIElement, _ range: CFRange) -> CGRect? {
        guard let v = param(el, kAXBoundsForRangeParameterizedAttribute, range),
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(v as! AXValue, .cgRect, &rect), rect.height > 1 else { return nil }
        return rect
    }

    static func elementFrame(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func paramAny(_ el: AXUIElement, _ name: String, _ arg: CFTypeRef) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(el, name as CFString, arg, &v) == .success ? v : nil
    }

    private static func rect(from v: CFTypeRef?) -> CGRect? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        guard AXValueGetValue(v as! AXValue, .cgRect, &r), r.height > 1 else { return nil }
        return r
    }

    /// The caret as a text marker (start of the selected marker range).
    static func caretMarker(_ el: AXUIElement) -> AXTextMarker? {
        guard let sel = attr(el, "AXSelectedTextMarkerRange"),
              CFGetTypeID(sel) == AXTextMarkerRangeGetTypeID() else { return nil }
        return AXTextMarkerRangeCopyStartMarker(sel as! AXTextMarkerRange)
    }

    private static func markerRect(_ el: AXUIElement, _ a: CFTypeRef, _ b: CFTypeRef) -> CGRect? {
        guard let range = paramAny(el, "AXTextMarkerRangeForUnorderedTextMarkers", [a, b] as CFArray) else { return nil }
        return rect(from: paramAny(el, "AXBoundsForTextMarkerRange", range))
    }

    /// Caret via WebKit/Chromium text markers (contenteditable editors in browsers and Electron apps).
    static func textMarkerCaret(_ el: AXUIElement, prevIsNewline: Bool) -> CGRect? {
        guard let sel = attr(el, "AXSelectedTextMarkerRange") else { return nil }
        // Only trust a caret-sized box; Chromium returns the whole line box for a collapsed range.
        let selBox = rect(from: paramAny(el, "AXBoundsForTextMarkerRange", sel))
        if let r = selBox, r.width <= 3, isOnScreen(r) {
            return CGRect(x: r.minX, y: r.minY, width: 0, height: r.height)
        }
        guard let caret = caretMarker(el) else { return nil }
        // Measure the character before the caret (or after it, at the start of a line).
        var link: CGRect?
        if !prevIsNewline, let prev = paramAny(el, "AXPreviousTextMarkerForTextMarker", caret),
           let r = markerRect(el, prev, caret), isOnScreen(r) {
            if r.width < 80 { return CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height) }
            link = r   // a link before the caret is measured as one run: its end is the caret
        }
        if let next = paramAny(el, "AXNextTextMarkerForTextMarker", caret),
           let r = markerRect(el, caret, next), r.width < 80, isOnScreen(r) {
            return CGRect(x: r.minX, y: r.minY, width: 0, height: r.height)
        }
        // Empty line: the line box begins exactly where the caret is.
        if prevIsNewline, let r = selBox, isOnScreen(r) {
            return CGRect(x: r.minX, y: r.minY, width: 0, height: r.height)
        }
        if let r = link, r.width < 600, r.height <= 36 { return CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height) }
        return nil
    }

    static func focusedElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        for source in [app, systemWide] {
            if let v = attr(source, kAXFocusedUIElementAttribute), CFGetTypeID(v) == AXUIElementGetTypeID() {
                return (v as! AXUIElement)
            }
        }
        return nil
    }

    // MARK: Context

    /// Why the last `currentContext()` returned nil (for the log).
    static var lastFailure = ""

    private static func fail(_ reason: String) -> TextContext? {
        lastFailure = reason
        return nil
    }

    static func currentContext() -> TextContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return fail("no frontmost app") }
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return fail("NexoLLM is frontmost") }
        enableManualAccessibility(pid)
        // Browsers expose web editors (Google Docs, canvas/iframe apps) only to "enhanced" assistive clients.
        let browser = browserBundles.contains(app.bundleIdentifier ?? "")
        if browser { _ = enableEnhancedUserInterface(pid, app: app.localizedName ?? "?") }
        guard var el = focusedElement(pid: pid) else {
            enableManualAccessibility(pid, force: true)
            return fail("no focused element in \(app.localizedName ?? "?")")
        }
        var role = attr(el, kAXRoleAttribute) as? String ?? "?"
        if browser, attr(el, kAXSelectedTextRangeAttribute) == nil, let child = textChild(el) {
            el = child
            role = attr(el, kAXRoleAttribute) as? String ?? "?"
        }
        let docs = browser && isGoogleDocs(pid)
        // Pages, Keynote and Numbers report their document canvas (an AXScrollArea) as focused and only
        // expose the text inside it to "enhanced" assistive clients. Ask once per app, then look again.
        if attr(el, kAXSelectedTextRangeAttribute) == nil, role == "AXScrollArea" || role == "AXLayoutArea",
           enableEnhancedUserInterface(pid, app: app.localizedName ?? "?"),
           let again = focusedElement(pid: pid) {
            el = again
            role = attr(el, kAXRoleAttribute) as? String ?? "?"
        }

        // Never touch password fields.
        if let sub = attr(el, kAXSubroleAttribute) as? String, sub == (kAXSecureTextFieldSubrole as String) {
            return fail("password field")
        }
        if role == "AXSecureTextField" { return fail("password field") }

        guard let rv = attr(el, kAXSelectedTextRangeAttribute), CFGetTypeID(rv) == AXValueGetTypeID() else {
            if docs { return canvasContext(app, el) }
            enableManualAccessibility(pid, force: true)
            return fail("focused \(role) has no selected text range")
        }
        var sel = CFRange()
        guard AXValueGetValue(rv as! AXValue, .cfRange, &sel), sel.location >= 0 else { return fail("bad range") }
        guard sel.length == 0 else { return fail("text is selected") }
        let loc = sel.location

        // Text before/after the caret. Prefer ranged reads; fall back to the full value.
        let start = max(0, loc - 3000)
        var prefix = string(el, CFRange(location: start, length: loc - start))
        var after: String?
        let total = (attr(el, kAXNumberOfCharactersAttribute) as? Int)
        if let total, total > loc {
            after = string(el, CFRange(location: loc, length: min(300, total - loc)))
        } else if total != nil {
            after = ""
        }
        if prefix == nil || after == nil {
            guard let value = attr(el, kAXValueAttribute) as? String else { return fail("\(role): cannot read text") }
            let ns = value as NSString
            guard loc <= ns.length else { return fail("caret beyond text") }
            prefix = prefix ?? ns.substring(with: NSRange(location: start, length: loc - start))
            after = after ?? ns.substring(with: NSRange(location: loc, length: min(300, ns.length - loc)))
        }
        guard var prefix, var after else { return fail("no text") }
        // Some web fields report their grey placeholder as the value: an empty field has no text to continue.
        (prefix, after) = withoutPlaceholder(prefix: prefix, after: after,
                                             placeholder: attr(el, kAXPlaceholderValueAttribute) as? String)
        let restOfLine = after.prefix(while: { $0 != "\n" && $0 != "\r" })
        let atLineEnd = restOfLine.allSatisfy { $0.isWhitespace }

        // Caret position on screen. Apps disagree on the box of an empty range (some return the field's
        // origin, the line start or the whole paragraph), so candidates are cross-checked with the box of
        // the character before the caret and with the field's frame (see `CaretGeometry`).
        let field = elementFrame(el)
        var caret: CGRect?
        var fallback: CGRect?   // on screen but doesn't fit the field: used only if nothing better turns up
        var notes: [String] = []
        let prevIsNewline = prefix.last?.isNewline ?? false
        func visible(_ r: CGRect?, _ label: String) -> CGRect? {
            guard let r else { notes.append("\(label) nil"); return nil }
            guard isOnScreen(r) else { notes.append("\(label) offscreen \(r)"); return nil }
            return r
        }
        func consider(_ c: CGRect) {
            if caret == nil, CaretGeometry.plausible(c, field: field) { caret = c } else if fallback == nil { fallback = c }
        }
        let r0 = visible(bounds(el, CFRange(location: loc, length: 0)), "r0")
        let rPrev = loc > 0 && !prevIsNewline ? visible(bounds(el, CFRange(location: loc - 1, length: 1)), "prev") : nil
        caret = CaretGeometry.choose(collapsed: r0, previous: rPrev,
                                     previousIsSpace: prefix.last == " " || prefix.last == "\t", field: field)
        if caret == nil {
            fallback = r0.map { CGRect(x: $0.minX, y: $0.minY, width: 0, height: $0.height) }
                ?? rPrev.map { CGRect(x: $0.maxX, y: $0.minY, width: 0, height: $0.height) }
        }
        if caret == nil, let next = after.first, !next.isNewline,
           let r = visible(bounds(el, CFRange(location: loc, length: 1)), "next") {
            consider(CGRect(x: r.minX, y: r.minY, width: 0, height: r.height))
        }
        if caret == nil, prevIsNewline, loc > 0,
           let nl = bounds(el, CFRange(location: loc - 1, length: 1)), isOnScreen(nl), let frame = field {
            // Empty new line: one line below the previous line, at the field's left edge.
            consider(CGRect(x: frame.minX + 6, y: nl.maxY, width: 0, height: nl.height))
        }
        if caret == nil {
            if let r = textMarkerCaret(el, prevIsNewline: prevIsNewline) { consider(r) } else { notes.append("marker nil") }
        }
        caret = caret ?? fallback
        if caret == nil, docs, let f = field ?? windowFrame(pid) {   // the hidden input of a canvas editor
            caret = CGRect(x: f.midX - 60, y: f.maxY - 64, width: 0, height: 18)
        }
        guard let caretRect = caret else {
            return fail("\(app.localizedName ?? "?") \(role): no caret bounds loc=\(loc) prev=\(String(reflecting: prefix.last.map(String.init) ?? "")) \(notes.joined(separator: ", "))")
        }

        // Some editors (CodeMirror/Obsidian, many web apps) omit newlines between lines in the AX text,
        // so also treat the caret as "at line end" when the next character is on another visual line.
        var lineEnd = atLineEnd
        if !lineEnd {
            if let rest = markerRestOfLine(el) ?? indexRestOfLine(el, loc) {
                lineEnd = rest.allSatisfy { $0.isWhitespace }
            } else if let next = nextCharRect(el, loc) {
                lineEnd = abs(next.midY - caretRect.midY) > caretRect.height * 0.5
            }
        }

        return TextContext(
            pid: pid,
            bundleID: app.bundleIdentifier ?? "",
            appName: app.localizedName ?? "",
            element: el,
            caretLocation: loc,
            prefix: prefix,
            prefixStart: start,
            after: after,
            atLineEnd: lineEnd,
            caretRect: caretRect,
            fontSize: fontSize(el, loc),
            fieldFrame: field,
            canvasEditor: docs
        )
    }

    /// The field's text unless it's only the placeholder (then the field is empty).
    static func withoutPlaceholder(prefix: String, after: String, placeholder: String?) -> (prefix: String, after: String) {
        guard let p = placeholder?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty,
              (prefix + after).trimmingCharacters(in: .whitespacesAndNewlines) == p else { return (prefix, after) }
        return ("", "")
    }

    /// A short selected word/phrase in the focused field (for synonyms).
    struct Selection {
        let text: String
        let rect: CGRect
        let pid: pid_t
        let bundleID: String
        let before: String
    }

    /// A selected word/phrase in the focused field: short by default (synonyms), longer for rewriting or web lookup.
    static func currentSelection(maxChars: Int = 40, maxWords: Int = 3) -> Selection? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let pid = app.processIdentifier
        enableManualAccessibility(pid)
        guard let el = focusedElement(pid: pid) else { return nil }

        var sel = CFRange(location: 0, length: 0)
        var hasRange = false
        if let rv = attr(el, kAXSelectedTextRangeAttribute), CFGetTypeID(rv) == AXValueGetTypeID(),
           AXValueGetValue(rv as! AXValue, .cfRange, &sel), sel.length > 0 {
            hasRange = true
        }
        let rawText = (attr(el, kAXSelectedTextAttribute) as? String) ?? (hasRange ? string(el, sel) : nil)
        guard let text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= maxChars,
              maxWords > 3 || !text.contains("\n"),
              text.split(whereSeparator: \.isWhitespace).count <= maxWords else { return nil }

        var rect: CGRect? = hasRange ? bounds(el, sel) : nil
        if rect == nil, let m = attr(el, "AXSelectedTextMarkerRange") {
            rect = self.rect(from: paramAny(el, "AXBoundsForTextMarkerRange", m))
        }
        if let r = rect, !isOnScreen(r) { rect = nil }
        let fallbackRect = rect ?? currentContext()?.caretRect ?? elementFrame(el) ?? mouseAXRect()
        let start = hasRange ? max(0, sel.location - 300) : 0
        let before = hasRange ? (string(el, CFRange(location: start, length: sel.location - start)) ?? "") : ""
        return Selection(text: text, rect: fallbackRect, pid: pid, bundleID: app.bundleIdentifier ?? "", before: before)
    }

    /// Reads highlighted text anywhere in the frontmost app (including Google/browser pages, WhatsApp messages, PDFs, etc.).
    static func selectedTextAnywhere(maxChars: Int = 600) -> Selection? {
        if let s = currentSelection(maxChars: maxChars, maxWords: 140) { return s }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let pid = app.processIdentifier
        enableManualAccessibility(pid)
        if browserBundles.contains(app.bundleIdentifier ?? "") {
            _ = enableEnhancedUserInterface(pid, app: app.localizedName ?? "?")
        }
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.3)
        var queue: [AXUIElement] = []
        if let f = focusedElement(pid: pid) {
            queue.append(f)
            if let p = attr(f, kAXParentAttribute), CFGetTypeID(p) == AXUIElementGetTypeID() { queue.append(p as! AXUIElement) }
        }
        if let w = attr(appEl, kAXFocusedWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() {
            queue.append(w as! AXUIElement)
        }
        var head = 0
        let maxNodes = 42
        while head < queue.count, head < maxNodes {
            let el = queue[head]
            head += 1
            var selectedString = (attr(el, kAXSelectedTextAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let markerRange = attr(el, "AXSelectedTextMarkerRange")
            if (selectedString == nil || selectedString!.isEmpty), let m = markerRange {
                selectedString = (paramAny(el, "AXStringForTextMarkerRange", m) as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let t = selectedString, !t.isEmpty, t.count <= maxChars {
                var r: CGRect?
                if let m = markerRange {
                    r = rect(from: paramAny(el, "AXBoundsForTextMarkerRange", m))
                }
                let finalRect = (r != nil && isOnScreen(r!)) ? r! : mouseAXRect()
                return Selection(text: t, rect: finalRect, pid: pid, bundleID: app.bundleIdentifier ?? "", before: "")
            }
            if queue.count < maxNodes, let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: kids.prefix(12))
            }
        }
        return nil
    }

    /// Reads highlighted text anywhere in the frontmost app, falling back to a non-destructive `⌘C` probe
    /// (preserving the user's clipboard) when an external app or browser page does not expose selection via Accessibility.
    static func selectedTextWithCopyFallback(maxChars: Int = 600, completion: @escaping (Selection?) -> Void) {
        if let sel = selectedTextAnywhere(maxChars: maxChars), sel.text.contains(where: { $0.isLetter }) {
            completion(sel)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !IsSecureEventInputEnabled() else {
            completion(nil)
            return
        }
        // A text field that reports an empty selection has nothing highlighted: never probe with ⌘C there
        // (editors like VS Code copy the whole current line when nothing is selected).
        if focusedFieldHasEmptySelection(pid: app.processIdentifier) {
            completion(nil)
            return
        }
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier ?? ""
        let pb = NSPasteboard.general
        let savedCount = pb.changeCount
        let savedItems: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }

        // Synthesize Cmd+C to probe if any external text (Google page, WhatsApp message, PDF) is currently highlighted.
        let src = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) {
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        // Browsers and Electron apps (Chrome, WhatsApp) can take a while to answer ⌘C: poll up to ~300 ms.
        func waitForCopy(_ attempt: Int) {
            guard pb.changeCount == savedCount, attempt < 10 else { finish(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { waitForCopy(attempt + 1) }
        }
        func restoreClipboard() {
            pb.clearContents()
            if !savedItems.isEmpty {
                let restored: [NSPasteboardItem] = savedItems.map { pairs in
                    let item = NSPasteboardItem()
                    for (t, d) in pairs { item.setData(d, forType: t) }
                    return item
                }
                pb.writeObjects(restored)
            }
        }
        func finish() {
            guard pb.changeCount != savedCount else {
                // The app may still answer ⌘C after we gave up: if exactly that one copy lands, undo it so the
                // user's clipboard is never silently replaced by the selection.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if pb.changeCount == savedCount + 1 { restoreClipboard() }
                }
                completion(nil)
                return
            }
            // Password managers mark what they copy as concealed: never read or search it.
            let concealed = Pasteboards.isSensitive(pb)
            let copied = concealed ? nil : pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Restore original pasteboard immediately so the user's clipboard is untouched.
            restoreClipboard()
            guard let text = copied, !text.isEmpty, text.count <= maxChars, text.contains(where: { $0.isLetter }) else {
                completion(nil)
                return
            }
            completion(Selection(text: text, rect: mouseAXRect(), pid: pid, bundleID: bundleID, before: ""))
        }
        waitForCopy(0)
    }

    /// True when the focused element is a text field whose selection is a caret (length 0).
    private static func focusedFieldHasEmptySelection(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let f = attr(app, kAXFocusedUIElementAttribute), CFGetTypeID(f) == AXUIElementGetTypeID() else { return false }
        let el = f as! AXUIElement
        guard let v = attr(el, kAXSelectedTextRangeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return false }
        var range = CFRange()
        guard AXValueGetValue(v as! AXValue, .cfRange, &range) else { return false }
        return range.length == 0
    }

    static func mouseAXRect() -> CGRect {
        let m = NSEvent.mouseLocation
        let h = NSScreen.screens.first?.frame.height ?? 900
        return CGRect(x: m.x, y: h - m.y, width: 0, height: 18)
    }

    // MARK: Other fields of the window

    /// Short values of the *other* text fields around the focused one — an email's subject and recipients,
    /// a form's title, a ticket's summary — labelled when the app names them ("Oggetto: dal 19 al 23").
    ///
    /// Bounded, so it's safe on the main thread: scans outward from the focused field (nearest container
    /// first, then its parents up to the window), one batched AX call per node, at most `nodeBudget`
    /// nodes and `timeBudget` seconds. Password fields and search boxes are skipped.
    static func windowFields(around focused: AXUIElement, nodeBudget: Int = 260, timeBudget: TimeInterval = 0.03,
                             maxFields: Int = 5) -> [String] {
        let started = Date()
        var ancestors: [AXUIElement] = []
        var node = focused
        for _ in 0..<14 {
            guard let p = attr(node, kAXParentAttribute), CFGetTypeID(p) == AXUIElementGetTypeID() else { break }
            let parent = p as! AXUIElement
            ancestors.append(parent)
            if (attr(parent, kAXRoleAttribute) as? String) == (kAXWindowRole as String) { break }
            node = parent
        }
        let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXDescriptionAttribute,
                     kAXPlaceholderValueAttribute, kAXTitleAttribute, kAXChildrenAttribute] as CFArray
        var visited = 0
        var out: [String] = []
        var seen = Set<String>()
        var skip: AXUIElement? = focused   // subtree already scanned at the previous level
        for root in ancestors {
            var queue: [AXUIElement] = [root]
            var head = 0
            while head < queue.count {
                if visited >= nodeBudget || out.count >= maxFields || Date().timeIntervalSince(started) > timeBudget { return out }
                let el = queue[head]; head += 1
                if let s = skip, CFEqual(el, s) { continue }
                visited += 1
                var values: CFArray?
                guard AXUIElementCopyMultipleAttributeValues(el, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
                      let v = values as? [Any], v.count == 7 else { continue }
                let role = v[0] as? String ?? ""
                let subrole = v[1] as? String ?? ""
                if role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox",
                   subrole != (kAXSecureTextFieldSubrole as String), subrole != (kAXSearchFieldSubrole as String),
                   !CFEqual(el, focused),
                   let raw = v[2] as? String {
                    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                    if !value.isEmpty, value.count <= 400, seen.insert(value).inserted {
                        let label = [v[3], v[4], v[5]].lazy.compactMap { $0 as? String }
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .first { !$0.isEmpty && $0 != value && $0.count <= 40 }
                        let clipped = String(value.prefix(160))
                        out.append(label.map { "\($0): \(clipped)" } ?? clipped)
                    }
                    continue   // a text field's children are its text runs
                }
                if role == "AXStaticText" || role == "AXImage" || role == "AXButton" { continue }
                if let kids = v[6] as? [AXUIElement] { queue.append(contentsOf: kids.prefix(60)) }
            }
            skip = root
        }
        return out
    }

    /// Text from the caret to the end of its visual line (WebKit/Chromium text markers).
    static func markerRestOfLine(_ el: AXUIElement) -> String? {
        guard let caret = caretMarker(el),
              let line = paramAny(el, "AXLineTextMarkerRangeForTextMarker", caret),
              CFGetTypeID(line) == AXTextMarkerRangeGetTypeID() else { return nil }
        let end = AXTextMarkerRangeCopyEndMarker(line as! AXTextMarkerRange)
        guard let range = paramAny(el, "AXTextMarkerRangeForUnorderedTextMarkers", [caret, end] as CFArray) else { return nil }
        return paramAny(el, "AXStringForTextMarkerRange", range) as? String
    }

    /// Text from the caret to the end of its line using index-based line APIs.
    static func indexRestOfLine(_ el: AXUIElement, _ loc: Int) -> String? {
        guard let lineNum = paramAny(el, kAXLineForIndexParameterizedAttribute, loc as CFNumber) as? Int,
              let rv = paramAny(el, kAXRangeForLineParameterizedAttribute, lineNum as CFNumber),
              CFGetTypeID(rv) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        guard AXValueGetValue(rv as! AXValue, .cfRange, &r) else { return nil }
        let end = r.location + r.length
        guard end >= loc else { return nil }
        return string(el, CFRange(location: loc, length: end - loc))
    }

    /// Diagnostic: attribute names + a few geometry probes for the focused element.
    static func dump(_ el: AXUIElement, loc: Int) -> String {
        var names: CFArray?
        AXUIElementCopyAttributeNames(el, &names)
        var pnames: CFArray?
        AXUIElementCopyParameterizedAttributeNames(el, &pnames)
        let next = nextCharRect(el, loc).map { "\($0)" } ?? "nil"
        let sel = attr(el, "AXSelectedTextMarkerRange")
        let selRect = sel.flatMap { rect(from: paramAny(el, "AXBoundsForTextMarkerRange", $0)) }.map { "\($0)" } ?? "nil"
        let parentRole = (attr(el, kAXParentAttribute)).flatMap { p -> String? in
            guard CFGetTypeID(p) == AXUIElementGetTypeID() else { return nil }
            return attr(p as! AXUIElement, kAXRoleAttribute) as? String
        } ?? "nil"
        let insertionLine = attr(el, kAXInsertionPointLineNumberAttribute).map { "\($0)" } ?? "nil"
        let mc = textMarkerCaret(el, prevIsNewline: false).map { "\($0)" } ?? "nil"
        let mr = markerRestOfLine(el).map { String(reflecting: String($0.prefix(30))) } ?? "nil"
        let ir = indexRestOfLine(el, loc).map { String(reflecting: String($0.prefix(30))) } ?? "nil"
        return "next=\(next) selRect=\(selRect) markerCaret=\(mc) markerRest=\(mr) indexRest=\(ir) parent=\(parentRole) insLine=\(insertionLine) attrsCount=\((names as? [String])?.count ?? 0) paramsCount=\((pnames as? [String])?.count ?? 0)"
    }

    /// Screen rect of the character right after the caret (AX range API, then text markers).
    private static func nextCharRect(_ el: AXUIElement, _ loc: Int) -> CGRect? {
        if let r = bounds(el, CFRange(location: loc, length: 1)), isOnScreen(r) { return r }
        guard let caret = caretMarker(el),
              let next = paramAny(el, "AXNextTextMarkerForTextMarker", caret),
              let r = markerRect(el, caret, next), r.width < 80, isOnScreen(r) else { return nil }
        return r
    }

    /// Font size of the character before the caret, if the app exposes it.
    private static func fontSize(_ el: AXUIElement, _ loc: Int) -> CGFloat? {
        guard loc > 0,
              let v = param(el, kAXAttributedStringForRangeParameterizedAttribute, CFRange(location: loc - 1, length: 1)),
              let attributed = v as? NSAttributedString, attributed.length > 0,
              let font = attributed.attribute(NSAttributedString.Key("AXFont"), at: 0, effectiveRange: nil) as? [String: Any],
              let size = font["AXFontSize"] as? CGFloat, size > 4 else { return nil }
        return size
    }

    private static func isOnScreen(_ axRect: CGRect) -> Bool {
        let p = Geometry.toCocoa(axRect)
        return NSScreen.screens.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(CGPoint(x: p.minX, y: p.midY)) }
    }
}

/// Picks the caret among the boxes an app reports. Pure geometry (AX coordinates), unit-tested.
enum CaretGeometry {
    /// One line tall, not the (0,0) placeholder some apps return, and inside the field when its frame is known.
    static func plausible(_ r: CGRect, field: CGRect?) -> Bool {
        guard !(r.minX == 0 && r.minY == 0), r.height >= 4, r.height <= 200 else { return false }
        guard let f = field, f.width > 20, f.height > 8 else { return true }
        if r.height > f.height + 12 { return false }
        return f.insetBy(dx: -24, dy: -24).contains(CGPoint(x: r.minX, y: r.midY))
    }

    /// `collapsed`: box of the empty range at the caret. `previous`: box of the character before it.
    /// Empty ranges are where apps misbehave; a character box is reliable. When both exist and disagree,
    /// trust the character, unless it's the space ending a wrapped line and the caret starts the next one.
    static func choose(collapsed: CGRect?, previous: CGRect?, previousIsSpace: Bool, field: CGRect?) -> CGRect? {
        let c = collapsed.map { CGRect(x: $0.minX, y: $0.minY, width: 0, height: $0.height) }
        let p = previous.flatMap { r -> CGRect? in
            r.width <= max(r.height * 4, 80) ? CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height) : nil
        }
        let okC = c.map { plausible($0, field: field) } ?? false
        let okP = p.map { plausible($0, field: field) } ?? false
        if okC, okP, let c, let p {
            let h = min(c.height, p.height)
            if abs(c.midY - p.midY) < h * 0.6, abs(c.minX - p.minX) <= max(h * 1.5, 24) { return c }   // they agree
            if previousIsSpace, c.minY >= p.midY { return c }   // soft wrap: caret at the start of the next line
            return p
        }
        if okC { return c }
        if okP { return p }
        // Nothing else fits: a link right before the caret is reported as one wide run, and its end is the caret.
        if let r = previous, r.height <= 36, r.width <= 600 {
            let end = CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height)
            if plausible(end, field: field) { return end }
        }
        return nil
    }
}

enum Geometry {
    /// AX/Quartz (top-left origin of the primary screen) -> Cocoa (bottom-left origin).
    static func toCocoa(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
