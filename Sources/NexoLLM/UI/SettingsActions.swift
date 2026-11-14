import AppKit

/// Callbacks the Settings UI uses to talk to the running app (implemented in AppDelegate).
struct SettingsActions {
    /// Open System Settings → Privacy → Accessibility (and trigger the system prompt).
    var openAccessibilitySettings: () -> Void = {}
    /// Trigger the Screen Recording prompt / open its System Settings pane.
    var requestScreenRecording: () -> Void = {}
    /// Restart NexoLLM services in place without closing the window.
    var restartServices: () -> Void = {}
    static let none = SettingsActions()
}

/// Live engine status shown in the Settings window.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()
    @Published var engine: String = "Starting…"
    @Published var modelReady = false
}
