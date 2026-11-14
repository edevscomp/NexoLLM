import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click to record a key combination. Esc cancels. Optional variant can be cleared with ✕.
struct ShortcutRecorder: View {
    /// A recorder is waiting for keys: global hotkeys must not swallow them.
    static var isRecording = false
    private static var stopActive: (() -> Void)?
    private static var activeToken = UUID()
    @Binding private var shortcut: Shortcut?
    private let optional: Bool
    @State private var recording = false
    @State private var monitor: Any?
    @State private var token = UUID()

    init(shortcut: Binding<Shortcut>) {
        _shortcut = Binding(get: { shortcut.wrappedValue },
                            set: { if let v = $0 { shortcut.wrappedValue = v } })
        optional = false
    }

    init(optional shortcut: Binding<Shortcut?>) {
        _shortcut = shortcut
        optional = true
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: { recording ? stop() : start() }) {
                Text(title)
                    .font(recording ? .body : .body.monospaced())
                    .foregroundStyle(recording ? Color.accentColor : .primary)
                    .frame(minWidth: 96)
            }
            if optional, shortcut != nil, !recording {
                Button { shortcut = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("Clear shortcut", "Cancella scorciatoia"))
            }
        }
        .onDisappear(perform: stop)
    }

    private var title: String {
        if recording { return L("Type shortcut…", "Premi i tasti…") }
        return shortcut?.display ?? L("Record Shortcut", "Registra scorciatoia")
    }

    private func start() {
        Self.stopActive?()
        stop()
        let myToken = UUID()
        token = myToken
        Self.activeToken = myToken
        Self.stopActive = { if Self.activeToken == myToken { stop() } }
        recording = true
        Self.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Int(event.keyCode) == kVK_Escape && mods.intersection([.command, .control, .option, .shift]).isEmpty {
                stop()
                return nil
            }
            shortcut = Shortcut(Int(event.keyCode), Self.cgFlags(mods))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        if Self.activeToken == token {
            Self.isRecording = false
            Self.stopActive = nil
        }
    }

    static func cgFlags(_ m: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.shift) { f.insert(.maskShift) }
        return f
    }
}
