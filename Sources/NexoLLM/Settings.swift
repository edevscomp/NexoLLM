import AppKit
import Carbon.HIToolbox
import Security

// MARK: - Shortcut

/// A key + modifier combination matched inside the event tap.
struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: Int64
    var modifiers: UInt64

    static let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    init(_ keyCode: Int, _ flags: CGEventFlags = []) {
        self.keyCode = Int64(keyCode)
        self.modifiers = flags.intersection(Shortcut.relevant).rawValue
    }

    func matches(_ code: Int64, _ flags: CGEventFlags) -> Bool {
        code == keyCode && flags.intersection(Shortcut.relevant).rawValue == modifiers
    }

    var display: String {
        let f = CGEventFlags(rawValue: modifiers)
        var s = ""
        if f.contains(.maskControl) { s += "⌃" }
        if f.contains(.maskAlternate) { s += "⌥" }
        if f.contains(.maskShift) { s += "⇧" }
        if f.contains(.maskCommand) { s += "⌘" }
        return s + KeyNames.name(Int(keyCode))
    }
}

enum KeyNames {
    private static var cache: [Int: String] = [:]
    private static var cachedLayoutID: String?

    static func name(_ code: Int) -> String {
        switch code {
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return "#\(code)" }
        let layoutID = TISGetInputSourceProperty(src, kTISPropertyInputSourceID).map {
            Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
        }
        if layoutID != cachedLayoutID { cachedLayoutID = layoutID; cache.removeAll() }
        if let hit = cache[code] { return hit }
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        let translated = data.withUnsafeBytes { raw -> String in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return "#\(code)" }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
            return len > 0 ? String(utf16CodeUnits: chars, count: len).uppercased() : "#\(code)"
        }
        cache[code] = translated
        return translated
    }

    /// The physical key right above Tab (`\` on Italian ISO, `` ` `` on US ANSI).
    static var aboveTab: Int {
        KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardISO ? kVK_ISO_Section : kVK_ANSI_Grave
    }
}

// MARK: - Option enums

enum TriState: String, Codable, CaseIterable, Identifiable {
    case `default`, on, off
    var id: String { rawValue }
}

enum CompletionLength: String, Codable, CaseIterable, Identifiable {
    case short, medium, long, veryLong
    var id: String { rawValue }
    var label: String {
        switch self {
        case .short: return L("Short (~1 – 2 words)", "Breve (~1 – 2 parole)")
        case .medium: return L("Medium (~2 – 4 words)", "Media (~2 – 4 parole)")
        case .long: return L("Long (~4 – 8 words)", "Lunga (~4 – 8 parole)")
        case .veryLong: return L("Very long (full sentence)", "Molto lunga (frase intera)")
        }
    }
    var maxTokens: Int {
        switch self { case .short: return 4; case .medium: return 8; case .long: return 14; case .veryLong: return 26 }
    }
    var shorter: CompletionLength {
        switch self { case .short, .medium: return .short; case .long: return .medium; case .veryLong: return .long }
    }
}

enum EscapeBehavior: String, Codable, CaseIterable, Identifiable {
    case pause, dismiss, disableApp
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pause: return L("Pause completions for a few seconds", "Metti in pausa per qualche secondo")
        case .dismiss: return L("Only dismiss the suggestion", "Nascondi solo il suggerimento")
        case .disableApp: return L("Pause completions in this app for 10 minutes", "Metti in pausa in questa app per 10 minuti")
        }
    }
}

/// Which model to use: switch automatically with the power source, or pin one.
enum ModelMode: String, Codable, CaseIterable, Identifiable {
    case automatic, pluggedIn, battery
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: return L("Automatic (switch on plug/unplug)", "Automatico (cambia tra corrente e batteria)")
        case .pluggedIn: return L("Always use the plugged-in model", "Usa sempre il modello con alimentatore")
        case .battery: return L("Always use the battery model", "Usa sempre il modello a batteria")
        }
    }
}

enum ToolMode: String, Codable, CaseIterable, Identifiable {
    case off, auto, shortcut
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return L("Don't show", "Non mostrare")
        case .auto: return L("After a short delay", "Dopo una breve pausa")
        case .shortcut: return L("On shortcut", "Con scorciatoia")
        }
    }
}

/// When NexoLLM may read the screen for context.
enum ScreenMode: String, Codable, CaseIterable, Identifiable {
    case off, smart, manual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return L("Never", "Mai")
        case .smart: return L("Smart (automatic)", "Smart (automatico)")
        case .manual: return L("Only when I ask", "Solo su richiesta")
        }
    }
}

/// Window appearance of NexoLLM's own UI.
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("System", "Sistema")
        case .light: return L("Light", "Chiaro")
        case .dark: return L("Dark", "Scuro")
        }
    }
}

/// What ⌥Tab lists first: other words for the one being typed, or other ways to continue the sentence.
enum AlternativesScope: String, Codable, CaseIterable, Identifiable {
    case word, phrase
    var id: String { rawValue }
    var label: String { self == .word ? L("Word", "Parola") : L("Phrase", "Frase") }
    var other: AlternativesScope { self == .word ? .phrase : .word }
}

/// Language of the whole interface and of the tour's sample text.
enum ExampleLanguage: String, Codable, CaseIterable, Identifiable {
    case english, italian, spanish, french, german, portuguese
    var id: String { rawValue }

    private var meta: (label: String, iso: String, locale: String, flag: String, englishName: String) {
        switch self {
        case .english: return ("English", "en", "en_US", "🇬🇧", "English")
        case .italian: return ("Italiano", "it", "it_IT", "🇮🇹", "Italian")
        case .spanish: return ("Español", "es", "es_ES", "🇪🇸", "Spanish")
        case .french: return ("Français", "fr", "fr_FR", "🇫🇷", "French")
        case .german: return ("Deutsch", "de", "de_DE", "🇩🇪", "German")
        case .portuguese: return ("Português", "pt", "pt_PT", "🇵🇹", "Portuguese")
        }
    }

    var label: String { meta.label }
    /// ISO 639-1 code: "en", "it", "es", "fr", "de", "pt".
    var iso: String { meta.iso }
    var code: String { meta.iso.uppercased() }
    var localeIdentifier: String { meta.locale }
    var flag: String { meta.flag }
    /// The language's English name, as the writing tools' instructions use it ("Translate into natural Spanish").
    var englishName: String { meta.englishName }

    init?(iso: String) {
        guard let l = Self.allCases.first(where: { $0.iso == iso.prefix(2).lowercased() }) else { return nil }
        self = l
    }
}

/// Per-app overrides ("App Settings" pane).
struct AppConfig: Codable, Equatable {
    var enabled: TriState = .default
    var insideText: TriState = .default
    var autocorrect: TriState = .default
    var disableTab: TriState = .default
    var compatibility = false
    var instructions = ""
    var record: TriState = .default
}

// MARK: - Preferences

/// Every user preference. Persisted as one JSON blob; unknown/missing keys fall back to defaults.
struct Prefs: Codable, Equatable {
    // General
    var launchAtLogin = false
    var showMenuBarIcon = true
    var appearance: AppearanceMode = .system
    var modelPath = Settings.defaultModelPath
    var enabledByDefault = true
    var completeInsideText = true
    var completionLength: CompletionLength = .medium
    var debounceMs: Double = 110
    var suppressOnTypo = true
    var showSuggestedFixes = true
    var globallyDisabled = false
    /// Free the model's memory after this many idle minutes (0 = never).
    var unloadAfterMinutes = 10
    /// Go quiet after this many seconds without typing: the KV cache and GPU buffers are released
    /// and a new writing burst starts with a fresh look at the screen (0 = never release memory).
    var sleepAfterSeconds = 60
    var modelMode: ModelMode = .automatic
    var debugLogging = false
    /// A quiet tap when a suggestion is accepted.
    var acceptSound = false
    /// Key click volume, 0.1 … 1.
    var acceptSoundVolume: Double = 0.65
    /// Language of the app (interface and tour examples).
    var exampleLanguage: ExampleLanguage = .english
    /// Ghost text in a soft accent hue instead of neutral grey.
    var ghostTint = false
    /// Ghost text opacity, 0.5 … 1.
    var ghostOpacity: Double = 1

    // Network. Suggestions and every AI feature run on this computer; the network is only used for what
    // the user asks for (model downloads, Web Lookup) and the update check.
    /// ⌃⌥L looks things up on Wikipedia, Wiktionary, Wikiquote, DuckDuckGo and Google News.
    var webLookupEnabled = true

    // Context
    /// Smart = NexoLLM decides when to look (event-driven); manual = only when you press the capture shortcut.
    var screenMode: ScreenMode = .smart
    var useClipboard = true
    /// Read the other fields of the focused window (subject, recipients, title) as context.
    var useWindowFields = true
    /// Experimental: listen to the microphone (on-device speech-to-text) to use lectures/meetings as context.
    var micContextEnabled = false

    // Personalization
    var recordWriting = true
    var recordWithoutAccept = true
    var personalizeStrength: Double = 2       // 0 (off) … 5 (max)
    var customInstructions = Prefs.defaultInstructions
    /// Short-term memory of recent topics (decays; reinforced when the topic comes back).
    var memoryEnabled = true
    /// Unused memories are forgotten after about this many days.
    var memoryDays = 3
    /// Learn openings, closings, recurring expressions and habits from the typing history.
    var learnStyle = true

    /// Empty by default: you describe yourself in Settings → Mind → Memory & Style.
    static let defaultInstructions = ""

    // Emoji
    var emojiEnabled = true
    var emoticonsEnabled = true

    // Shortcuts
    var nextWordShortcut = Shortcut(kVK_Tab)
    var trailingSpace = true
    var fullCompletionShortcut = Shortcut(kVK_Tab, .maskShift)
    /// Tab keeps indenting at the start of a line or after a list marker ("- ", "1. "): accept with the
    /// full-completion key there instead.
    var smartTab = true
    var escapeBehavior: EscapeBehavior = .pause
    var forceShortcut = Shortcut(KeyNames.aboveTab, .maskControl)
    var toggleAppShortcut = Shortcut(KeyNames.aboveTab, [.maskControl, .maskAlternate, .maskCommand])
    var globalToggleShortcut: Shortcut? = nil
    var alternativesShortcut = Shortcut(kVK_Tab, .maskAlternate)
    /// Look at the screen right now (works in every screen mode).
    var captureShortcut = Shortcut(kVK_ANSI_S, [.maskControl, .maskAlternate])
    /// Opens the quick menu at the cursor.
    var quickMenuShortcut = Shortcut(kVK_ANSI_M, [.maskControl, .maskAlternate])
    /// Looks up the selected text (or the current question) on the web in a floating card.
    var webLookupShortcut = Shortcut(kVK_ANSI_L, [.maskControl, .maskAlternate])
    /// Soft-restarts NexoLLM services (keyboard tap, overlays, model) in place.
    var restartShortcut = Shortcut(kVK_ANSI_R, [.maskControl, .maskAlternate])

    // Battery
    var batteryOnDemand = false
    var batteryModelPath = Settings.defaultBatteryModelPath   // "" = same as the plugged-in model
    var batteryShorter = false
    /// Below 20 % battery, suggestions appear only on demand (force shortcut).
    var lowBatteryOnDemand = true

    // Apps
    var apps: [String: AppConfig] = Prefs.defaultApps

    // Word tools
    var alternatives: ToolMode = .shortcut
    var synonyms: ToolMode = .shortcut
    var alternativesScope: AlternativesScope = .word

    // Updates: look for a new version on GitHub once a day.
    var autoCheckUpdates = true

    static let defaultApps: [String: AppConfig] = {
        var d: [String: AppConfig] = [:]
        for id in ["com.apple.Terminal", "com.googlecode.iterm2", "com.apple.dt.Xcode", "com.microsoft.VSCode",
                   "com.1password.1password", "com.apple.keychainaccess", "com.apple.Passwords"] {
            d[id] = AppConfig(enabled: .off)
        }
        return d
    }()
}

// MARK: - Settings store

final class Settings: ObservableObject {
    static let shared = Settings()

    /// NexoLLM keeps its models in its own folder.
    static let modelsFolder = AppPaths.support.appendingPathComponent("Models", isDirectory: true)

    static let e4bModelPath = modelsFolder.appendingPathComponent("gemma-4-E4B.i1-Q4_K_M.gguf").path

    /// The catalog's file name; very early builds saved it with a dash (`-i1`), which is still recognized.
    static let e2bModelPath: String = {
        let current = modelsFolder.appendingPathComponent("gemma-4-E2B.i1-Q4_K_M.gguf").path
        let legacy = modelsFolder.appendingPathComponent("gemma-4-E2B-i1-Q4_K_M.gguf").path
        return !FileManager.default.fileExists(atPath: current) && FileManager.default.fileExists(atPath: legacy) ? legacy : current
    }()

    /// Model files already in NexoLLM's folder, largest first.
    static func installedModelPaths() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: modelsFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.filter { $0.pathExtension == "gguf" }
            .map { ($0.path, (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            .sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Brings model files that preferences point to outside NexoLLM's folder into it (APFS clone: instant,
    /// no extra disk space), and repoints the preferences. Returns the paths that were moved.
    @discardableResult
    func adoptExternalModels() -> [String] {
        let fm = FileManager.default
        try? fm.createDirectory(at: Settings.modelsFolder, withIntermediateDirectories: true)
        var moved: [String] = []
        func adopt(_ path: String) -> String {
            guard !path.isEmpty, !path.hasPrefix(Settings.modelsFolder.path), fm.fileExists(atPath: path) else { return path }
            let target = Settings.modelsFolder.appendingPathComponent((path as NSString).lastPathComponent).path
            if !fm.fileExists(atPath: target) {
                do { try fm.copyItem(atPath: path, toPath: target) } catch { return path }
            }
            moved.append((path as NSString).lastPathComponent)
            return target
        }
        let main = adopt(prefs.modelPath), battery = adopt(prefs.batteryModelPath)
        if main != prefs.modelPath { prefs.modelPath = main }
        if battery != prefs.batteryModelPath { prefs.batteryModelPath = battery }
        return moved
    }

    /// A fresh install has no model: the path stays empty (state "no model", never an error) until one is
    /// downloaded or imported.
    static let defaultModelPath: String = {
        let fm = FileManager.default
        if fm.fileExists(atPath: e4bModelPath) { return e4bModelPath }
        if fm.fileExists(atPath: e2bModelPath) { return e2bModelPath }
        return installedModelPaths().first ?? ""
    }()

    static let defaultBatteryModelPath: String = {
        FileManager.default.fileExists(atPath: e2bModelPath) ? e2bModelPath : ""
    }()

    private static let key = "prefs.v2"

    @Published var prefs: Prefs {
        didSet { if prefs != oldValue { save() } }
    }

    private var saveWork: DispatchWorkItem?

    private init() {
        var loaded = Settings.load()
        // Audio Context never resumes by itself: listening starts only when the user turns it on, every time.
        loaded.micContextEnabled = false
        prefs = loaded
        if UserDefaults.standard.data(forKey: Settings.key) != nil { flush() }
    }

    /// Removes any pre-0.8 cloud API keys stored in the Keychain once.
    static func removeLegacyCloudKeysOnce() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "cleanup.cloudKeysRemoved") else { return }
        d.set(true, forKey: "cleanup.cloudKeysRemoved")
        for provider in ["openAI", "anthropic", "gemini", "compatible"] {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Brand.bundleID,
                                    kSecAttrAccount as String: "api-key-\(provider)"]
            if SecItemDelete(q as CFDictionary) == errSecSuccess { Log.info("cleanup: removed a stored cloud API key") }
            d.removeObject(forKey: "cloud.verified.\(provider)")
        }
    }

    private static func load() -> Prefs {
        let defaults = Prefs()
        guard let stored = UserDefaults.standard.data(forKey: key),
              let storedDict = try? JSONSerialization.jsonObject(with: stored) as? [String: Any],
              let baseData = try? JSONEncoder().encode(defaults),
              var merged = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any] else {
            UserDefaults.standard.set(true, forKey: "prefs.shiftTabMigrated")   // fresh install: already ⇧⇥
            return defaults
        }
        merged.merge(storedDict) { _, new in new }
        // v2 → v3: the screenshot on/off switch became a mode (off / smart / manual).
        if storedDict["screenMode"] == nil, let legacy = storedDict["useScreenshots"] as? Bool {
            merged["screenMode"] = legacy ? ScreenMode.smart.rawValue : ScreenMode.off.rawValue
        }
        merged["useScreenshots"] = nil
        merged["trailingPunctuation"] = nil
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              var prefs = try? JSONDecoder().decode(Prefs.self, from: data) else { return defaults }
        // A model that is no longer on disk (deleted, or a default that was never downloaded) gives way to one
        // that is, or to "no model" — never to a "model not found" error.
        let fm = FileManager.default
        if !prefs.modelPath.isEmpty, !fm.fileExists(atPath: prefs.modelPath) {
            prefs.modelPath = installedModelPaths().first ?? ""
        }
        if !prefs.batteryModelPath.isEmpty, !fm.fileExists(atPath: prefs.batteryModelPath) { prefs.batteryModelPath = "" }
        // Once: the old default for "accept all" (the key above Tab) becomes ⇧⇥. A custom choice is kept.
        if !UserDefaults.standard.bool(forKey: "prefs.shiftTabMigrated") {
            UserDefaults.standard.set(true, forKey: "prefs.shiftTabMigrated")
            let s = prefs.fullCompletionShortcut
            if s.modifiers == 0, s.keyCode == Int64(kVK_ISO_Section) || s.keyCode == Int64(kVK_ANSI_Grave) {
                prefs.fullCompletionShortcut = Shortcut(kVK_Tab, .maskShift)
            }
        }
        return prefs
    }

    var savingEnabled = true

    private func save() {
        guard savingEnabled else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func flush() {
        saveWork?.cancel()
        saveWork = nil
        guard savingEnabled else { return }
        if let data = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(data, forKey: Settings.key) }
    }

    // MARK: Effective per-app values

    func config(_ bundleID: String) -> AppConfig { prefs.apps[bundleID] ?? AppConfig() }

    func updateConfig(_ bundleID: String, _ change: (inout AppConfig) -> Void) {
        var c = config(bundleID)
        change(&c)
        prefs.apps[bundleID] = c
    }

    private func resolve(_ t: TriState, _ fallback: Bool) -> Bool {
        switch t { case .on: return true; case .off: return false; case .default: return fallback }
    }

    func isEnabled(in id: String) -> Bool { resolve(config(id).enabled, prefs.enabledByDefault) }
    func insideText(in id: String) -> Bool { resolve(config(id).insideText, prefs.completeInsideText) }
    func autocorrect(in id: String) -> Bool { resolve(config(id).autocorrect, prefs.suppressOnTypo) }
    func tabDisabled(in id: String) -> Bool { resolve(config(id).disableTab, false) }
    func records(in id: String) -> Bool { resolve(config(id).record, prefs.recordWriting) }

    /// Completion length after battery adjustments.
    var effectiveLength: CompletionLength {
        (Power.onBattery && prefs.batteryShorter) ? prefs.completionLength.shorter : prefs.completionLength
    }

    /// Battery rules: right now suggestions should only appear on demand (force shortcut).
    var onDemandOnly: Bool {
        guard Power.onBattery else { return false }
        return prefs.batteryOnDemand || (prefs.lowBatteryOnDemand && Power.batteryLevel <= 20)
    }

    /// Model to use right now, following the plug/unplug rule.
    var effectiveModelPath: String {
        let battery = prefs.batteryModelPath.isEmpty ? prefs.modelPath : prefs.batteryModelPath
        switch prefs.modelMode {
        case .automatic: return Power.onBattery ? battery : prefs.modelPath
        case .pluggedIn: return prefs.modelPath
        case .battery: return battery
        }
    }
}
