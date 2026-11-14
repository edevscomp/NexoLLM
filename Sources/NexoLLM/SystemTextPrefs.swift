import AppKit

/// macOS's own typing aids that compete with NexoLLM's suggestions. Both live in the global preferences
/// domain (`defaults -g`), are reversible with one click, and are read back after every change so the
/// Settings show what macOS really stored — not what we hoped it stored.
enum SystemTextPrefs {
    enum Kind: CaseIterable {
        /// Apple's grey inline predictions after the cursor (macOS 14+).
        case inlinePrediction
        /// The blue bubble that replaces misspelled words ("helo" → "hello") as you type.
        case autocorrect

        /// Keys written for this setting. Autocorrect has a separate key for WebKit text fields (Safari, Mail).
        var keys: [String] {
            switch self {
            case .inlinePrediction: return ["NSAutomaticInlinePredictionEnabled"]
            case .autocorrect: return ["NSAutomaticSpellingCorrectionEnabled", "WebAutomaticSpellingCorrectionEnabled"]
            }
        }
    }

    /// A missing key means macOS's default, which is "on" for both.
    static func boolValue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String { return !["0", "false", "no"].contains(s.lowercased()) }
        return true
    }

    static func read(key: String) -> Bool {
        boolValue(CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                                         kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
    }

    /// Writes the value via CFPreferences (zero subprocess spawn) and confirms it.
    @discardableResult
    static func write(key: String, on: Bool) -> Bool {
        CFPreferencesSetValue(key as CFString, on as CFBoolean, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return read(key: key) == on
    }

    static func isOn(_ kind: Kind) -> Bool { read(key: kind.keys[0]) }

    /// Turns the setting on or off for every app; true when macOS confirmed it.
    @discardableResult
    static func set(_ kind: Kind, on: Bool) -> Bool {
        for key in kind.keys {
            CFPreferencesSetValue(key as CFString, on as CFBoolean, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let ok = kind.keys.allSatisfy { read(key: $0) == on }
        Log.info("system prefs: \(kind.keys[0]) = \(on) (\(ok ? "confirmed" : "not confirmed"))")
        return ok
    }

    /// System Settings › Keyboard, where both switches can be checked by eye.
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
