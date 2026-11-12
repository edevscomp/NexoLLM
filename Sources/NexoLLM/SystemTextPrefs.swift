import AppKit

/// macOS's own typing aids that compete with NexoLLM's suggestions. Both live in the global preferences
/// domain (`defaults -g`), are reversible with one click, and are read back after every change so the
/// Settings show what macOS really stored — not what we hoped it stored.
enum SystemTextPrefs {
    enum Kind: CaseIterable {
        /// Apple's grey inline predictions after the cursor (macOS 14+).
        case inlinePrediction
        /// The blue bubble that replaces misspelled words ("cao" → "ciao") as you type.
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
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return boolValue(CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                                                kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
    }

    /// Writes the value and reads it back. Returns true when macOS now reports exactly `on`.
    @discardableResult
    static func write(key: String, on: Bool) -> Bool {
        CFPreferencesSetValue(key as CFString, on as CFBoolean, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        if read(key: key) == on { return true }
        // Fallback: the same change through `defaults`, which talks to cfprefsd directly.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["write", "-g", key, "-bool", on ? "true" : "false"]
        try? p.run()
        p.waitUntilExit()
        return read(key: key) == on
    }

    static func isOn(_ kind: Kind) -> Bool { read(key: kind.keys[0]) }

    /// Turns the setting on or off for every app; true when macOS confirmed it.
    @discardableResult
    static func set(_ kind: Kind, on: Bool) -> Bool {
        let ok = kind.keys.map { write(key: $0, on: on) }.allSatisfy { $0 }
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
