import AppKit
import Carbon.HIToolbox

/// Global keyboard/mouse event tap. The handler returns true to swallow an event.
final class KeyboardTap {
    /// Marks events we synthesize ourselves so the tap lets them through untouched.
    static let syntheticMarker: Int64 = 0x4652_4545   // "FREE"

    var handler: ((CGEvent, CGEventType) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Self-healing: macOS can disable the tap (slow callback, secure input) or invalidate its port
    /// (sleep/wake, screen lock, session switch). Re-enables it, or rebuilds it from scratch if the port died.
    /// Cheap; called on system events (wake, unlock, app switch), never on a timer.
    @discardableResult
    func ensureRunning(reason: String) -> Bool {
        guard let t = tap else { return start() }
        if !CFMachPortIsValid(t) {
            Log.info("tap: port invalid (\(reason)) — rebuilding")
            teardown()
            return start()
        }
        if !CGEvent.tapIsEnabled(tap: t) {
            Log.info("tap: was disabled (\(reason)) — re-enabling")
            CGEvent.tapEnable(tap: t, enable: true)
            if !CGEvent.tapIsEnabled(tap: t) { teardown(); return start() }
        }
        return true
    }

    /// Rebuilds the tap from scratch (soft restart).
    func restart() -> Bool { teardown(); return start() }

    private func teardown() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<KeyboardTap>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                Log.info("tap: disabled by system (\(type == .tapDisabledByTimeout ? "timeout" : "user input")) — re-enabled")
                return Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.eventSourceUserData) == KeyboardTap.syntheticMarker {
                return Unmanaged.passUnretained(event)
            }
            if me.handler?(event, type) == true { return nil }
            return Unmanaged.passUnretained(event)
        }

        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        source = src
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }
}

/// Types text into the focused app by posting Unicode keyboard events.
/// Works in native, web and Electron apps and keeps the app's own undo stack.
enum TextInjector {
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .privateState)
        let units = Array(SuggestionText.safeForInsertion(text).utf16)
        var i = 0
        while i < units.count {
            var end = min(i + 20, units.count)   // CGEvent carries at most 20 UTF-16 units
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            var chunk = Array(units[i..<end])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                e.setIntegerValueField(.eventSourceUserData, value: KeyboardTap.syntheticMarker)
                e.post(tap: .cgSessionEventTap)
            }
            i = end
        }
    }

    static func key(_ code: CGKeyCode, flags: CGEventFlags = [], times: Int = 1) {
        let source = CGEventSource(stateID: .privateState)
        for _ in 0..<times {
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
                e.flags = flags
                e.setIntegerValueField(.eventSourceUserData, value: KeyboardTap.syntheticMarker)
                e.post(tap: .cgSessionEventTap)
            }
        }
    }

    static func backspace(_ count: Int) {
        guard count > 0 else { return }
        key(CGKeyCode(kVK_Delete), times: count)
    }

    /// Paste-based insertion for apps that drop synthetic Unicode key events. The user's clipboard (every item and
    /// format) is put back afterwards, and the temporary text is marked transient so clipboard history apps skip it.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = Pasteboards.snapshot(pb)
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(SuggestionText.safeForInsertion(text), forType: .string)
        item.setData(Data(), forType: Pasteboards.transient)
        item.setData(Data(), forType: Pasteboards.autoGenerated)
        pb.writeObjects([item])
        let ours = pb.changeCount
        key(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // If the user copied something new meanwhile, leave it alone.
            guard pb.changeCount == ours else { return }
            Pasteboards.restore(pb, saved)
        }
    }
}
