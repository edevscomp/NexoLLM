import Foundation

/// Tracks the user's writing activity with zero per-keystroke timers.
///
/// Deadlines are checked lazily: one timer is armed per idle period and, when it fires, it re-arms
/// itself only for the time that's left if the user kept typing. A 10-minute typing session therefore
/// costs a handful of timer fires instead of one allocation per keystroke.
///
/// - `onWake`: first keystroke after an idle period (a new writing burst begins).
/// - `onIdle`: no keystrokes for `idleAfter()` seconds (the app goes quiet).
/// - `whenPaused`: run something once the user pauses for a few seconds (e.g. refresh screen context).
final class Activity {
    private(set) var lastKey = Date.distantPast
    /// Start of the current writing burst (set on the first keystroke after being idle).
    private(set) var wokeAt: Date?
    private(set) var isIdle = true

    var idleAfter: () -> TimeInterval = { 60 }
    var onWake: (() -> Void)?
    var onIdle: (() -> Void)?

    private var idleArmed = false
    private var pauseArmed = false
    private var pauseLength: TimeInterval = 0
    private var pauseBody: (() -> Void)?

    /// Seconds since the last keystroke.
    var quietFor: TimeInterval { Date().timeIntervalSince(lastKey) }

    func keystroke() {
        let now = Date()
        lastKey = now
        if isIdle {
            isIdle = false
            wokeAt = now
            onWake?()
        }
        if !idleArmed { armIdle(after: idleAfter()) }
    }

    /// Runs `body` once the user has stopped typing for `pause` seconds. A newer request replaces
    /// the pending one; the timer is armed once and re-armed lazily while the user keeps typing.
    func whenPaused(_ pause: TimeInterval, _ body: @escaping () -> Void) {
        pauseBody = body
        pauseLength = pause
        guard !pauseArmed else { return }
        armPause(after: max(0.05, pause - quietFor))
    }

    func cancelPause() { pauseBody = nil }

    private func armIdle(after delay: TimeInterval) {
        idleArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, delay)) { [weak self] in
            guard let self else { return }
            self.idleArmed = false
            guard !self.isIdle else { return }
            let limit = self.idleAfter()
            let quiet = self.quietFor
            if quiet + 0.05 >= limit {
                self.isIdle = true
                self.pauseBody = nil
                self.onIdle?()
            } else {
                self.armIdle(after: limit - quiet)
            }
        }
    }

    private func armPause(after delay: TimeInterval) {
        pauseArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.pauseArmed = false
            guard let body = self.pauseBody else { return }
            let quiet = self.quietFor
            if quiet + 0.05 >= self.pauseLength {
                self.pauseBody = nil
                body()
            } else {
                self.armPause(after: self.pauseLength - quiet)
            }
        }
    }
}
