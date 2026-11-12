import AppKit
import ApplicationServices

/// Event-driven focus tracking: an AXObserver on the frontmost app reports focus changes,
/// so we never poll Accessibility on a timer.
final class FocusObserver {
    var onChange: (() -> Void)?
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var pid: pid_t = 0
    private var pending: DispatchWorkItem?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.attach(app)
            self?.fire()
        }
        attach(NSWorkspace.shared.frontmostApplication)
    }

    private func attach(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != pid,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        detach()
        pid = app.processIdentifier
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<FocusObserver>.fromOpaque(refcon).takeUnretainedValue().fire()
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let el = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(obs, el, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        appElement = el
    }

    private func detach() {
        if let obs = observer {
            if let el = appElement {
                for n in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
                    AXObserverRemoveNotification(obs, el, n as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observer = nil; appElement = nil; pid = 0
    }

    /// Coalesces bursts of notifications into one callback.
    private func fire() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
