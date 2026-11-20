import AppKit

/// macOS's own typing aids that compete with NexoLLM's suggestions. They live in the global preferences
/// domain (`defaults -g`), are reversible with one click, and are read back after every change so the
/// Settings show what macOS really stored — not what we hoped it stored.
///
/// Running apps cache these flags in memory: System Settings tells them to re-read by posting a distributed
/// notification per key, and so do we — otherwise apps already open keep showing the system's popup.
enum SystemTextPrefs {
    enum Kind: CaseIterable {
        /// Apple's grey inline predictions and the word-completion popup under the cursor.
        case inlinePrediction
        /// The blue bubble that replaces misspelled words ("helo" → "hello") as you type.
        case autocorrect

        /// Keys written for this setting; `keys[0]` is the one the Settings toggle reflects first.
        var keys: [String] {
            switch self {
            case .inlinePrediction: return ["NSAutomaticInlinePredictionEnabled", "NSAutomaticTextCompletionEnabled"]
            case .autocorrect: return ["NSAutomaticSpellingCorrectionEnabled", "WebAutomaticSpellingCorrectionEnabled"]
            }
        }

        /// Cross-process names AppKit itself posts when System Settings changes these keys (verified in AppKit).
        var notifications: [String] {
            switch self {
            case .inlinePrediction: return ["NSAutomaticInlinePredictionEnabledChanged", "NSAutomaticTextCompletionEnabledChanged"]
            case .autocorrect: return ["NSAutomaticSpellingCorrectionEnabledChanged"]
            }
        }
    }

    /// A missing key means macOS's default, which is "on" for all of them.
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

    /// On while any key of the group is on: a half-disabled group still shows the system's popup.
    static func isOn(_ kind: Kind) -> Bool { kind.keys.contains(where: read(key:)) }

    /// Turns the setting on or off for every app, tells running apps to re-read it; true when macOS confirmed it.
    @discardableResult
    static func set(_ kind: Kind, on: Bool) -> Bool {
        let ok = kind.keys.map { write(key: $0, on: on) }.allSatisfy { $0 }
        broadcast(kind)
        Log.info("system prefs: \(kind.keys.joined(separator: ", ")) = \(on) (\(ok ? "confirmed" : "not confirmed"))")
        return ok
    }

    static func broadcast(_ kind: Kind) {
        for name in kind.notifications {
            DistributedNotificationCenter.default().postNotificationName(.init(name), object: nil, userInfo: nil,
                                                                         deliverImmediately: true)
        }
    }

    /// Older versions turned off only the first key of each group: finish the job if the user had chosen off.
    static func reconcileOnLaunch() {
        for kind in Kind.allCases where !read(key: kind.keys[0]) && isOn(kind) {
            set(kind, on: false)
        }
    }

    private static var checkedApps = Set<String>()

    /// An app's own domain overrides the global one: drop a leftover "on" there when the user chose off globally.
    /// At most once per app per session; only removes `true` values of our keys, never anything else.
    static func clearOverrides(for bundleID: String) {
        guard !bundleID.isEmpty, checkedApps.insert(bundleID).inserted else { return }
        for kind in Kind.allCases where !isOn(kind) {
            let stale = kind.keys.filter {
                CFPreferencesCopyValue($0 as CFString, bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                    .map { boolValue($0) } == true
            }
            guard !stale.isEmpty else { continue }
            for key in stale {
                CFPreferencesSetValue(key as CFString, nil, bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
            CFPreferencesSynchronize(bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            broadcast(kind)
            Log.info("system prefs: removed \(stale.joined(separator: ", ")) override from \(bundleID)")
        }
    }

    /// System Settings › Keyboard, where the switches can be checked by eye.
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
