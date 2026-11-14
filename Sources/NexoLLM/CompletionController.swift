import AppKit
import SwiftUI
import Carbon.HIToolbox
import NaturalLanguage

/// Glues keyboard events, Accessibility, the model and all overlays together.
/// Completions (end-of-line and mid-line), word/full accept,
/// autocorrect, emoji, alternatives, synonyms, per-app rules, battery modes, personalization and context.
final class CompletionController {
    let engine: LLMEngine
    private var settings: Settings { Settings.shared }
    private var prefs: Prefs { Settings.shared.prefs }

    private let ghost = GhostOverlay()
    private let list = ListOverlay()
    private let toast = ToastOverlay()
    private let quickMenu = QuickMenuOverlay()
    private let lookup = LookupOverlay()
    private let screenSelector = ScreenSelectionOverlay()
    private let tap = KeyboardTap()

    // MARK: State

    private enum Suggestion {
        case none
        case completion(text: String, midLine: Bool, endedWithSpace: Bool)
        case fix(word: String, fix: String, trailing: String)
        case emoticon(source: String, emoji: String)
    }

    private enum ListKind {
        case none
        case emoji(query: String)
        /// Phrase continuations, inserted at the caret.
        case alternatives([String])
        /// Whole words; `replace` characters (the half-typed word) are deleted first.
        case words([String], replace: Int)
        case synonyms([String])
    }

    /// Which alternatives list is on screen, if any.
    private var altScope: AlternativesScope? {
        guard list.isVisible else { return nil }
        switch listKind {
        case .words: return .word
        case .alternatives: return .phrase
        default: return nil
        }
    }

    private var suggestion: Suggestion = .none
    private var listKind: ListKind = .none
    private var lastContext: TextContext?
    private var debounce: DispatchWorkItem?
    private var laterWork: DispatchWorkItem?
    private var pausedApps: [String: Date] = [:]
    private var pausedUntil: Date?
    /// Global snooze ("pause everywhere for 30 minutes"); nil = not snoozed.
    private var snoozedUntil: Date?
    /// The suggestion on screen sits where Tab means "indent" (list marker / indentation): Tab passes through.
    private var tabIndents = false
    private var keyCount = 0
    private let focus = FocusObserver()
    private var scrollMonitor: Any?
    /// Small cache of recent prompt -> completion results (avoids recomputing identical requests).
    private var resultCache = BoundedCache<String, LLMEngine.Completion>(limit: 12)
    private var lastActivityReport = Date.distantPast

    // Tab chaining: keep suggestions flowing while the user accepts with Tab.
    /// Context + full text of the suggestion on screen (for predicting the text after it's accepted).
    private var anchor: (ctx: TextContext, text: String)?
    /// Prefix when `suggestion` was generated/updated, to reconcile 1-keystroke AX lag or spaces on Tab.
    private var suggestionPrefix: String?
    /// Where the caret will be once the app has processed what we (or the user) just typed.
    private var predictedCaret: Int?
    /// Until then, Tab/full-accept presses are swallowed: the next suggestion is on its way.
    private var chainUntil = Date.distantPast
    private var lastAcceptAt = Date.distantPast
    /// Bumped on every accept/invalidate so stale "after insert" callbacks bail out.
    private var editSeq = 0
    private var insertPending = false
    private var requestInFlight = false
    /// When the flags above were last raised (the watchdog clears them if a callback never came back).
    private var lastInsertStarted = Date.distantPast
    private var lastRequestStarted = Date.distantPast
    /// Canvas editors (Google Docs) hide their text: what was typed in the browser, kept here instead.
    private var browserTypedBuffer = ""
    private var browserTypedPID: pid_t = 0
    private var lookupRequest = 0
    private var rewriteRequest = 0
    /// Look-ahead request for the text after the current suggestion, and refreshes waiting for it.
    private var specKey: String?
    private var specWaiters: [(LLMEngine.Completion) -> Void] = []

    /// Per-field session: stable prompt header + whether the user accepted anything here.
    private struct Session {
        var fieldKey = ""
        var header = ""
        var accepted = false
        var screen: String?
        var filteredScreen: String?
        var clipboard: String?
        var clipChange = -1
        var examples: [String] = []
        /// The screen text came from a manual capture (gets more room in the prompt).
        var screenManual = false
        /// Other fields of the same window (subject, recipients…), read once per field.
        var fields: String?
        /// Learned writing style for this app.
        var style: String?
        /// Recalled memories in the header, and whether recall already ran for this field.
        var memory: String?
        var memoryIDs: [UUID] = []
        var memoryChecked = false
        /// Microphone transcript in the header, and when it was put there.
        var audio = ""
        var audioAt = Date.distantPast
    }
    private var session = Session()

    /// What was written in each field during the current burst; turned into memories when idle.
    private struct Tracked {
        let app: String
        let appName: String
        var base: String
        var last: String
        var committed: [String]
    }
    private var burst: [String: Tracked] = [:]
    /// Characters typed since the last refresh: tells which part of a field's text is new on first sight.
    private var typedSinceRefresh = 0

    /// Writing activity: idle/wake detection and "when the user pauses" callbacks, without timers per key.
    private let activity = Activity()
    /// Field the last screen-context decision was made for (to detect coming back to a field).
    private var lastScreenField = ""
    /// Field whose screenshot is being processed right now.
    private var screenPendingKey: String?
    /// A suggestion request parked until the screenshot it should use is ready (with a timeout).
    private var screenHoldWork: DispatchWorkItem?
    private var screenHoldForce = false
    /// Seconds without typing after which the app goes quiet.
    private var idleSeconds: TimeInterval {
        prefs.sleepAfterSeconds > 0 ? TimeInterval(prefs.sleepAfterSeconds) : 60
    }

    var onStatsChange: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Called (throttled) while the user is typing; used for idle model unloading.
    var onActivity: (() -> Void)?
    /// Called when a suggestion is wanted but the model was unloaded to save memory.
    var onNeedModel: (() -> Void)?
    /// Called (rate-limited) when the engine failed or the GPU stopped answering: the app reloads the model.
    var onEngineFailure: (() -> Void)?
    /// Called by the quick menu's Restart: the app restarts every service in place.
    var onRestart: (() -> Void)?
    private var lastRecovery = Date.distantPast
    private var secureInputLogged = false
    private var contextFailures = 0
    var isTapRunning: Bool { tap.isRunning }

    init(engine: LLMEngine) {
        self.engine = engine
        tap.handler = { [weak self] event, type in self?.handle(event, type) ?? false }
        list.onPick = { [weak self] i in self?.pickListItem(i) }
        lookup.onSelectArea = { [weak self] in self?.startAreaLookup() }
        lookup.onAskQuestion = { [weak self] q in self?.performLookup(query: q, rect: nil) }
        TempCache.controller = self
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.invalidate(); self?.list.hide(); self?.quickMenu.hide(); self?.statusChanged() }
        focus.onChange = { [weak self] in self?.pollFocus() }
        // Self-healing event tap: re-check it whenever the system may have broken it. Event-driven, no polling.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.tap.ensureRunning(reason: note.name.rawValue.replacingOccurrences(of: "NSWorkspace", with: ""))
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    AX.enableManualAccessibility(app.processIdentifier, force: true)   // re-arm Electron/Chromium text trees
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.tap.ensureRunning(reason: "screen unlocked")
        }
        activity.idleAfter = { [weak self] in self?.idleSeconds ?? 60 }
        activity.onWake = { [weak self] in self?.didWake() }
        activity.onIdle = { [weak self] in self?.didGoIdle() }
        AudioContext.shared.addListener { [weak self] in
            guard let self, self.prefs.micContextEnabled else { return }
            let live = AudioContext.shared.transcript
            guard live != self.session.audio else { return }
            // Avoid invalidating the KV cache every 2.5s mid-sentence while actively typing fast.
            guard self.activity.quietFor > 1.2 || Date().timeIntervalSince(self.session.audioAt) >= 6 else { return }
            self.session.audio = live
            self.session.audioAt = Date()
            self.resultCache.removeAll()
            if let ctx = self.lastContext { self.rebuildHeader(ctx) }
        }
    }

    private func updateScrollMonitor() {
        let needed = ghost.isVisible || list.isVisible
        if needed, scrollMonitor == nil {
            scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
                guard let self, !self.list.contains(NSEvent.mouseLocation) else { return }
                self.invalidate()
                self.list.hide(); self.listKind = .none
                self.updateScrollMonitor()
            }
        } else if !needed, let m = scrollMonitor {
            NSEvent.removeMonitor(m)
            scrollMonitor = nil
        }
    }

    func startTap() -> Bool { tap.start() }

    private var frontBundleID: String { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" }

    // MARK: Pausing

    func isPaused(_ bundleID: String) -> Bool {
        guard let until = pausedApps[bundleID] else { return false }
        if until < Date() { pausedApps[bundleID] = nil; return false }
        return true
    }

    func togglePause(_ bundleID: String, minutes: Double = 10) {
        if isPaused(bundleID) {
            pausedApps[bundleID] = nil
            announce(L("Resumed in \(frontAppName)", "Ripreso in \(frontAppName)"), symbol: "play.fill")
        } else {
            pausedApps[bundleID] = Date().addingTimeInterval(minutes * 60); invalidate()
            announce(L("Paused in \(frontAppName) for \(Int(minutes)) min", "In pausa in \(frontAppName) per \(Int(minutes)) min"), symbol: "pause.fill")
        }
    }

    func toggleEverywhere() {
        settings.prefs.globallyDisabled.toggle()
        invalidate(); list.hide()
        announce(prefs.globallyDisabled ? L("\(Brand.name) is off", "\(Brand.name) è spento") : L("\(Brand.name) is on", "\(Brand.name) è attivo"),
                 symbol: prefs.globallyDisabled ? "power" : "checkmark.circle.fill")
    }

    func toggleApp(_ id: String, name: String) {
        let on = settings.isEnabled(in: id)
        settings.updateConfig(id) { $0.enabled = on ? .off : .on }
        invalidate()
        announce(on ? L("Off in \(name)", "Spento in \(name)") : L("On in \(name)", "Attivo in \(name)"), symbol: on ? "nosign" : "checkmark.circle.fill")
    }

    /// Pauses completions everywhere for `minutes` (nil resumes).
    func snooze(minutes: Double?) {
        snoozedUntil = minutes.map { Date().addingTimeInterval($0 * 60) }
        if minutes != nil { invalidate(); list.hide() }
        Log.info(minutes.map { "snooze: paused everywhere for \(Int($0)) min" } ?? "snooze: resumed")
        if let m = minutes {
            announce(L("Paused everywhere for ", "In pausa ovunque per ") + (m >= 60 ? "\(Int(m / 60)) h" : "\(Int(m)) min"), symbol: "pause.fill")
        } else {
            announce(L("Resumed", "Ripreso"), symbol: "play.fill")
        }
    }

    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        if until < Date() { snoozedUntil = nil; return false }
        return true
    }

    /// "until 15:40" for menus.
    var snoozeEndText: String? {
        guard isSnoozed, let until = snoozedUntil else { return nil }
        return Fmt.time(until)
    }

    private var hasSuggestion: Bool {
        if case .none = suggestion { return false }
        return ghost.isVisible
    }

    // MARK: Event handling (main thread, must stay fast)

    private func handle(_ event: CGEvent, _ type: CGEventType) -> Bool {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Our own window: only the global toggle and the quick menu work, never while recording a shortcut.
            guard !ShortcutRecorder.isRecording else { return false }
            if type == .keyDown { return handleKey(event, ownApp: true) }
            // After a search from the ⌃⌥L bar NexoLLM is the active app: clicks land here, and still close the card.
            if type == .leftMouseDown || type == .rightMouseDown, lookup.shouldClose(onClickAt: NSEvent.mouseLocation) { lookup.hide() }
            if quickMenu.isVisible, type != .scrollWheel, !quickMenu.contains(NSEvent.mouseLocation) { quickMenu.hide() }
            return false
        }
        switch type {
        case .keyDown: return handleKey(event)
        case .leftMouseUp:
            if prefs.synonyms == .auto { scheduleSelectionCheck() }
            return false
        default:
            if type == .leftMouseDown { browserTypedBuffer = "" }   // the caret may have moved
            if type == .leftMouseDown || type == .rightMouseDown, lookup.shouldClose(onClickAt: NSEvent.mouseLocation) { lookup.hide() }
            if quickMenu.isVisible {
                if quickMenu.contains(NSEvent.mouseLocation) { return false }   // clicking a row of the menu
                if type != .scrollWheel { quickMenu.hide() }
            }
            guard hasSuggestionPending || list.isVisible else { return false }   // nothing on screen: zero work
            if list.contains(NSEvent.mouseLocation) { return false }   // clicking a row of the list
            invalidate()
            list.hide(); listKind = .none
            return false
        }
    }

    private func handleKey(_ event: CGEvent, ownApp: Bool = false) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.intersection(Shortcut.relevant)
        keyCount += 1
        if keyCount <= 3 || keyCount % 100 == 0 { Log.write("tap: keyDown #\(keyCount) code=\(key)") }

        if let g = prefs.globalToggleShortcut, g.matches(key, flags) {
            DispatchQueue.main.async { self.toggleEverywhere() }
            return true
        }
        if prefs.restartShortcut.matches(key, flags) {
            DispatchQueue.main.async { self.onRestart?() }
            return true
        }
        if screenSelector.isVisible {
            if flags.isEmpty, key == kVK_Escape { screenSelector.hide(); return true }
            return false
        }
        // Quick menu open: it owns ↑/↓, ←/→ (to open/close dropdowns), ↩/⇥, 1–9, ⇧1–⇧9 (only when a dropdown is open) and ⎋; any other key closes it.
        if quickMenu.isVisible, !prefs.quickMenuShortcut.matches(key, flags) {
            if flags.isEmpty, key == kVK_DownArrow || key == kVK_UpArrow {
                quickMenu.moveSelection(key == kVK_DownArrow ? 1 : -1); return true
            }
            if flags.isEmpty, key == kVK_RightArrow {
                quickMenu.expandRight(); return true
            }
            if flags.isEmpty, key == kVK_LeftArrow {
                quickMenu.collapseLeft(); return true
            }
            if flags.isEmpty, key == kVK_Return || key == kVK_Tab {
                quickMenu.activateCurrent(); return true
            }
            if flags.isEmpty, let d = digitValue(key), d <= quickMenu.items.count { quickMenu.activate(d - 1); return true }
            if flags == .maskShift, quickMenu.hasExpandedSubmenu, let d = digitValue(key) {
                quickMenu.activateSubitem(d - 1); return true
            }
            if key == kVK_Shift || key == kVK_RightShift { return false }
            quickMenu.hide()
            if flags.isEmpty, key == kVK_Escape { return true }
        }
        if prefs.quickMenuShortcut.matches(key, flags) {
            // Never run a menu inside the event tap: it would hold every keystroke on the system.
            DispatchQueue.main.async { [weak self] in self?.invalidate(); self?.showQuickMenu() }
            return true
        }
        if lookup.isVisible, flags.isEmpty, key == kVK_Escape { lookup.hide(); return true }
        if prefs.webLookupShortcut.matches(key, flags) {
            DispatchQueue.main.async { [weak self] in self?.lookUpNow() }
            return true
        }
        if ownApp { return false }
        guard !prefs.globallyDisabled else { return false }
        activity.keystroke()
        healStuckState()
        if let s = typedString(event) { typedSinceRefresh += s.count }
        trackBrowserTyping(event, key: key, flags: flags)
        let app = frontBundleID

        if prefs.toggleAppShortcut.matches(key, flags) { togglePause(app); return true }
        if prefs.forceShortcut.matches(key, flags) { invalidate(); refresh(force: true); return true }
        if prefs.captureShortcut.matches(key, flags) { captureScreenNow(); return true }

        // ⌥Tab: alternatives for the word being written; pressed again, the same key switches Word ⇄ Phrase.
        if prefs.alternativesShortcut.matches(key, flags) {
            if let scope = altScope { showAlternatives(scope: scope.other); return true }
            if prefs.synonyms != .off, showSynonymsIfSelection() { return true }
            if prefs.alternatives != .off { showAlternatives(scope: prefs.alternativesScope); return true }
        }

        // Numbered list (emoji / alternatives / synonyms): ↑/↓ move the highlight, ↩/⇥ insert it, 1–9 pick directly.
        if list.isVisible {
            if flags.isEmpty, let digit = digitValue(key), digit >= 1, digit <= list.items.count {
                pickListItem(digit - 1); return true
            }
            if flags.isEmpty, key == kVK_DownArrow || key == kVK_UpArrow {
                list.moveSelection(key == kVK_DownArrow ? 1 : -1); return true
            }
            // ←/→ switch Word ⇄ Phrase.
            if let scope = altScope, flags.isEmpty, key == kVK_LeftArrow || key == kVK_RightArrow {
                let target: AlternativesScope = key == kVK_LeftArrow ? .word : .phrase
                if target != scope { showAlternatives(scope: target) }
                return true
            }
            if flags.isEmpty, key == kVK_Escape { list.hide(); listKind = .none; return true }
            if flags.isEmpty, key == kVK_Tab || key == kVK_Return {
                if !list.loading { pickListItem(list.selectedIndex) }
                return true
            }
            if case .emoji = listKind {} else { list.hide(); listKind = .none }
        }

        if hasSuggestion {
            let tabBlocked = settings.tabDisabled(in: app) && prefs.nextWordShortcut.keyCode == Int64(kVK_Tab)
            if prefs.nextWordShortcut.matches(key, flags), !tabBlocked {
                // Smart Tab: at a list marker / indentation Tab keeps indenting (Obsidian, Notes, editors);
                // the full-completion key still accepts there.
                if tabIndents { invalidate(); return false }
                acceptWord(); return true
            }
            if prefs.fullCompletionShortcut.matches(key, flags) { acceptAll(); return true }
            if flags.isEmpty, key == kVK_Escape { escape(app: app); return true }
        } else if Date() < chainUntil,
                  prefs.nextWordShortcut.matches(key, flags) || prefs.fullCompletionShortcut.matches(key, flags) {
            // Just accepted the end of a suggestion and the next one is on its way:
            // never let Tab type a tab/space into the document. Kick a refresh if nothing is pending.
            if !insertPending, !requestInFlight, specKey == nil { refresh(force: true) }
            return true
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            invalidate(); scheduleRefresh(); return false
        }

        let navigation: Set<Int64> = [Int64(kVK_LeftArrow), Int64(kVK_RightArrow), Int64(kVK_UpArrow), Int64(kVK_DownArrow),
                                      Int64(kVK_Home), Int64(kVK_End), Int64(kVK_PageUp), Int64(kVK_PageDown),
                                      Int64(kVK_Escape), Int64(kVK_Tab)]
        if navigation.contains(key) {
            invalidate()
            if flags.contains(.maskShift), prefs.synonyms == .auto { scheduleSelectionCheck() }
            return false
        }

        // Typing the same characters as the suggestion: consume them, no new inference.
        if case let .completion(text, mid, sp) = suggestion, ghost.isVisible,
           let rawTyped = typedString(event), !rawTyped.isEmpty {
            let typed = SuggestionText.normalizeSpaces(rawTyped)
            if text.hasPrefix(typed) {
                let rest = String(text.dropFirst(typed.count))
                engine.generation.next(); debounce?.cancel()
                if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                    invalidate(); scheduleRefresh()
                } else {
                    suggestion = .completion(text: rest, midLine: mid, endedWithSpace: sp)
                    suggestionPrefix = suggestionPrefix.map { $0 + typed }
                    tabIndents = false
                    predictedCaret = predictedCaret.map { $0 + (rawTyped as NSString).length }
                    repositionAfterInsert()
                }
                return false
            }
        }

        invalidate()
        scheduleRefresh()
        return false
    }

    private func digitValue(_ key: Int64) -> Int? {
        let map: [Int: Int] = [kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
                               kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9]
        return map[Int(key)]
    }

    private func typedString(_ event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        return s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) ? s : nil
    }

    /// Watchdog: a dropped callback must never leave suggestions blocked until the app is restarted.
    private func healStuckState() {
        let request = Date().timeIntervalSince(lastRequestStarted)
        if requestInFlight, request > 2.5 {
            Log.info("watchdog: completion request stuck for \(Int(request)) s — cleared")
            requestInFlight = false
            if request > 10 { recoverEngine("completion never returned") }
        }
        if insertPending, Date().timeIntervalSince(lastInsertStarted) > 1.5 {
            Log.info("watchdog: insert wait stuck — cleared")
            insertPending = false
        }
    }

    /// Keeps what's typed in a browser, for canvas editors that hide their text (Google Docs).
    private func trackBrowserTyping(_ event: CGEvent, key: Int64, flags: CGEventFlags) {
        guard let front = NSWorkspace.shared.frontmostApplication, AX.browserBundles.contains(front.bundleIdentifier ?? "") else { return }
        if front.processIdentifier != browserTypedPID { browserTypedPID = front.processIdentifier; browserTypedBuffer = "" }
        let moves: Set<Int> = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown]
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || moves.contains(Int(key)) { browserTypedBuffer = ""; return }
        if key == kVK_Delete { browserTypedBuffer = String(browserTypedBuffer.dropLast()); return }
        if key == kVK_Return { browserTypedBuffer += "\n"; return }
        if let s = typedString(event) { browserTypedBuffer = String((browserTypedBuffer + s).suffix(600)) }
    }

    /// In a canvas editor, the context with what was typed there as the text before the caret.
    private func withTypedBuffer(_ c: TextContext?) -> TextContext? {
        guard let c, c.canvasEditor, c.prefix.isEmpty, !browserTypedBuffer.isEmpty, c.pid == browserTypedPID else { return c }
        return TextContext(pid: c.pid, bundleID: c.bundleID, appName: c.appName, element: c.element,
                           caretLocation: (browserTypedBuffer as NSString).length, prefix: browserTypedBuffer, prefixStart: 0,
                           after: "", atLineEnd: false, caretRect: c.caretRect, fontSize: c.fontSize, fieldFrame: c.fieldFrame,
                           canvasEditor: true)
    }

    private func backspace(_ count: Int) {
        browserTypedBuffer = String(browserTypedBuffer.dropLast(count))
        DispatchQueue.main.async {
            TextInjector.backspace(count)
        }
    }

    private func escape(app: String) {
        invalidate()
        switch prefs.escapeBehavior {
        case .pause: pausedUntil = Date().addingTimeInterval(4)
        case .dismiss: break
        case .disableApp: togglePause(app)
        }
    }

    // MARK: Inserting

    private func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let usePaste = text.contains("\n") || settings.config(frontBundleID).compatibility
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == browserTypedPID {
            browserTypedBuffer = String((browserTypedBuffer + text).suffix(600))
        }
        DispatchQueue.main.async {
            if usePaste {
                TextInjector.paste(text)
            } else {
                TextInjector.type(text)
            }
        }
    }

    /// Click and session bookkeeping. Insights only count words accepted with the word / full-accept keys.
    private func credit(_ words: Int, countInStats: Bool = false) {
        KeyClickSound.play()
        session.accepted = true
        guard countInStats else { return }
        Stats.shared.record(words: max(1, words), app: frontBundleID)
        onStatsChange?()
    }

    private func acceptWord() {
        switch suggestion {
        case let .completion(text, mid, sp):
            let live = withTypedBuffer(AX.currentContext())?.prefix
            let reconciled = SuggestionText.reconcile(suggestion: text, basePrefix: suggestionPrefix, livePrefix: live)
            if reconciled.trimmingCharacters(in: .whitespaces).isEmpty {
                invalidate()
                scheduleRefresh()
                return
            }
            let (word, rest) = SuggestionText.splitNextWord(reconciled, trailingSpace: prefs.trailingSpace)
            engine.generation.next(); debounce?.cancel()
            // The user is chaining with Tab: start computing what comes after this suggestion right away.
            if !mid { prefetchNext() }
            insert(word)
            credit(SuggestionText.wordCount(word), countInStats: true)
            if !session.memoryIDs.isEmpty { Memory.shared.reinforce(session.memoryIDs, with: word) }
            lastAcceptAt = Date()
            predictedCaret = predictedCaret.map { $0 + (word as NSString).length }
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                finishChain()
            } else {
                editSeq += 1
                suggestion = .completion(text: rest, midLine: mid, endedWithSpace: sp)
                suggestionPrefix = (live ?? suggestionPrefix).map { $0 + word }
                repositionAfterInsert()
            }
        case .fix, .emoticon:
            acceptAll()
        case .none:
            break
        }
    }

    private func acceptAll() {
        switch suggestion {
        case let .completion(text, _, _):
            let live = withTypedBuffer(AX.currentContext())?.prefix
            let reconciled = SuggestionText.reconcile(suggestion: text, basePrefix: suggestionPrefix, livePrefix: live)
            if reconciled.trimmingCharacters(in: .whitespaces).isEmpty {
                invalidate()
                scheduleRefresh()
                return
            }
            insert(reconciled)
            credit(SuggestionText.wordCount(reconciled), countInStats: true)
            if !session.memoryIDs.isEmpty { Memory.shared.reinforce(session.memoryIDs, with: reconciled) }
            lastAcceptAt = Date()
            predictedCaret = predictedCaret.map { $0 + (reconciled as NSString).length }
            finishChain()
            return
        case let .fix(word, fix, trailing):
            backspace(word.count + trailing.count)
            insert(fix + trailing)
            credit(1)
        case let .emoticon(source, emoji):
            backspace(source.count)
            insert(emoji)
            credit(1)
        case .none:
            return
        }
        invalidate()
        scheduleRefresh(after: 80)
    }

    /// The whole suggestion has been inserted: as soon as the app shows it, suggest what comes next
    /// (usually instant, thanks to the look-ahead). Tab presses meanwhile are swallowed.
    private func finishChain() {
        let expected = predictedCaret
        invalidate(keepSpeculation: true)
        chainUntil = Date().addingTimeInterval(1.5)
        afterInsert(expectedCaret: expected) { [weak self] ctx in
            self?.refresh(force: false, context: ctx, chained: true)
        }
    }

    private func pickListItem(_ index: Int) {
        defer { list.hide(); listKind = .none }
        switch listKind {
        case let .emoji(query):
            guard index < list.items.count else { return }
            backspace(query.count + 1)   // ":" + query
            insert(list.items[index].leading)
            credit(1)
        case let .alternatives(texts):
            guard index < texts.count else { return }
            invalidate()
            insert(texts[index])
            credit(SuggestionText.wordCount(texts[index]))
            scheduleRefresh(after: 80)
        case let .words(words, replace):
            guard index < words.count else { return }
            invalidate()
            backspace(replace)
            insert(words[index] + (prefs.trailingSpace ? " " : ""))
            credit(1)
            scheduleRefresh(after: 80)
        case let .synonyms(words):
            guard index < words.count else { return }
            insert(words[index])   // typing over the selection replaces it
            credit(1)
        case .none:
            break
        }
    }

    // MARK: Suggestions lifecycle

    func invalidate(keepSpeculation: Bool = false) {
        engine.generation.next()
        debounce?.cancel()
        laterWork?.cancel()
        screenHoldWork?.cancel()
        screenHoldWork = nil
        suggestion = .none
        suggestionPrefix = nil
        tabIndents = false
        ghost.hide()
        if list.loading { list.hide(); listKind = .none }   // its request was just cancelled: never leave it stuck
        updateScrollMonitor()
        editSeq += 1
        anchor = nil
        if !keepSpeculation {
            cancelSpeculation()
            predictedCaret = nil
            chainUntil = .distantPast
        }
    }

    /// Restarts every service in place (the app stays open): event tap, overlay windows, stuck state, caches.
    func softRestart() {
        invalidate()
        requestInFlight = false
        insertPending = false
        screenPendingKey = nil
        pausedUntil = nil
        contextFailures = 0
        browserTypedBuffer = ""
        list.hide(); listKind = .none
        quickMenu.hide(); lookup.hide(); screenSelector.hide()
        ghost.rebuildPanel(); list.rebuildPanel(); toast.rebuildPanel(); quickMenu.rebuildPanel(); lookup.rebuildPanel()
        _ = tap.restart()
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != ProcessInfo.processInfo.processIdentifier {
            AX.enableManualAccessibility(pid, force: true)
        }
        clearCaches()
        announce(L("\(Brand.name) restarted", "\(Brand.name) riavviato"), symbol: "arrow.clockwise")
    }

    private func cancelSpeculation() {
        guard specKey != nil else { return }
        engine.specGeneration.next()
        specKey = nil
        specWaiters = []
    }

    private func scheduleRefresh(after ms: Double? = nil) {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh(force: false) }
        debounce = work
        let delay = ms ?? prefs.debounceMs
        DispatchQueue.main.asyncAfter(deadline: .now() + delay / 1000, execute: work)
    }

    /// The engine failed or the GPU stopped answering (typically after sleep): reload the model, at most
    /// every 20 s, instead of silently showing nothing until the app is restarted.
    private func recoverEngine(_ reason: String) {
        guard Date().timeIntervalSince(lastRecovery) > 20 else { return }
        lastRecovery = Date()
        Log.info("recovery: \(reason) — reloading the model")
        onEngineFailure?()
    }

    /// Waits until the app has applied our synthetic keystrokes (caret at `expectedCaret`), polling AX
    /// every 15 ms for up to ~300 ms, instead of guessing a fixed delay. Slow apps (Electron/web) need it.
    private func afterInsert(expectedCaret: Int?, attempt: Int = 0, token: Int? = nil, _ body: @escaping (TextContext?) -> Void) {
        let token = token ?? { insertToken += 1; return insertToken }()
        if attempt == 0 { lastInsertStarted = Date() }
        insertPending = true
        let seq = editSeq
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.02 : 0.015)) { [weak self] in
            guard let self else { return }
            guard seq == self.editSeq else {   // a newer accept/keystroke took over
                if token == self.insertToken { self.insertPending = false }   // never leave the flag stuck
                return
            }
            let ctx = self.withTypedBuffer(AX.currentContext())
            if attempt < 20, ctx == nil || (expectedCaret != nil && ctx?.caretLocation != expectedCaret) {
                self.afterInsert(expectedCaret: expectedCaret, attempt: attempt + 1, token: token, body); return
            }
            if token == self.insertToken { self.insertPending = false }
            body(ctx)
        }
    }
    private var insertToken = 0

    /// Moves the remaining suggestion to the new caret once the app has caught up.
    private func repositionAfterInsert() {
        afterInsert(expectedCaret: predictedCaret) { [weak self] ctx in
            guard let self, self.hasSuggestionPending else { return }
            guard let ctx else { self.invalidate(); return }
            self.lastContext = ctx
            self.predictedCaret = ctx.caretLocation
            self.render(ctx)
        }
    }

    private var hasSuggestionPending: Bool {
        if case .none = suggestion { return false }
        return true
    }

    private var keyLabel: String { tabIndents ? prefs.fullCompletionShortcut.display : prefs.nextWordShortcut.display }

    private func render(_ ctx: TextContext) {
        tabIndents = prefs.smartTab && prefs.nextWordShortcut.keyCode == Int64(kVK_Tab)
            && SuggestionText.isIndentPosition(ctx.prefix)
        switch suggestion {
        case let .completion(text, mid, _):
            if mid {
                ghost.showBubble(Text(text.trimmingCharacters(in: .whitespaces)).font(.system(size: 12.5)),
                                 caretAX: ctx.caretRect, keyLabel: keyLabel, id: text)
            } else {
                // Highlight what one press of the next-word key inserts (whole text when Tab is indenting).
                let head = tabIndents ? "" : SuggestionText.splitNextWord(text, trailingSpace: false).word
                // Ghost color follows the page under the caret (light page in dark mode, and vice versa).
                let tone = Backdrop.shared.tone(for: ctx.fieldKey, caretAX: ctx.caretRect) { [weak self] _ in
                    guard let self, self.hasSuggestionPending, let last = self.lastContext,
                          last.fieldKey == ctx.fieldKey else { return }
                    self.render(last)
                }
                ghost.showInline(text, caretAX: ctx.caretRect, fontSize: ctx.fontSize, keyLabel: keyLabel, head: head, tone: tone)
            }
        case let .fix(word, fix, _):
            ghost.showBubble(HStack(spacing: 6) {
                Text(word).strikethrough(color: Theme.rose.opacity(0.8)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.aurora)
                Text(fix).fontWeight(.semibold)
            }.font(.system(size: 12.5)), caretAX: ctx.caretRect, keyLabel: keyLabel, id: "fix \(word) \(fix)")
        case let .emoticon(source, emoji):
            ghost.showBubble(HStack(spacing: 6) {
                Text(source).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.aurora)
                Text(emoji).font(.system(size: 15))
            }, caretAX: ctx.caretRect, keyLabel: keyLabel, id: "emoticon \(source) \(emoji)")
        case .none:
            ghost.hide()
        }
        updateStatus(ctx, state: .active)
        updateScrollMonitor()
    }

    // MARK: Status (menu bar icon)

    /// Whether NexoLLM works in the app in front right now. Drives the menu bar icon; nothing floats over
    /// the text anymore.
    var isActiveInFrontApp: Bool {
        let app = frontBundleID
        return !prefs.globallyDisabled && !isSnoozed && settings.isEnabled(in: app) && !isPaused(app)
            && !IsSecureEventInputEnabled()
    }
    /// Called when `isActiveInFrontApp` may have changed.
    var onStatusChange: (() -> Void)?
    private var lastStatus: Bool?

    private func statusChanged() {
        let now = isActiveInFrontApp
        guard now != lastStatus else { return }
        lastStatus = now
        onStatusChange?()
    }

    private func updateStatus(_ ctx: TextContext?, state: ActivityState) {
        // Secure Event Input (a password field, or an app that leaves it on) blocks every keyboard tap.
        let secure = IsSecureEventInputEnabled()
        if secure != secureInputLogged {
            secureInputLogged = secure
            Log.info(secure ? "secure input is ON: keystrokes are hidden from NexoLLM until it's released"
                            : "secure input released")
        }
        statusChanged()
    }

    /// Focus moved between fields without typing: only the menu bar icon may need an update.
    private func pollFocus() { statusChanged() }

    /// Short confirmation near the caret after a state change from the keyboard or a menu.
    private func announce(_ text: String, symbol: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.toast.show(text, symbol: symbol, nearAX: AX.currentContext()?.caretRect, duration: 1.1)
        }
        statusChanged()
    }

    private var frontAppName: String { NSWorkspace.shared.frontmostApplication?.localizedName ?? L("this app", "questa app") }

    /// Opens the quick menu at the caret (or the mouse) without leaving the app you're typing in.
    /// Opens the floating ⌃⌥M Quick Menu at the text caret/selection when a textbox is focused,
    /// or at the mouse cursor when no textbox is focused.
    /// Maximum 8 top-level items (numbered 1–8), with dropdown submenus activated by ⇧1–⇧9 when open.
    func showQuickMenu() {
        if quickMenu.isVisible { quickMenu.hide(); return }
        toast.hide(); list.hide(); listKind = .none
        let front = NSWorkspace.shared.frontmostApplication
        let id = front?.bundleIdentifier ?? ""
        let name = front?.localizedName ?? id
        var items: [QuickMenuItem] = []

        // Capture selection or draft paragraph right at the caret (including end-of-word without trailing space).
        let liveAXCtx = AX.currentContext()
        let capturedSel = AX.currentSelection(maxChars: 1000, maxWords: 180)
        let capturedCtx = withTypedBuffer(liveAXCtx) ?? lastContext

        let executeRewrite: (String) -> Void = { [weak self] instruction in
            guard let self else { return }
            if let liveSel = AX.currentSelection(maxChars: 1000, maxWords: 180) ?? capturedSel,
               !liveSel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.rewriteSelection(liveSel, instruction: instruction, replaceDraftCount: 0, trailingWhitespace: "")
                return
            }
            let ctx = self.withTypedBuffer(AX.currentContext()) ?? capturedCtx
            let prefix = ctx?.prefix ?? self.browserTypedBuffer
            guard let target = Self.draftTargetForRewrite(prefix) else {
                self.toast.show(L("Select text or write a word/sentence first", "Seleziona un testo o scrivi prima una parola o frase"),
                                symbol: "text.cursor", nearAX: ctx?.caretRect, duration: 2)
                return
            }
            let sel = AX.Selection(
                text: target.text,
                rect: ctx?.caretRect ?? AX.mouseAXRect(),
                pid: front?.processIdentifier ?? 0,
                bundleID: id,
                before: String(prefix.dropLast(min(prefix.count, target.replaceCount)))
            )
            self.rewriteSelection(sel, instruction: instruction, replaceDraftCount: target.replaceCount, trailingWhitespace: target.trailingWhitespace)
        }

        let languages: [(flag: String, label: String, englishName: String)] = [
            ("🇬🇧", "English", "English"),
            ("🇮🇹", "Italiano", "Italian"),
            ("🇪🇸", "Español", "Spanish"),
            ("🇫🇷", "Français", "French"),
            ("🇩🇪", "Deutsch", "German"),
            ("🇵🇹", "Português", "Portuguese"),
        ]
        let translateSubitems: [QuickMenuItem] = languages.map { lang in
            QuickMenuItem(symbol: "globe", title: "\(lang.flag)  \(lang.label)") {
                executeRewrite("Translate this text into natural \(lang.englishName)")
            }
        }

        var writingSubitems: [QuickMenuItem] = Self.rewrites.map { symbol, title, instruction in
            QuickMenuItem(symbol: symbol, title: title) {
                executeRewrite(instruction)
            }
        }
        writingSubitems.append(QuickMenuItem(symbol: "globe", title: L("Translate…", "Traduci…"), subitems: translateSubitems))

        // 1. Writing Tools dropdown (⇧1..⇧5 when open)
        items.append(QuickMenuItem(symbol: "wand.and.stars", title: L("Writing Tools", "Strumenti di scrittura"), subitems: writingSubitems))

        // 2. Enable / Disable in current app (filled circle ● when active -> says "Disable in <App>", empty circle ○ when off -> says "Enable in <App>")
        if !id.isEmpty, id != Bundle.main.bundleIdentifier {
            let on = settings.isEnabled(in: id)
            items.append(QuickMenuItem(
                symbol: on ? "circle.fill" : "circle",
                title: on ? L("Disable in \(name)", "Disattiva in \(name)") : L("Enable in \(name)", "Attiva in \(name)"),
                badge: on ? L("Active", "Attivo") : L("Off", "Spento")
            ) { [weak self] in
                self?.toggleApp(id, name: name)
            })
        }

        // 3. Pause Suggestions… dropdown (⇧1..⇧4 when open)
        var pauseSubitems: [QuickMenuItem] = []
        let hasApp = !id.isEmpty && id != Bundle.main.bundleIdentifier
        if isSnoozed || prefs.globallyDisabled || (hasApp && isPaused(id)) {
            pauseSubitems.append(QuickMenuItem(symbol: "play.fill", title: L("Resume Suggestions", "Riprendi suggerimenti")) { [weak self] in
                guard let self else { return }
                if self.prefs.globallyDisabled { self.toggleEverywhere() }
                if self.isSnoozed { self.snooze(minutes: nil) }
                if hasApp, self.isPaused(id) { self.togglePause(id) }
            })
        }
        if hasApp, !isPaused(id) {
            pauseSubitems.append(QuickMenuItem(symbol: "timer", title: L("Pause 10m in \(name)", "Pausa 10 min in \(name)")) { [weak self] in
                self?.togglePause(id, minutes: 10)
            })
        }
        pauseSubitems.append(QuickMenuItem(symbol: "pause.circle", title: L("Pause 30m Everywhere", "Pausa 30 min ovunque")) { [weak self] in
            self?.snooze(minutes: 30)
        })
        pauseSubitems.append(QuickMenuItem(symbol: "clock", title: L("Pause 2h Everywhere", "Pausa 2 ore ovunque")) { [weak self] in
            self?.snooze(minutes: 120)
        })
        pauseSubitems.append(QuickMenuItem(
            symbol: "power",
            title: prefs.globallyDisabled ? L("Enable Everywhere", "Attiva ovunque") : L("Disable Indefinitely", "Disabilita indefinitamente")
        ) { [weak self] in
            self?.toggleEverywhere()
        })
        items.append(QuickMenuItem(symbol: "pause.circle", title: L("Pause Suggestions…", "Metti in pausa…"), subitems: pauseSubitems))

        // 4. Unified Smart Web Lookup (combines text lookup + screen area selection + questions)
        items.append(QuickMenuItem(
            symbol: "sparkle.magnifyingglass",
            title: L("Smart Web Lookup", "Ricerca Web intelligente"),
            badge: NetworkMonitor.shared.isOnline ? prefs.webLookupShortcut.display : L("No Wi-Fi", "Senza Wi-Fi")
        ) { [weak self] in
            self?.lookUpNow()
        })

        // 5. Read the Screen Now
        items.append(QuickMenuItem(
            symbol: "text.viewfinder",
            title: L("Read the Screen Now", "Leggi lo schermo ora"),
            badge: prefs.captureShortcut.display
        ) { [weak self] in
            self?.captureScreenNow()
        })

        // 6. Audio Context dropdown (⇧1..⇧4 when open): start/stop and the recognition language.
        let audio = AudioContext.shared
        let lang = audio.activeLanguageShort
        let listening = prefs.micContextEnabled
        let audioBadge = listening ? (lang.isEmpty ? L("On", "Attivo") : L("On", "Attivo") + " · " + lang) : L("Off", "Spento")
        let current = audio.overrideLocale
        var audioSubitems: [QuickMenuItem] = [
            QuickMenuItem(symbol: listening ? "stop.circle" : "mic.fill",
                          title: listening ? L("Stop Listening", "Ferma ascolto") : L("Start Listening", "Avvia ascolto")) { [weak self] in
                self?.toggleAudioContext()
            },
            QuickMenuItem(symbol: current == nil ? "checkmark" : "globe", title: L("Auto (Multilingual)", "Auto (Multilingua)")) {
                audio.overrideLocale = nil
            },
        ]
        for item in AudioContext.speechLocales {
            let isSelected = current == item.locale || String(current?.prefix(2) ?? "").lowercased() == item.iso
            audioSubitems.append(QuickMenuItem(symbol: isSelected ? "checkmark" : "globe", title: "\(item.flag)  \(item.label)") {
                audio.overrideLocale = item.locale
            })
        }
        items.append(QuickMenuItem(symbol: "waveform", title: L("Audio Context", "Contesto audio"),
                                   badge: audioBadge, subitems: audioSubitems))

        // 7. Restart NexoLLM
        items.append(QuickMenuItem(
            symbol: "arrow.clockwise",
            title: L("Restart \(Brand.name)", "Riavvia \(Brand.name)"),
            badge: prefs.restartShortcut.display
        ) { [weak self] in
            self?.onRestart?()
        })

        // 8. Open NexoLLM
        items.append(QuickMenuItem(
            symbol: "macwindow",
            title: L("Open \(Brand.name)", "Apri \(Brand.name)")
        ) { [weak self] in
            self?.onOpenSettings?()
        })

        // If a textbox is actively focused, anchor at the caret / final character; otherwise anchor at the mouse cursor.
        // A rect only counts if it is really on a screen (some apps report a zero or off-screen caret).
        func onScreen(_ r: CGRect?) -> NSRect? {
            guard let r, r.width > 0 || r.height > 0 else { return nil }
            let c = Geometry.toCocoa(r)
            return NSScreen.screens.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(NSPoint(x: c.minX, y: c.minY)) } ? c : nil
        }
        let point: NSPoint
        if let c = onScreen(capturedSel?.rect) ?? onScreen(liveAXCtx?.caretRect) {
            point = NSPoint(x: c.minX, y: c.minY - 4)
        } else {
            let mouse = NSEvent.mouseLocation
            point = NSPoint(x: mouse.x, y: mouse.y - 4)
        }
        let (status, color) = quickStatus(appID: id, appName: name)
        quickMenu.show(status: status, statusColor: color, words: Stats.shared.today.words, items: items, topLeft: point)
    }

    /// Looks up the selection on the web (including highlighted text in external browser pages, WhatsApp, PDFs),
    /// answers the question just written, or opens the screenshot-style area selector + question bar when nothing is highlighted.
    /// Web Lookup is on and there is a connection; otherwise says why and returns false.
    private func webLookupAvailable() -> Bool {
        if !prefs.webLookupEnabled {
            toast.show(L("Web Lookup is turned off in Settings › Behavior", "La ricerca web è disattivata in Impostazioni › Comportamento"),
                       symbol: "globe", nearAX: nil, duration: 2.4)
            return false
        }
        guard NetworkMonitor.shared.isOnline else {
            toast.show(L("Web Lookup needs an internet connection", "La ricerca web richiede una connessione a internet"),
                       symbol: "wifi.slash", nearAX: nil, duration: 2.2)
            return false
        }
        return true
    }

    func lookUpNow() {
        toast.hide()
        guard webLookupAvailable() else { return }
        let ctx = withTypedBuffer(AX.currentContext())
        let typedBuffer = browserTypedBuffer
        AX.selectedTextWithCopyFallback(maxChars: 360) { [weak self] sel in
            guard let self else { return }
            if let sel, sel.text.contains(where: { $0.isLetter }) {
                self.performLookup(query: sel.text, rect: sel.rect)
                return
            }
            let lastSentence = WebLookup.lastSentence(ctx?.prefix ?? typedBuffer)
            if lastSentence.contains("?"), lastSentence.contains(where: { $0.isLetter }) {
                self.performLookup(query: lastSentence, rect: ctx?.caretRect)
                return
            }
            self.startAreaLookup(initialQuery: lastSentence)
        }
    }

    /// Opens the dimmed screenshot-style selection overlay to drag over any text on screen or ask a question.
    func startAreaLookup(initialQuery: String = "") {
        toast.hide()
        guard webLookupAvailable() else { return }
        invalidate(); list.hide(); listKind = .none; lookup.hide()
        screenSelector.begin(
            initialQuery: initialQuery,
            onQuestion: { [weak self] q in
                self?.performLookup(query: q, rect: nil)
            },
            onRegion: { [weak self] axRect in
                guard let self else { return }
                self.toast.show(L("Reading selected area…", "Lettura dell'area selezionata…"), busy: true, nearAX: nil)
                Task {
                    let recognized = await ScreenContext.recognizeRegion(axRect)
                    await MainActor.run {
                        self.toast.hide()
                        guard let text = recognized, text.contains(where: { $0.isLetter }) else {
                            self.toast.show(L("No readable text in the selected area", "Nessun testo leggibile nell'area selezionata"),
                                            symbol: "eye.slash", nearAX: nil, duration: 2.4)
                            return
                        }
                        self.performLookup(query: text, rect: axRect)
                    }
                }
            }
        )
    }

    private func performLookup(query rawQuery: String, rect: CGRect?) {
        let query = WebLookup.cleanQuery(rawQuery)
        guard query.contains(where: { $0.isLetter }) else { return }
        invalidate(); list.hide(); listKind = .none
        lookup.showLoading(query: query, nearAX: rect)
        lookupRequest += 1
        let request = lookupRequest
        let answerer: (String, @escaping (String?) -> Void) -> Void = { [weak self] prompt, done in
            guard let self else { done(nil); return }
            guard self.prepareModel() else { done(nil); return }
            let id = self.engine.taskGeneration.next()
            self.engine.complete(prompt: prompt + " \"", maxTokens: 120, id: id, instruction: true) { result in
                done(Self.rewriteResult(result?.text))
            }
        }
        WebLookup.search(rawQuery: rawQuery, answerWith: answerer) { [weak self] result in
            guard let self, request == self.lookupRequest, self.lookup.isVisible else { return }
            switch result {
            case .success(let card): self.lookup.show(card: card, nearAX: rect)
            case .failure:
                self.lookup.hide()
                self.toast.show(L("Nothing found online", "Nessun risultato online"), symbol: "globe", nearAX: nil, duration: 2.4)
            }
        }
    }

    /// Symbol, title (app language) and the instruction for the model (always English).
    private static var rewrites: [(String, String, String)] { [
        ("wand.and.stars", L("Improve Writing", "Migliora il testo"), "Improve clarity and flow, keeping the same language and meaning"),
        ("checkmark.seal", L("Fix Grammar", "Correggi la grammatica"), "Fix grammar, spelling and punctuation only, keeping the same language"),
        ("briefcase", L("Make Formal", "Rendi formale"), "Rewrite in a formal, polite and professional tone in the same language"),
        ("arrow.down.right.and.arrow.up.left", L("Make Shorter", "Accorcia"), "Make this more concise in the same language"),
    ] }

    /// Extracts the current paragraph/line right before the caret (including all sentences in the paragraph)
    /// when no text is explicitly highlighted, along with the exact character count to backspace (`replaceCount`)
    /// and any trailing spaces (`trailingWhitespace`).
    static func draftTargetForRewrite(_ prefix: String) -> (text: String, replaceCount: Int, trailingWhitespace: String)? {
        guard !prefix.isEmpty else { return nil }
        let currentLine: Substring
        if let lastNewline = prefix.lastIndex(of: "\n") {
            let afterNL = prefix[prefix.index(after: lastNewline)...]
            if afterNL.contains(where: { $0.isLetter }) {
                currentLine = afterNL
            } else {
                return nil
            }
        } else {
            currentLine = prefix[...]
        }

        // Separate any trailing spaces/tabs right before the caret.
        var contentEnd = currentLine.endIndex
        while contentEnd > currentLine.startIndex, currentLine[currentLine.index(before: contentEnd)].isWhitespace {
            contentEnd = currentLine.index(before: contentEnd)
        }
        let trailingWS = String(currentLine[contentEnd...])
        let content = currentLine[..<contentEnd]
        guard content.contains(where: { $0.isLetter }) else { return nil }

        // Skip any leading indentation spaces at the start of the line so indentation stays intact.
        var paragraphStart = content.startIndex
        while paragraphStart < content.endIndex, content[paragraphStart].isWhitespace {
            paragraphStart = content.index(after: paragraphStart)
        }
        var slice = content[paragraphStart...]
        // If the paragraph is very long (> 600 chars), trim to the last 600 chars at a sentence boundary.
        if slice.count > 600 {
            let tailStart = slice.index(slice.endIndex, offsetBy: -600)
            if let dotRange = slice[tailStart...].range(of: ". ") {
                slice = slice[dotRange.upperBound...]
            } else {
                slice = slice[tailStart...]
            }
        }
        let paragraph = String(slice)
        guard paragraph.contains(where: { $0.isLetter }) else { return nil }
        let replaceCount = paragraph.count + trailingWS.count
        return (text: paragraph, replaceCount: replaceCount, trailingWhitespace: trailingWS)
    }

    /// Applies `NSSpellChecker` corrections plus capitalization and greeting comma fixes to `text`.
    /// `shorthandLanguage`: the writing tools also expand chat shorthand of that language ("nn" → "non").
    static func applySpellingFixes(to text: String, context: String = "", shorthandLanguage: String? = nil) -> String {
        var result = ""
        var currentWord = ""
        let flushWord = {
            guard !currentWord.isEmpty else { return }
            let lower = currentWord.lowercased()
            if let lang = shorthandLanguage, let s = Spelling.shorthand[lower], s.language == lang {
                result += currentWord.first?.isUppercase == true ? s.word.prefix(1).uppercased() + s.word.dropFirst() : s.word
            } else if currentWord.count >= 3,
               let fix = Spelling.correction(for: currentWord, context: context + " " + result) {
                result += fix
            } else {
                result += currentWord
            }
            currentWord = ""
        }
        for ch in text {
            if ch.isLetter || ch == "'" || ch == "’" {
                currentWord.append(ch)
            } else {
                flushWord()
                result.append(ch)
            }
        }
        flushWord()
        return result.contains(" ") ? polishCapitalizationAndPunctuation(result) : result
    }

    /// Capitalizes sentence starts (start of text and after `. `, `! `, `? `, `\n` — never inside `config.json` or URLs).
    static func polishCapitalizationAndPunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var chars = Array(text)
        var capitalizeNext = true
        for i in 0..<chars.count {
            if chars[i].isLetter {
                if capitalizeNext {
                    // Skip URLs/domains/camelCase tokens ("https://...", "iPhone", "macOS").
                    var end = i
                    while end < chars.count, !chars[end].isWhitespace { end += 1 }
                    let token = String(chars[i..<end])
                    let hasMidCap = token.dropFirst().contains { $0.isUppercase }
                    if !hasMidCap && !Spelling.isURLToken(Substring(token)) {
                        if let first = String(chars[i]).uppercased().first { chars[i] = first }
                    }
                    capitalizeNext = false
                }
            } else if chars[i] == "\n" {
                capitalizeNext = true
            } else if chars[i] == "." || chars[i] == "!" || chars[i] == "?" {
                if i + 1 < chars.count, chars[i + 1].isWhitespace { capitalizeNext = true }
            }
        }
        var out = String(chars)
        let greetingFixes: [(String, String)] = [
            ("Ciao mi chiamo ", "Ciao, mi chiamo "),
            ("Salve mi chiamo ", "Salve, mi chiamo "),
            ("Buongiorno mi chiamo ", "Buongiorno, mi chiamo "),
            ("Buonasera mi chiamo ", "Buonasera, mi chiamo "),
            ("Hi my name is ", "Hi, my name is "),
            ("Hello my name is ", "Hello, my name is "),
        ]
        for (wrong, right) in greetingFixes where out.hasPrefix(wrong) {
            out = right + out.dropFirst(wrong.count)
        }
        return out
    }

    private static let translationTable: [(keys: [String], name: String, label: String, a: String, b: String)] = [
        (["spanish", "español", "espanol"], "Spanish", "Español",
         "Mañana por la tarde llueve, así que la reunión pasa a ser en línea.",
         "El archivo está listo, te lo envío después de comer."),
        (["french", "français", "francais"], "French", "Français",
         "Demain après-midi il pleut, donc la réunion se fera en ligne.",
         "Le fichier est prêt, je te l'envoie après le déjeuner."),
        (["german", "deutsch"], "German", "Deutsch",
         "Morgen Nachmittag regnet es, deshalb findet das Treffen online statt.",
         "Die Datei ist fertig, ich schicke sie dir nach dem Mittagessen."),
        (["portuguese", "português", "portugues"], "Portuguese", "Português",
         "Amanhã à tarde vai chover, por isso a reunião passa a ser online.",
         "O arquivo está pronto, envio depois do almoço."),
    ]

    static func buildRewritePrompt(text: String, instruction: String, language: String? = nil) -> String {
        let cleanText = text.replacingOccurrences(of: "\"", with: "'")
        let lower = instruction.lowercased()
        let srcIT = "Domani pomeriggio piove, quindi la riunione si sposta online."
        let srcEN = "The file is ready, I'll send it to you after lunch."
        if lower.contains("translate") {
            if let entry = translationTable.first(where: { $0.keys.contains { lower.contains($0) } }) {
                return """
                Translate the text into natural \(entry.name). Output only the \(entry.name) translation inside quotes.
                Original: "\(srcIT)"
                \(entry.label): "\(entry.a)"
                Original: "\(srcEN)"
                \(entry.label): "\(entry.b)"
                Original: "\(cleanText)"
                \(entry.label): "
                """
            }
            if lower.contains("english") {
                return """
                Translate the text into natural English. Output only the English translation inside quotes.
                Original: "\(srcIT)"
                English: "It's going to rain tomorrow afternoon, so the meeting is moving online."
                Original: "Il file è pronto, te lo mando dopo pranzo."
                English: "\(srcEN)"
                Original: "\(cleanText)"
                English: "
                """
            }
            return """
            Traduci il testo in italiano naturale. Scrivi solo la traduzione in italiano tra virgolette.
            Originale: "\(srcEN)"
            Italiano: "Il file è pronto, te lo mando dopo pranzo."
            Originale: "It's going to rain tomorrow afternoon, so the meeting is moving online."
            Italiano: "\(srcIT)"
            Originale: "\(cleanText)"
            Italiano: "
            """
        }

        let lang = language ?? Spelling.dominantLanguageCode(of: cleanText)
        let p = RewriteExamples.prompt(
            (lower.contains("grammar") || lower.contains("spelling")) ? .grammar
            : lower.contains("formal") ? .formal
            : (lower.contains("concise") || lower.contains("shorter")) ? .shorter : .improve,
            language: lang
        )
        var out = p.intro + "\n"
        for (a, b) in p.pairs { out += "\(p.inLabel): \"\(a)\"\n\(p.outLabel): \"\(b)\"\n" }
        return out + "\(p.inLabel): \"\(cleanText)\"\n\(p.outLabel): \""
    }

    /// ISO code of the language a "Translate…" instruction asks for, or nil for every other tool.
    static func translationTarget(_ instruction: String) -> String? {
        let l = instruction.lowercased()
        guard l.contains("translate") else { return nil }
        let map: [(String, String)] = [("spanish", "es"), ("español", "es"), ("french", "fr"), ("français", "fr"),
                                       ("german", "de"), ("deutsch", "de"), ("portuguese", "pt"), ("português", "pt"),
                                       ("english", "en"), ("italian", "it"), ("italiano", "it")]
        return map.first { l.contains($0.0) }?.1
    }

    /// True when the model answered in the wrong language: a rewrite (grammar, improve, formal, shorter) that left
    /// the language of the original or mixed English into Italian, or a translation that isn't in the target language.
    static func hasUnwantedLanguageSwitch(original: String, output: String, instruction: String, language: String? = nil) -> Bool {
        let outLang = Spelling.dominantLanguageCode(of: output)
        if let target = translationTarget(instruction) {
            // Only judge texts long enough to be recognized reliably.
            guard output.split(separator: " ").count >= 3 else { return false }
            return outLang != target
        }
        let origLang = language ?? Spelling.dominantLanguageCode(of: original)
        if origLang == "it" {
            let outLower = " " + output.lowercased() + " "
            let englishIntrusions = [" my name ", " i am ", " i'm ", " worked ", " years ", " in the ", " field", " specialize ",
                                     " hello,", " computer engineer", " expert.", " and i ", " with the "]
            let originalLower = " " + original.lowercased() + " "
            // An intrusion counts only if the user didn't write it themselves.
            if englishIntrusions.contains(where: { outLower.contains($0) && !originalLower.contains($0) }) { return true }
        }
        guard output.split(separator: " ").count >= 4 else {
            // Short answers ("ciao" → "Hello"): rejected when their marker words are in the other language.
            if let m = Spelling.markerLanguage(of: output), m != origLang, Spelling.markerLanguage(of: original) != m { return true }
            return false
        }
        return outLang != origLang
    }

    /// Language of the text to rewrite. Short texts (1–3 words, e.g. a single "xciao") are judged together with
    /// what was written before them in the field; with no evidence at all, the system's own language decides.
    static func rewriteLanguage(text: String, before: String) -> String {
        let words = text.split(whereSeparator: { !$0.isLetter }).count
        if words >= 4 { return Spelling.dominantLanguageCode(of: text) }
        if let m = Spelling.markerLanguage(of: text) { return m }
        let tail = String(before.suffix(300))
        if let m = Spelling.markerLanguage(of: tail) { return m }
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Spelling.detectedLanguageCode(for: tail + " " + text)
        }
        if let sys = Locale.preferredLanguages.lazy.map({ String($0.prefix(2)) }).first(where: { RewriteExamples.languages.contains($0) }),
           Spelling.detectedLanguageCode(for: text) != sys {
            // Neutral word: prefer the system language over the app UI language.
            let validSys = Spelling.isValid(text, language: sys)
            if validSys { return sys }
        }
        return Spelling.detectedLanguageCode(for: text)
    }

    /// Separates leading indentation / bullet markers (`"- "`, `"* "`, `"1. "`) from a line so multi-line rewrites preserve structure.
    static func splitLinePrefix(_ line: String) -> (prefix: String, body: String) {
        if let r = line.range(of: "^\\s*(?:[-*•]\\s+|\\d+[.)]\\s+)?", options: .regularExpression) {
            return (String(line[r]), String(line[r.upperBound...]))
        }
        return ("", line)
    }

    /// Replaces the selection (or the last `replaceDraftCount` characters when nothing was highlighted) with a rewrite.
    /// Multi-line selections are rewritten line-by-line so paragraphs and bullet lists are never truncated to line 1.
    private func rewriteSelection(_ sel: AX.Selection, instruction: String, replaceDraftCount: Int = 0, trailingWhitespace: String = "") {
        toast.show(L("Rewriting…", "Riscrittura…"), busy: true, nearAX: sel.rect)
        rewriteRequest += 1
        let reqID = rewriteRequest
        let isGrammar = instruction.lowercased().contains("grammar")
        let rawLanguage = Self.rewriteLanguage(text: sel.text, before: sel.before)
        var spellFixed = Self.applySpellingFixes(to: sel.text, context: sel.before, shorthandLanguage: rawLanguage)
        let head = sel.before.trimmingCharacters(in: .whitespaces)
        if !spellFixed.contains(" "), !spellFixed.contains("\n"),
           head.isEmpty || ".!?\n".contains(head.last!),
           let f = spellFixed.first, f.isLowercase,
           !spellFixed.dropFirst().contains(where: \.isUppercase),
           !Spelling.isURLToken(Substring(spellFixed)) {
            spellFixed = f.uppercased() + spellFixed.dropFirst()
        }
        let inputForModel = spellFixed
        let language = Self.rewriteLanguage(text: spellFixed, before: sel.before)
        let startKeys = keyCount
        let startBundleID = frontBundleID

        let commitFinal: (String?, Bool) -> Void = { [weak self] finalText, wrongLanguage in
            guard let self, reqID == self.rewriteRequest else { return }
            guard self.keyCount == startKeys, self.frontBundleID == startBundleID,
                  self.rewriteTargetStillThere(sel, replaceDraftCount: replaceDraftCount, trailingWhitespace: trailingWhitespace) else {
                self.toast.show(L("The text changed: rewrite cancelled", "Il testo è cambiato: riscrittura annullata"),
                                symbol: "arrow.uturn.backward", nearAX: sel.rect, duration: 1.8)
                return
            }
            guard let text = finalText, !text.isEmpty else {
                self.toast.show(wrongLanguage
                                ? L("The model answered in the wrong language. Try again or switch to a more capable model.",
                                    "Il modello ha risposto nella lingua sbagliata. Riprova o passa a un modello più capace.")
                                : L("No rewrite this time", "Nessuna riscrittura questa volta"),
                                symbol: "exclamationmark.triangle", nearAX: sel.rect, duration: wrongLanguage ? 3 : 1.6)
                return
            }
            self.toast.hide()
            if replaceDraftCount > 0 { self.backspace(replaceDraftCount) }
            self.insert(text + trailingWhitespace)
            self.credit(SuggestionText.wordCount(text))
        }

        if RewriteGuard.isTooShortToRewrite(sel.text, instruction: instruction) {
            if spellFixed != sel.text { commitFinal(spellFixed, false) } else {
                toast.show(L("Nothing to change here", "Niente da cambiare qui"), symbol: "checkmark", nearAX: sel.rect, duration: 1.4)
            }
            return
        }
        guard prepareModel() else {
            if isGrammar, spellFixed != sel.text { commitFinal(spellFixed, false); return }
            toast.show(L("The model isn't available", "Il modello non è disponibile"), symbol: "exclamationmark.triangle", nearAX: sel.rect)
            return
        }

        let lines = inputForModel.components(separatedBy: "\n")
        if lines.count > 1 {
            let id = engine.taskGeneration.next()
            var outLines = Array(repeating: "", count: lines.count)
            var anyChanged = spellFixed != sel.text
            var anyWrongLang = false
            func step(_ idx: Int) {
                guard reqID == self.rewriteRequest else { return }
                if idx >= lines.count {
                    let joined = outLines.joined(separator: "\n")
                    commitFinal(anyChanged || Self.translationTarget(instruction) != nil ? joined : nil, anyWrongLang)
                    return
                }
                let (lead, body) = Self.splitLinePrefix(lines[idx])
                guard body.contains(where: \.isLetter) else { outLines[idx] = lines[idx]; step(idx + 1); return }
                if RewriteGuard.isTooShortToRewrite(body, instruction: instruction) {
                    outLines[idx] = lead + body; step(idx + 1); return
                }
                let prompt = Self.buildRewritePrompt(text: body, instruction: instruction, language: language)
                let budget = max(80, Int(Double(body.count) * 0.9) + 32)
                engine.complete(prompt: prompt, maxTokens: budget, id: id, instruction: true) { [weak self] res in
                    guard let self, reqID == self.rewriteRequest else { return }
                    if res?.truncated != true, let cand = Self.rewriteResult(res?.text),
                       RewriteGuard.accepts(output: cand, original: body, prompt: prompt, instruction: instruction) {
                        if Self.hasUnwantedLanguageSwitch(original: body, output: cand, instruction: instruction, language: language) {
                            anyWrongLang = true
                            outLines[idx] = lead + body
                        } else {
                            outLines[idx] = lead + cand
                            if cand != body { anyChanged = true }
                        }
                    } else {
                        outLines[idx] = lead + body
                    }
                    step(idx + 1)
                }
            }
            step(0)
            return
        }

        let id = engine.taskGeneration.next()
        let prompt = Self.buildRewritePrompt(text: inputForModel, instruction: instruction, language: language)
        let tokenBudget = max(80, Int(Double(sel.text.count) * 0.9) + 32)
        engine.complete(prompt: prompt, maxTokens: tokenBudget, id: id, instruction: true) { [weak self] result in
            guard let self, reqID == self.rewriteRequest else { return }
            guard result?.truncated != true else {
                commitFinal(isGrammar && spellFixed != sel.text ? spellFixed : nil, false)
                return
            }
            var finalOut = Self.rewriteResult(result?.text)
            if let cand = finalOut, !RewriteGuard.accepts(output: cand, original: inputForModel, prompt: prompt, instruction: instruction) {
                Log.write("rewrite: rejected by RewriteGuard")
                finalOut = isGrammar && spellFixed != sel.text ? spellFixed : nil
            }
            var wrongLanguage = false
            if let cand = finalOut, Self.hasUnwantedLanguageSwitch(original: spellFixed, output: cand, instruction: instruction, language: language) {
                wrongLanguage = true
                finalOut = Self.translationTarget(instruction) == nil && spellFixed != sel.text ? spellFixed : nil
            }
            if isGrammar, (finalOut == nil || finalOut == sel.text), spellFixed != sel.text {
                finalOut = spellFixed
            }
            commitFinal(finalOut, wrongLanguage)
        }
    }

    /// Verifies the text to replace is still in the exact same app and field — never blindly backspaces if unreadable!
    private func rewriteTargetStillThere(_ sel: AX.Selection, replaceDraftCount: Int, trailingWhitespace: String) -> Bool {
        if replaceDraftCount > 0 {
            guard let now = withTypedBuffer(AX.currentContext()), now.bundleID == sel.bundleID else { return false }
            return now.prefix.hasSuffix(sel.text + trailingWhitespace)
        }
        guard let cur = AX.currentSelection(maxChars: 1000, maxWords: 180) else { return false }
        return cur.bundleID == sel.bundleID && cur.text == sel.text
    }

    /// The answer is the first line, up to its closing quote. Quotes inside it are kept: with an odd number of
    /// `"` the last one is the closing quote (`L'espressione "x" significa y."` → `L'espressione "x" significa y.`).
    static func rewriteResult(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var line = raw.components(separatedBy: "\n").first ?? raw
        for marker in [" Originale:", " Original:"] {
            if let r = line.range(of: marker) { line = String(line[..<r.lowerBound]) }
        }
        // The model went on after the closing quote with another few-shot label (`Ciao." Corretto: "…`).
        if let r = line.range(of: "\"\\s+\\p{Lu}\\p{L}*:", options: .regularExpression) {
            line = String(line[..<line.index(after: r.lowerBound)])
        }
        if line.filter({ $0 == "\"" }).count % 2 == 1, let q = line.lastIndex(of: "\"") {
            line = String(line[..<q])
        }
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// True when a model can answer now or as soon as it's back: a model freed after inactivity (`.unloaded`)
    /// is reloaded on the spot, and requests queued after the reload run once it's in memory.
    private func prepareModel() -> Bool {
        switch engine.state {
        case .ready, .loading: return true
        case .unloaded: onNeedModel?(); return true
        case .idle, .noModel, .failed: return false
        }
    }

    /// Starts/stops Audio Context; before the plugin is installed (with consent) it points to where to do it.
    func toggleAudioContext() {
        if !prefs.micContextEnabled, !MainActor.assumeIsolated({ AudioPlugin.shared.isReady }) {
            toast.show(L("Install the Audio Context plugin first: Settings › Awareness", "Installa prima il plugin Contesto audio: Impostazioni › Contesto"),
                       symbol: "waveform.badge.mic", nearAX: nil, duration: 2.6)
            onOpenSettings?()
            return
        }
        settings.prefs.micContextEnabled.toggle()
    }

    /// Every state NexoLLM can be in, most specific first, with its color.
    private func quickStatus(appID id: String, appName name: String) -> (String, Color) {
        let hasApp = !id.isEmpty && id != Bundle.main.bundleIdentifier
        if prefs.globallyDisabled { return (L("Off everywhere", "Spento ovunque"), .secondary) }
        if let end = snoozeEndText { return (L("Paused everywhere until \(end)", "In pausa ovunque fino alle \(end)"), Theme.amber) }
        if hasApp, isPaused(id) { return (L("Paused in \(name)", "In pausa in \(name)"), Theme.amber) }
        if hasApp, !settings.isEnabled(in: id) { return (L("Off in \(name)", "Spento in \(name)"), .secondary) }
        if IsSecureEventInputEnabled() { return (L("Hidden while a password field is active", "Nascosto mentre è attivo un campo password"), Theme.amber) }
        let engine = AppStatus.shared.engine.split(separator: " · ").map { part -> String in
            let p = part.replacingOccurrences(of: " (freed to save memory)", with: "")
            return p.hasSuffix(".gguf") ? (CatalogModel.match(p)?.name ?? p.replacingOccurrences(of: ".gguf", with: "")) : p
        }.joined(separator: " · ")
        if engine.hasPrefix("Error") { return (Fmt.status(engine), Theme.rose) }
        if engine.hasPrefix("Loading") || engine.hasPrefix("Starting") { return (Fmt.status(engine), Theme.amber) }
        if engine.hasPrefix("Sleeping") { return (Fmt.status(engine) + L(" · memory freed", " · memoria liberata"), Theme.blue) }
        return (Fmt.status(engine), Theme.mint)
    }

    // MARK: Menu (menu bar icon and quick menu share it)

    /// The menu bar dropdown: a compact status header card followed by native actions and a native Pause submenu.
    func menuItems(status engine: String, accessibilityMissing: Bool = false,
                   openAccessibility: (() -> Void)? = nil, dismissMenu: (() -> Void)? = nil, quit: Bool) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let front = NSWorkspace.shared.frontmostApplication
        let id = front?.bundleIdentifier ?? ""
        let hasApp = !id.isEmpty && id != Bundle.main.bundleIdentifier
        let name = front?.localizedName ?? id
        let (statusText, statusColor) = quickStatus(appID: id, appName: name)

        let header = NSMenuItem()
        let card = MenuBarHeaderView(
            status: statusText,
            statusColor: statusColor,
            wordsToday: Stats.shared.today.words,
            isSnoozed: isSnoozed,
            onSnooze: { [weak self] mins in dismissMenu?(); self?.snooze(minutes: mins) },
            onToggleIndefinite: { [weak self] in dismissMenu?(); self?.toggleEverywhere() },
            onRestart: { [weak self] in dismissMenu?(); self?.onRestart?() }
        )
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.autoresizingMask = [.width]
        header.view = host
        items.append(header)

        if accessibilityMissing, let openAccessibility {
            items.append(.separator())
            items.append(ClosureMenuItem(L("Allow Accessibility Access…", "Consenti l'accesso Accessibilità…"), openAccessibility))
        }
        if let update = Updater.shared.available {
            let dl = ClosureMenuItem(L("Download \(Brand.name) \(update.version)…", "Scarica \(Brand.name) \(update.version)…")) { Updater.shared.download() }
            dl.isEnabled = NetworkMonitor.shared.isOnline
            items.append(dl)
        }
        items.append(.separator())

        if hasApp {
            let on = settings.isEnabled(in: id)
            let toggleItem = ClosureMenuItem(on ? L("Disable in \(name)", "Disattiva in \(name)")
                                                : L("Enable in \(name)", "Attiva in \(name)")) { [weak self] in
                self?.toggleApp(id, name: name)
            }
            toggleItem.isEnabled = !prefs.globallyDisabled
            items.append(toggleItem)
        }

        // Native NSMenu submenu for pausing / resuming suggestions
        let pauseRoot = NSMenuItem(title: L("Pause Suggestions", "Metti in pausa i suggerimenti"), action: nil, keyEquivalent: "")
        let pauseSub = NSMenu(title: L("Pause Suggestions", "Metti in pausa i suggerimenti"))
        if isSnoozed || prefs.globallyDisabled || (hasApp && isPaused(id)) {
            pauseSub.addItem(ClosureMenuItem(L("Resume Suggestions", "Riprendi suggerimenti")) { [weak self] in
                guard let self else { return }
                if self.prefs.globallyDisabled { self.toggleEverywhere() }
                if self.isSnoozed { self.snooze(minutes: nil) }
                if hasApp, self.isPaused(id) { self.togglePause(id) }
            })
            pauseSub.addItem(.separator())
        }
        if hasApp {
            let pauseApp = ClosureMenuItem(isPaused(id) ? L("Resume in \(name)", "Riprendi in \(name)")
                                                        : L("Pause 10 Minutes in \(name)", "Pausa per 10 minuti in \(name)")) { [weak self] in
                self?.togglePause(id, minutes: 10)
            }
            pauseSub.addItem(pauseApp)
            pauseSub.addItem(.separator())
        }
        pauseSub.addItem(ClosureMenuItem(L("Pause for 30 Minutes Everywhere", "Pausa per 30 minuti ovunque")) { [weak self] in
            self?.snooze(minutes: 30)
        })
        pauseSub.addItem(ClosureMenuItem(L("Pause for 2 Hours Everywhere", "Pausa per 2 ore ovunque")) { [weak self] in
            self?.snooze(minutes: 120)
        })
        pauseSub.addItem(.separator())
        pauseSub.addItem(ClosureMenuItem(prefs.globallyDisabled
            ? L("Enable Suggestions Everywhere", "Attiva suggerimenti ovunque")
            : L("Disable Indefinitely", "Disabilita indefinitamente")) { [weak self] in
            self?.toggleEverywhere()
        })
        pauseRoot.submenu = pauseSub
        items.append(pauseRoot)
        items.append(.separator())

        items.append(ClosureMenuItem(L("Read the Screen Now", "Leggi lo schermo ora")) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.captureScreenNow() }
        })
        let micItem = ClosureMenuItem(L("Audio Context (Experimental)", "Contesto audio (Sperimentale)")) { [weak self] in
            self?.toggleAudioContext()
        }
        micItem.state = prefs.micContextEnabled ? .on : .off
        items.append(micItem)

        let online = NetworkMonitor.shared.isOnline
        let lookupTitle = L("Smart Web Lookup", "Ricerca Web intelligente") + (online ? "" : L(" · Offline (Wi-Fi required)", " · Offline (richiede Wi-Fi)"))
        let lookupItem = ClosureMenuItem(lookupTitle) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.lookUpNow() }
        }
        lookupItem.isEnabled = online
        items.append(lookupItem)

        items.append(.separator())
        let coffeeItem = ClosureMenuItem(L("Support \(Brand.author) · Buy Me a Coffee", "Supporta \(Brand.author) · Offrimi un caffè")) {
            NSWorkspace.shared.open(Brand.coffee)
        }
        coffeeItem.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Buy Me a Coffee")
        items.append(coffeeItem)
        items.append(.separator())

        let restartItem = ClosureMenuItem(L("Restart \(Brand.name) Services", "Riavvia i servizi di \(Brand.name)")) { [weak self] in
            self?.onRestart?()
        }
        items.append(restartItem)

        let settingsItem = ClosureMenuItem(L("Open \(Brand.name)", "Apri \(Brand.name)")) { [weak self] in self?.onOpenSettings?() }
        settingsItem.keyEquivalent = ","
        items.append(settingsItem)
        if quit {
            let q = ClosureMenuItem(L("Quit \(Brand.name)", "Esci da \(Brand.name)")) { NSApp.terminate(nil) }
            q.keyEquivalent = "q"
            items.append(q)
        }
        return items
    }

    // MARK: Session (stable prompt header per field)

    private func updateSession(_ ctx: TextContext) {
        let clipChange = NSPasteboard.general.changeCount
        let newField = ctx.fieldKey != session.fieldKey
        let liveAudio = prefs.micContextEnabled ? AudioContext.shared.transcript : ""
        let audioDue = liveAudio != session.audio && (newField || session.audio.isEmpty || abs(liveAudio.count - session.audio.count) >= 6 || Date().timeIntervalSince(session.audioAt) > 1.2)
        guard newField || (prefs.useClipboard && clipChange != session.clipChange) || audioDue else { return }
        if newField {
            session = Session(fieldKey: ctx.fieldKey)
            let level = Int(prefs.personalizeStrength.rounded())
            let counts = [0, 1, 2, 3, 4, 6]
            session.examples = History.shared.snippets(similarTo: ctx.prefix, app: ctx.bundleID,
                                                       limit: counts[max(0, min(5, level))], excludingField: ctx.fieldKey)
            // Screen: this field's snapshot (automatic ones only in smart mode; manual ones always —
            // the user asked), else a recent manual capture of this app.
            let snap = ScreenContext.shared.snapshot(ctx.fieldKey).flatMap {
                !$0.text.isEmpty && (prefs.screenMode == .smart || $0.manual) ? $0 : nil
            } ?? ScreenContext.shared.pinned(pid: ctx.pid)
            session.screen = snap?.text
            session.screenManual = snap?.manual ?? false
            session.filteredScreen = Self.filterScreen(session.screen, forDraft: ctx.prefix, manual: session.screenManual)
            if prefs.useWindowFields {
                let started = Date()
                let fields = AX.windowFields(around: ctx.element)
                session.fields = fields.isEmpty ? nil : fields.joined(separator: "\n")
                if !fields.isEmpty {
                    Log.write(String(format: "fields: %d in %.0fms %@", fields.count, Date().timeIntervalSince(started) * 1000,
                                     String(reflecting: String(session.fields!.prefix(120)))))
                }
            }
            if prefs.learnStyle, prefs.recordWriting, level > 0 { session.style = StyleProfile.shared.block(for: ctx.bundleID) }
        }
        if audioDue {
            session.audio = liveAudio
            session.audioAt = Date()
            resultCache.removeAll()
        }
        session.clipChange = clipChange
        session.clipboard = prefs.useClipboard ? ContextSources.clipboard() : nil
        rebuildHeader(ctx)
    }

    // MARK: Screen context (event-driven)
    //
    // A screenshot is only considered while the user is writing — never on a timer, never on focus or
    // app switches. `ScreenContext.reason` decides; `ScreenContext` enforces a global cooldown.
    //   • first keystroke in a field with nothing cached        → capture (first look)
    //   • first keystroke after being idle                       → capture (wake)
    //   • back to a field whose snapshot is older than ~2 min    → capture (revisit); else reuse it
    //   • wrote ~300 chars / moved far since the capture         → capture at the next pause (drift)
    //   • typing continuously                                    → nothing, ever

    /// Returns true when a capture for this field is running and the first suggestion of the burst
    /// should wait for it (so the prompt is evaluated once, with context, instead of twice).
    private func considerScreen(_ ctx: TextContext, atPause: Bool) -> Bool {
        guard prefs.screenMode == .smart else { return false }
        let screen = ScreenContext.shared
        let t = ScreenContext.Tunables.current
        let key = ctx.fieldKey
        if screen.inFlight {
            if screenPendingKey == key { return !atPause }
            activity.whenPaused(t.driftPause) { [weak self] in self?.screenPauseCheck() }   // busy with another field
            return false
        }
        let snap = screen.snapshot(key)
        guard let reason = ScreenContext.reason(snapshot: snap, now: Date(), caret: ctx.caretLocation,
                                                caretY: ctx.caretRect.midY, wokeAt: activity.wokeAt,
                                                revisit: key != lastScreenField, atPause: atPause, t) else {
            lastScreenField = key
            // Drift building up: look again once the user pauses (never mid-burst).
            if !atPause, let snap, ScreenContext.drifted(snap, caret: ctx.caretLocation, caretY: ctx.caretRect.midY, t) {
                activity.whenPaused(t.driftPause) { [weak self] in self?.screenPauseCheck() }
            }
            return false
        }
        let started = screen.capture(key: key, pid: ctx.pid, fieldAX: ctx.fieldFrame, caretAX: ctx.caretRect,
                                     caret: ctx.caretLocation, reason: reason) { [weak self] text, changed in
            self?.screenCaptured(text, changed: changed, key: key)
        }
        guard started else {
            // Global cooldown: retry at the next pause (keeps `lastScreenField` so a revisit isn't lost).
            activity.whenPaused(max(t.driftPause, screen.cooldownRemaining(t))) { [weak self] in self?.screenPauseCheck() }
            return false
        }
        lastScreenField = key
        // Only first-look/wake/revisit captures are worth waiting for; a drift refresh runs in the background.
        let blocking = reason != .drift && !atPause
        screenPendingKey = blocking ? key : nil
        return blocking
    }

    /// The user paused: re-evaluate the screen context for the focused field (one AX read).
    private func screenPauseCheck() {
        guard prefs.screenMode == .smart, !prefs.globallyDisabled, !activity.isIdle,
              let ctx = self.withTypedBuffer(AX.currentContext()), ctx.fieldKey == session.fieldKey,
              settings.isEnabled(in: ctx.bundleID), !isPaused(ctx.bundleID) else { return }
        if !hasSuggestionPending { lastContext = ctx }
        _ = considerScreen(ctx, atPause: true)
    }

    private func screenCaptured(_ text: String, changed: Bool, key: String, manual: Bool = false) {
        if screenPendingKey == key { screenPendingKey = nil }
        if changed, session.fieldKey == key {
            session.screen = text.isEmpty ? nil : text
            session.screenManual = manual && !text.isEmpty
            session.filteredScreen = Self.filterScreen(session.screen, forDraft: (lastContext?.fieldKey == key ? lastContext?.prefix : nil) ?? "", manual: session.screenManual)
            if let ctx = lastContext, ctx.fieldKey == key {
                session.memoryChecked = false   // what's on screen can bring back a memory
                recallMemory(ctx)
                rebuildHeader(ctx)
            }
        }
        if let hold = screenHoldWork {   // the first suggestion of this burst was waiting for this
            hold.cancel()
            screenHoldWork = nil
            refresh(force: screenHoldForce, allowHold: false)
            return
        }
        // New context during a pause: evaluate it now so the next keystroke is instant.
        if changed, let ctx = lastContext, ctx.fieldKey == key { warmPrompt(ctx) }
    }

    /// Pre-evaluates the current prompt (new header) into the KV cache. Cancelled by any keystroke.
    private func warmPrompt(_ ctx: TextContext) {
        guard case .ready = engine.state, !requestInFlight, specKey == nil, !insertPending else { return }
        let prompt = SuggestionText.prompt(prefix: ctx.prefix, prefixStart: ctx.prefixStart,
                                           caretLocation: ctx.caretLocation, header: session.header)
        guard !prompt.text.isEmpty else { return }
        engine.warm(prompt: prompt.text, reserve: settings.effectiveLength.maxTokens, id: engine.generation.current)
    }

    // MARK: Idle / wake

    /// First keystroke after a quiet period: get the inference context back while the debounce runs.
    private func didWake() {
        Log.write("activity: wake")
        if case .ready = engine.state { engine.wakeContext() }
    }

    /// No typing for `idleSeconds`: release working memory and stop all background work.
    private func didGoIdle() {
        Log.write("activity: idle — going quiet")
        activity.cancelPause()
        commitMemoryBurst()   // needs the screen snapshots: before pruning them
        if prefs.sleepAfterSeconds > 0, case .ready = engine.state { engine.releaseContext() }
        ScreenContext.shared.prune(olderThan: ScreenContext.Tunables.current.reuseWindow)
        if prefs.learnStyle, prefs.recordWriting { StyleProfile.shared.refreshIfNeeded() }
    }

    // MARK: Manual screen capture

    /// The user asked NexoLLM to look at the screen now (shortcut or orb menu). Works in every screen mode:
    /// with a text field focused the capture belongs to it; otherwise the whole window is read and lent to
    /// the next field you type in, in that app, for a few minutes.
    func captureScreenNow() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let ctx = AX.currentContext()
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            toast.show(L("Allow Screen Recording for NexoLLM in System Settings", "Consenti la Registrazione schermo a NexoLLM in Impostazioni di Sistema"), symbol: "lock.fill", nearAX: ctx?.caretRect, duration: 3)
            return
        }
        let pid = ctx?.pid ?? app.processIdentifier
        let key = ctx?.fieldKey ?? "app-\(pid)"
        let caretAX = ctx?.caretRect ?? CGRect(x: 0, y: 100_000, width: 0, height: 10)   // no field: read the whole window
        if let ctx { updateStatus(ctx, state: .thinking) }
        let started = ScreenContext.shared.capture(key: key, pid: pid, fieldAX: ctx?.fieldFrame, caretAX: caretAX,
                                                   caret: ctx?.caretLocation ?? -1, reason: .manual) { [weak self] text, _ in
            guard let self else { return }
            let now = AX.currentContext()
            self.toast.show(text.isEmpty ? L("Nothing readable on screen", "Niente di leggibile sullo schermo")
                                         : L("Screen context updated", "Contesto schermo aggiornato"),
                            symbol: text.isEmpty ? "eye.slash" : "checkmark.circle.fill", nearAX: now?.caretRect ?? ctx?.caretRect)
            if ctx != nil {
                self.screenCaptured(text, changed: true, key: key, manual: true)
            } else if !text.isEmpty, self.session.fieldKey.hasPrefix("\(pid)-") {
                // Captured without a field: lend it to the field already in use in this app.
                self.session.screen = text
                self.session.screenManual = true
                self.session.filteredScreen = Self.filterScreen(text, forDraft: self.lastContext?.prefix ?? "", manual: true)
                if let last = self.lastContext, last.fieldKey == self.session.fieldKey { self.rebuildHeader(last) }
            }
            // Show what the new context suggests right away (only if the caret is still in the same field).
            if let ctx, let now, now.fieldKey == ctx.fieldKey, !self.hasSuggestion, now.prefix.contains(where: { $0.isLetter }) {
                self.refresh(force: false, context: now, allowHold: false)
            } else if let now {
                self.updateStatus(now, state: .active)
            }
        }
        if started {
            toast.show(L("Reading the screen…", "Lettura dello schermo…"), busy: true, nearAX: ctx?.caretRect)
        } else {
            toast.show(L("Already reading the screen…", "Sto già leggendo lo schermo…"), symbol: "hourglass", nearAX: ctx?.caretRect)
        }
    }

    // MARK: Memory (recent topics)

    /// Remembers what's being written in this field during the burst. Only string bookkeeping:
    /// the actual extraction runs when the app goes idle.
    private func trackForMemory(_ ctx: TextContext) {
        let typed = typedSinceRefresh
        typedSinceRefresh = 0
        guard prefs.memoryEnabled, settings.records(in: ctx.bundleID), ctx.bundleID != Bundle.main.bundleIdentifier else { return }   // Playground practice is never kept
        let key = ctx.fieldKey
        let text = ctx.prefix
        guard var t = burst[key] else {
            guard burst.count < 12 else { return }
            // Seen for the first time: what was there before is the text minus what was just typed.
            let base = String(text.dropLast(min(typed, text.count)))
            burst[key] = Tracked(app: ctx.bundleID, appName: ctx.appName, base: base, last: text, committed: [])
            return
        }
        if text.count + 15 < t.last.count {   // message sent, field cleared or caret moved far: keep what was written
            if let piece = Self.newText(base: t.base, last: t.last) { t.committed.append(piece) }
            t.base = text
        }
        t.last = text
        burst[key] = t
    }

    /// The part of `last` written after `base`, starting at a word boundary.
    static func newText(base: String, last: String) -> String? {
        var start = last.startIndex
        var b = base.startIndex
        while start < last.endIndex, b < base.endIndex, last[start] == base[b] {
            start = last.index(after: start); b = base.index(after: b)
        }
        while start > last.startIndex, !last[last.index(before: start)].isWhitespace { start = last.index(before: start) }
        let s = last[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count >= 15 ? s : nil
    }

    /// Hands the burst's new writing (plus what was on screen) to `Memory`. Called when idle and on quit.
    func commitMemoryBurst(sync: Bool = false) {
        defer { burst = [:] }
        guard prefs.memoryEnabled else { return }
        var sources: [Memory.Source] = []
        for (key, t) in burst {
            var pieces = t.committed
            if let p = Self.newText(base: t.base, last: t.last) { pieces.append(p) }
            guard !pieces.isEmpty else { continue }
            sources.append(Memory.Source(app: t.app, appName: t.appName, text: pieces.joined(separator: "\n"),
                                         screen: ScreenContext.shared.text(for: key)))
        }
        Memory.shared.ingest(sources, sync: sync)
    }

    /// Brings back memories that match the draft and the screen. Runs once per field and then only when a
    /// word has just been completed; the header only changes when *new* memories match (it costs a
    /// partial re-read of the prompt).
    private func recallMemory(_ ctx: TextContext) {
        guard prefs.memoryEnabled, settings.records(in: ctx.bundleID), Memory.shared.count > 0 else { return }
        let boundary = ctx.prefix.last.map { $0.isWhitespace || $0.isPunctuation } ?? false
        guard !session.memoryChecked || boundary else { return }
        session.memoryChecked = true
        let query = String(ctx.prefix.suffix(300)) + "\n" + (session.screen.map { String($0.suffix(450)) } ?? "")
        guard let r = Memory.shared.recall(query: query, draft: ctx.prefix, app: ctx.bundleID),
              Set(r.ids) != Set(session.memoryIDs) else { return }
        session.memoryIDs = r.ids
        session.memory = r.block
        rebuildHeader(ctx)
        Log.write("memory: recalled \(r.ids.count) for \(ctx.appName)")
    }

    private static func filterScreen(_ screen: String?, forDraft draft: String, manual: Bool) -> String? {
        guard let text = screen, !text.isEmpty else { return nil }
        let budget = manual ? 2400 : 1800
        let prefixWords = Set(draft.suffix(400).lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count > 3 })
        let relevant = ScreenContext.relevantExcerpt(from: text, forDraft: draft, budget: budget)
        let out = relevant.split(separator: "\n").filter { line in
            guard !draft.contains(line) else { return false }
            let lw = line.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count > 3 }
            guard lw.count >= 2 else { return true }
            return Double(lw.filter { prefixWords.contains($0) }.count) / Double(lw.count) < 0.6
        }.joined(separator: "\n")
        return out.isEmpty ? nil : out
    }

    private func rebuildHeader(_ ctx: TextContext) {
        let budget = session.screenManual ? 2400 : 1800
        let clip = session.clipboard.flatMap { c in ctx.prefix.contains(c) ? nil : c }
        let audio = prefs.micContextEnabled && !session.audio.isEmpty ? session.audio : nil
        session.header = SuggestionText.header(
            appName: ctx.appName, instructions: prefs.customInstructions,
            appInstructions: settings.config(ctx.bundleID).instructions,
            screen: session.filteredScreen, clipboard: clip, examples: session.examples,
            memory: prefs.memoryEnabled ? session.memory : nil,
            style: session.style, fields: session.fields, audio: audio,
            screenBudget: budget)
    }

    private func recordHistory(_ ctx: TextContext) {
        guard settings.records(in: ctx.bundleID), ctx.bundleID != Bundle.main.bundleIdentifier,
              prefs.recordWithoutAccept || session.accepted else { return }
        History.shared.record(app: ctx.bundleID, fieldKey: ctx.fieldKey, text: ctx.prefix)
    }

    // MARK: Refresh

    /// - Parameters:
    ///   - context: an already-read AX context (saves a round trip right after inserting).
    ///   - chained: the user just accepted a whole suggestion with Tab.
    ///   - allowHold: may wait (briefly) for a screenshot that's being processed for this field.
    private func refresh(force: Bool, context: TextContext? = nil, chained: Bool = false, allowHold: Bool = true) {
        guard !prefs.globallyDisabled else { return }
        healStuckState()
        reportActivity()
        if case .unloaded = engine.state { onNeedModel?(); return }
        if case .failed = engine.state { recoverEngine("engine failed"); return }
        guard case .ready = engine.state else { Log.write("refresh: engine not ready"); return }
        if !force, !chained, settings.onDemandOnly { return }
        if !force, let until = pausedUntil, until > Date() { return }
        guard let ctx = withTypedBuffer(context ?? AX.currentContext()) else {
            Log.write("refresh: no context — \(AX.lastFailure)")
            contextFailures += 1
            if contextFailures == 12 { Log.info("health: no text context for 12 refreshes in a row — \(AX.lastFailure)") }
            ghost.hide(); return
        }
        contextFailures = 0
        lastContext = ctx
        let app = ctx.bundleID
        if !force, !settings.isEnabled(in: app) || isPaused(app) || isSnoozed {
            updateStatus(ctx, state: .paused); return
        }
        updateSession(ctx)
        recordHistory(ctx)
        trackForMemory(ctx)
        // Screen context only while actually writing (not on launch/model reload refreshes).
        let waitForScreen = activity.quietFor < 5 && considerScreen(ctx, atPause: false) && allowHold && !chained
        recallMemory(ctx)

        // Emoji picker (" :que") and emoticons (":)").
        if prefs.emojiEnabled, let q = Emoji.pickerQuery(ctx.prefix) {
            let items = Emoji.search(q)
            if !items.isEmpty {
                listKind = .emoji(query: q)
                list.show(header: "Emoji", items: items.map { ListItem(leading: $0.glyph, title: $0.name.isEmpty ? "" : ":\($0.name.replacingOccurrences(of: " ", with: "_")):") },
                          belowAX: ctx.caretRect)
                updateStatus(ctx, state: .active)
                updateScrollMonitor()
                return
            }
        } else if case .emoji = listKind { list.hide(); listKind = .none }
        if prefs.emojiEnabled, prefs.emoticonsEnabled, let (src, emoji) = Emoji.trailingEmoticon(ctx.prefix) {
            suggestion = .emoticon(source: src, emoji: emoji)
            render(ctx); return
        }

        // Autocorrect. Skipped right after a Tab accept: those words are ours, not typos
        // (the spell checker often flags valid Italian words and would break the chain).
        if !force, !chained, settings.autocorrect(in: app) {
            if prefs.showSuggestedFixes, let (word, trailing) = Spelling.lastFinishedWord(ctx.prefix),
               let fix = Spelling.correction(for: word, context: ctx.prefix) {
                suggestion = .fix(word: word, fix: fix, trailing: trailing)
                render(ctx); return
            }
            if let partial = Spelling.currentWord(ctx.prefix), Spelling.isTypoInProgress(partial, context: ctx.prefix) {
                Log.write("refresh: typo suspected in \(String(reflecting: partial))")
                updateStatus(ctx, state: .active); return
            }
        }

        let midLine = !ctx.atLineEnd
        if midLine, !force, !settings.insideText(in: app) {
            updateStatus(ctx, state: .active); return
        }
        guard force || SuggestionText.hasEnoughText(ctx.prefix) else { return }

        // A fact already written in another field / the clipboard / on screen ("dal 19 al" → " 23"):
        // copy it exactly instead of letting the model guess. Instant, no inference.
        if let fact = factContinuation(ctx) {
            let text = midLine ? SuggestionText.trimForMidLine(fact, after: ctx.after) : fact
            if !text.isEmpty {
                engine.generation.next()
                Log.write("complete: fact from context \(String(reflecting: text))")
                suggestion = .completion(text: text, midLine: midLine, endedWithSpace: ctx.prefix.last.map(SuggestionText.isHorizontalSpace) ?? false)
                suggestionPrefix = ctx.prefix
                anchor = midLine ? nil : (ctx, text)
                predictedCaret = ctx.caretLocation
                render(ctx)
                if !midLine, Date().timeIntervalSince(lastAcceptAt) < 10 { prefetchNext() }
                return
            }
        }

        if waitForScreen {
            // First suggestion of a burst: wait for the screenshot (usually 100–300 ms) so the prompt is
            // evaluated once, with context, instead of once without and again with it. Never longer than 0.45 s.
            screenHoldWork?.cancel()
            screenHoldForce = force
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.screenHoldWork = nil
                self.refresh(force: force, allowHold: false)
            }
            screenHoldWork = work
            updateStatus(ctx, state: .thinking)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
            return
        }

        let prompt = SuggestionText.prompt(prefix: ctx.prefix, prefixStart: ctx.prefixStart,
                                           caretLocation: ctx.caretLocation, header: session.header)
        guard !prompt.text.isEmpty else { return }
        var maxTokens = settings.effectiveLength.maxTokens
        if midLine { maxTokens = min(maxTokens, 6) }
        let split = prompt.userEndedWithSpace ? nil : SuggestionText.healSplit(prompt.text)
        let id = engine.generation.next()
        let started = Date()
        let key = cacheKey(maxTokens, prompt)
        // `immediate`: result known right now (cache), so the context we just read is still current.
        let handle: (LLMEngine.Completion, Bool) -> Void = { [weak self] result, immediate in
            guard let self, id == self.engine.generation.current else { return }
            var text = SuggestionText.clean(result.text, userEndedWithSpace: prompt.userEndedWithSpace,
                                            truncated: result.truncated, prefix: ctx.prefix)
            if midLine { text = SuggestionText.trimForMidLine(text, after: ctx.after) }
            Log.write(String(format: "complete: %.0fms %@ shown=%@", Date().timeIntervalSince(started) * 1000,
                             ctx.appName, String(reflecting: text)))
            guard !text.isEmpty else { self.updateStatus(ctx, state: .active); return }
            let current = immediate ? ctx : self.withTypedBuffer(AX.currentContext())
            guard let now = current, now.pid == ctx.pid, now.caretLocation == ctx.caretLocation else { return }
            self.lastContext = now
            self.suggestion = .completion(text: text, midLine: midLine, endedWithSpace: prompt.userEndedWithSpace)
            self.suggestionPrefix = now.prefix
            self.anchor = midLine ? nil : (now, text)
            self.predictedCaret = now.caretLocation
            self.render(now)
            if self.prefs.alternatives == .auto { self.scheduleAlternatives() }
            // Mid-chain: prepare the following suggestion too, so the next Tab after this one is instant.
            if !midLine, Date().timeIntervalSince(self.lastAcceptAt) < 10 { self.prefetchNext() }
        }
        if let cached = resultCache[key] { handle(cached, true); return }
        updateStatus(ctx, state: .thinking)
        if specKey == key {   // the look-ahead is already computing exactly this: wait for it
            specWaiters.append { handle($0, false) }
            return
        }
        cancelSpeculation()   // stale look-ahead: don't make this request wait behind it
        requestInFlight = true
        lastRequestStarted = Date()
        engine.complete(prompt: split?.stem ?? prompt.text, header: session.header, mustStartWithSpace: prompt.userEndedWithSpace,
                        heal: split?.heal ?? "", maxTokens: maxTokens, id: id) { [weak self] result in
            guard let self else { return }
            self.requestInFlight = false
            guard let result else {
                if self.engine.consecutiveFailures >= 3 { self.recoverEngine("GPU stopped answering") }
                return
            }
            self.remember(key, result)
            handle(result, false)
        }
    }

    /// Exact continuation of the draft found in the window's other fields, the clipboard, microphone or the screen (e.g. a book open next to Obsidian).
    private func factContinuation(_ ctx: TextContext) -> String? {
        let clip = session.clipboard.flatMap { c in ctx.prefix.contains(c) ? nil : c }   // already pasted: not a source
        let mic = prefs.micContextEnabled && !AudioContext.shared.transcript.isEmpty ? AudioContext.shared.transcript : nil
        let sources = [session.fields, clip, mic, session.screen].compactMap { $0 }
        guard !sources.isEmpty else { return nil }
        let endedWithSpace = ctx.prefix.last.map(SuggestionText.isHorizontalSpace) ?? false
        return SuggestionText.contextContinuation(prefix: ctx.prefix, sources: sources, strict: [],
                                                  userEndedWithSpace: endedWithSpace)
    }

    private func cacheKey(_ maxTokens: Int, _ prompt: SuggestionText.Prompt) -> String {
        "\(maxTokens)|\(prompt.userEndedWithSpace ? 1 : 0)|" + prompt.text
    }

    /// Look-ahead: computes the suggestion that will follow the one on screen once it's fully accepted
    /// (text + trailing space), on a separate cancellation counter. Only runs while the user is accepting.
    private func prefetchNext() {
        guard let (base, text) = anchor, case .ready = engine.state else { return }
        let tail = prefs.trailingSpace && !(text.last?.isWhitespace ?? false) ? " " : ""
        let final = text + tail
        let prompt = SuggestionText.prompt(prefix: base.prefix + final, prefixStart: base.prefixStart,
                                           caretLocation: base.caretLocation + (final as NSString).length,
                                           header: session.header)
        guard !prompt.text.isEmpty else { return }
        let maxTokens = settings.effectiveLength.maxTokens
        let key = cacheKey(maxTokens, prompt)
        guard resultCache[key] == nil, specKey != key else { return }
        cancelSpeculation()
        specKey = key
        let id = engine.specGeneration.next()
        let split = prompt.userEndedWithSpace ? nil : SuggestionText.healSplit(prompt.text)
        engine.complete(prompt: split?.stem ?? prompt.text, header: session.header, mustStartWithSpace: prompt.userEndedWithSpace,
                        heal: split?.heal ?? "", maxTokens: maxTokens, id: id, speculative: true) { [weak self] result in
            guard let self else { return }
            if let result { self.remember(key, result) }   // a finished look-ahead is valid even if superseded
            guard self.specKey == key else { return }
            let waiters = self.specWaiters
            self.specKey = nil
            self.specWaiters = []
            guard let result else { return }
            waiters.forEach { $0(result) }
        }
    }

    private func remember(_ key: String, _ result: LLMEngine.Completion) {
        resultCache[key] = result
    }

    private func reportActivity() {
        guard Date().timeIntervalSince(lastActivityReport) > 15 else { return }
        lastActivityReport = Date()
        onActivity?()
    }

    /// Called once the model is (re)loaded: retry a suggestion at the current caret.
    func modelDidLoad() {
        resultCache.removeAll()
        scheduleRefresh(after: 10)
    }

    // MARK: Word tools: alternatives

    private func scheduleAlternatives() {
        laterWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showAlternatives(scope: self?.prefs.alternativesScope ?? .word) }
        laterWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    /// Word: other words for the one being typed (or the next one). Phrase: other ways to go on.
    /// Works at any caret, with or without a suggestion on screen. Opens at once with placeholder rows;
    /// switching Word ⇄ Phrase at the same caret is instant the second time (cached).
    private func showAlternatives(scope: AlternativesScope) {
        guard let ctx = AX.currentContext() ?? lastContext, ctx.prefix.contains(where: { $0.isLetter }) else { return }
        lastContext = ctx
        debounce?.cancel()
        let modelOK = prepareModel()   // before taking the id: a reload invalidates `generation`
        let gen = engine.generation.next()
        listRequest += 1
        let request = listRequest
        let prompt = SuggestionText.prompt(prefix: ctx.prefix, prefixStart: ctx.prefixStart,
                                           caretLocation: ctx.caretLocation, window: 600, header: session.header)
        guard !prompt.text.isEmpty else { return }
        let split = prompt.userEndedWithSpace ? nil : SuggestionText.healSplit(prompt.text)
        let partial = split.map { $0.heal.trimmingCharacters(in: .whitespaces) } ?? ""
        let cacheKey = "\(scope.rawValue)|\(ctx.caretLocation)|\(prompt.text.suffix(200))"
        let show: ([String]) -> Void = { [weak self] found in
            guard let self else { return }
            guard gen == self.engine.generation.current else {
                if request == self.listRequest, self.list.loading { self.list.hide(); self.listKind = .none; self.updateScrollMonitor() }
                return
            }
            let items = found.filter { !SuggestionText.isContextLabel($0, appName: ctx.appName, draft: ctx.prefix) }
            guard !items.isEmpty else {
                self.list.hide(); self.listKind = .none; self.updateScrollMonitor()
                self.toast.show(L("No alternatives here", "Nessuna alternativa qui"), symbol: "text.magnifyingglass", nearAX: ctx.caretRect, duration: 1)
                return
            }
            self.rememberAlternatives(cacheKey, items)
            self.suggestion = .none
            self.ghost.hide()
            self.listKind = scope == .word ? .words(items, replace: partial.count) : .alternatives(items)
            self.list.show(header: L("Alternatives", "Alternative"),
                           items: items.map { ListItem(leading: "", title: $0.trimmingCharacters(in: .whitespaces)) },
                           belowAX: ctx.caretRect, scope: scope, switchKey: self.prefs.alternativesShortcut.display)
            self.updateScrollMonitor()
        }
        if let cached = altCache[cacheKey] { show(cached); return }
        guard modelOK else { return }
        suggestion = .none
        ghost.hide()
        listKind = scope == .word ? .words([], replace: partial.count) : .alternatives([])
        list.showLoading(header: L("Alternatives", "Alternative"), belowAX: ctx.caretRect, scope: scope, switchKey: prefs.alternativesShortcut.display)
        updateScrollMonitor()
        let contextPool = ((session.screen ?? "") + " " + (session.audio)).split(whereSeparator: { !$0.isLetter })
            .map(String.init).filter { $0.count >= 4 }
        let words: ([String]) -> [String] = { found in
            var out: [String] = []
            func add(_ w: String) {
                guard !w.isEmpty, w.lowercased() != partial.lowercased(),
                      !out.contains(where: { $0.lowercased() == w.lowercased() }) else { return }
                out.append(w)
            }
            // Prefer real words and domain terms that appear on the screen / lecture transcript.
            found.filter { w in
                Spelling.isWord(w, context: ctx.prefix) || contextPool.contains { $0.caseInsensitiveCompare(w) == .orderedSame }
            }.forEach(add)
            if !partial.isEmpty {
                for w in contextPool where out.count < 6 && w.lowercased().hasPrefix(partial.lowercased()) {
                    add(partial.first!.isUppercase ? w.prefix(1).uppercased() + w.dropFirst() : w)
                }
            }
            return Array(out.prefix(6))
        }

        switch scope {
        case .word:
            engine.alternatives(prompt: split?.stem ?? prompt.text, header: session.header,
                                mustStartWithSpace: prompt.userEndedWithSpace, heal: split?.heal ?? "",
                                count: 10, maxTokens: 3, id: gen) { results in
                show(words(results.compactMap { SuggestionText.firstWord(partial: partial, continuation: $0.text) }))
            }
        case .phrase:
            engine.alternatives(prompt: split?.stem ?? prompt.text, header: session.header,
                                mustStartWithSpace: prompt.userEndedWithSpace, heal: split?.heal ?? "", count: 4,
                                maxTokens: settings.effectiveLength.maxTokens, id: gen) { results in
                var unique: [String] = []
                for r in results {
                    let text = SuggestionText.clean(r.text, userEndedWithSpace: prompt.userEndedWithSpace,
                                                    truncated: r.truncated, prefix: ctx.prefix)
                    if !text.isEmpty, !unique.contains(text) { unique.append(text) }
                }
                show(unique)
            }
        }
    }

    /// Recent alternatives by scope + caret, so switching back and forth costs nothing.
    private var altCache = BoundedCache<String, [String]>(limit: 8)
    /// Bumped by every alternatives/synonyms request: a cancelled one only closes its own placeholder.
    private var listRequest = 0

    private func rememberAlternatives(_ key: String, _ items: [String]) {
        altCache[key] = items
    }

    /// Drops every cached result (Settings → Clear Cache).
    func clearCaches() {
        resultCache.removeAll()
        altCache.removeAll()
        session.screen = nil; session.filteredScreen = nil; session.fields = nil; session.clipboard = nil; session.audio = ""
        if let ctx = lastContext { rebuildHeader(ctx) }
    }

    /// Context held in memory for the focused field (Privacy Inspector).
    var currentWindowFields: String? { session.fields }
    var currentClipboard: String? { session.clipboard }
    var currentAudioTranscript: String? {
        let t = AudioContext.shared.transcript
        return prefs.micContextEnabled && !t.isEmpty ? t : nil
    }

    /// Rough size of the in-memory caches, for Settings.
    var cacheBytes: Int {
        resultCache.entries.reduce(0) { $0 + $1.key.utf8.count + $1.value.text.utf8.count }
            + altCache.entries.reduce(0) { $0 + $1.key.utf8.count + $1.value.reduce(0) { $0 + $1.utf8.count } }
    }

    // MARK: Word tools: synonyms

    private func scheduleSelectionCheck() {
        laterWork?.cancel()
        let work = DispatchWorkItem { [weak self] in _ = self?.showSynonymsIfSelection() }
        laterWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    @discardableResult
    private func showSynonymsIfSelection() -> Bool {
        guard let sel = AX.currentSelection(), settings.isEnabled(in: sel.bundleID) else { return false }
        let word = sel.text.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, word.count <= 30 else { return false }
        let capitalized = word.first?.isUppercase ?? false
        let present: ([String]) -> Void = { [weak self] raw in
            guard let self else { return }
            var seen = Set<String>()
            let words = raw
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty && $0.count < 40 && $0.lowercased() != word.lowercased() }
                .map { capitalized ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }
                .filter { seen.insert($0.lowercased()).inserted }
            let top = Array(words.prefix(5))
            guard !top.isEmpty else { self.list.hide(); self.listKind = .none; return }
            self.listKind = .synonyms(top)
            self.list.show(header: L("Synonyms", "Sinonimi"), items: top.map { ListItem(leading: "", title: $0) }, belowAX: sel.rect)
            self.updateScrollMonitor()
        }
        guard prepareModel() else { return false }
        listKind = .synonyms([])
        list.showLoading(header: L("Synonyms", "Sinonimi"), belowAX: sel.rect)
        updateScrollMonitor()
        let synLang = Self.rewriteLanguage(text: word, before: sel.before)
        let synPrompts: [String: String] = [
            "it": "Sinonimi di \"bello\": carino, grazioso, piacevole, attraente\nSinonimi di \"parlare\": dire, discutere, conversare, esprimersi\nSinonimi di \"\(word)\":",
            "es": "Sinónimos de \"bonito\": hermoso, lindo, agradable, atractivo\nSinónimos de \"hablar\": decir, conversar, dialogar, charlar\nSinónimos de \"\(word)\":",
            "fr": "Synonymes de \"beau\": joli, agréable, charmant, attrayant\nSynonymes de \"parler\": dire, discuter, converser, échanger\nSynonymes de \"\(word)\":",
            "de": "Synonyme für \"schön\": hübsch, angenehm, ansprechend, reizvoll\nSynonyme für \"sprechen\": reden, sich unterhalten, diskutieren, äußern\nSynonyme für \"\(word)\":",
            "pt": "Sinónimos de \"bonito\": belo, agradável, elegante, atraente\nSinónimos de \"falar\": dizer, conversar, dialogar, discutir\nSinónimos de \"\(word)\":",
        ]
        let prompt = synPrompts[synLang] ?? "Synonyms of \"nice\": pleasant, lovely, delightful, kind\nSynonyms of \"talk\": speak, chat, converse, discuss\nSynonyms of \"\(word)\":"
        let id = engine.taskGeneration.next()
        listRequest += 1
        let request = listRequest
        engine.complete(prompt: prompt, maxTokens: 28, id: id, instruction: true) { [weak self] result in
            guard let self else { return }
            guard id == self.engine.taskGeneration.current else {
                if request == self.listRequest, self.list.loading { self.list.hide(); self.listKind = .none; self.updateScrollMonitor() }
                return
            }
            present(result?.text.split(separator: ",").map(String.init) ?? [])
        }
        return true
    }
}

/// Data that can be thrown away at any time: screen text, recent results, the log.
/// Your history and memories are not part of it.
enum TempCache {
    static weak var controller: CompletionController?

    static var bytes: Int64 { Int64((controller?.cacheBytes ?? 0) + ScreenContext.shared.bytes) + Log.bytes }
    static var windowFields: String? { controller?.currentWindowFields }
    static var clipboardPreview: String? { controller?.currentClipboard }
    static var audioPreview: String? { controller?.currentAudioTranscript }

    static func clear() {
        controller?.clearCaches()
        AudioContext.shared.clear()
        ScreenContext.shared.removeAll()
        Backdrop.shared.removeAll()
        Log.reset()
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

/// Compact header card at the top of the status bar menu: status, words accepted today, and restart button.
struct MenuBarHeaderView: View {
    let status: String
    let statusColor: Color
    let wordsToday: Int
    let isSnoozed: Bool
    let onSnooze: (Double?) -> Void
    let onToggleIndefinite: () -> Void
    let onRestart: () -> Void
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let disabled = settings.prefs.globallyDisabled
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                BrandOrb(size: 18)
                Text(Brand.name).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 6)
                Button(action: onRestart) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(4)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help(L("Restart NexoLLM services", "Riavvia i servizi di NexoLLM"))
            }

            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(status).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if wordsToday > 0 {
                    Text("\(Fmt.number(wordsToday)) " + L("words", "parole"))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }

            if disabled || isSnoozed {
                Button {
                    if disabled { onToggleIndefinite() } else { onSnooze(nil) }
                } label: {
                    Label(L("Resume Suggestions", "Riprendi suggerimenti"), systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
    }
}
