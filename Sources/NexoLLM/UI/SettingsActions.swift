import AppKit

/// Callbacks the Settings UI uses to talk to the running app (implemented in AppDelegate).
struct SettingsActions {
    /// Reload the model at `Settings.shared.effectiveModelPath`.
    var reloadModel: () -> Void
    /// Open System Settings → Privacy → Accessibility (and trigger the system prompt).
    var openAccessibilitySettings: () -> Void
    /// Trigger the Screen Recording prompt / open its System Settings pane.
    var requestScreenRecording: () -> Void
    /// Reveal the folder containing the current model in Finder.
    var revealModels: () -> Void
    /// Restart NexoLLM services in place without closing the window.
    var restartServices: () -> Void = {}
}

/// Live engine status shown in the Settings window.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()
    @Published var engine: String = "Starting…"
    @Published var modelReady = false
}
