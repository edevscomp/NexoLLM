import XCTest
@testable import NexoLLM

/// The "when to take a screenshot" policy, checked against real usage scenarios.
final class CapturePolicyTests: XCTestCase {
    private let t = ScreenContext.Tunables.pluggedIn
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func snap(at seconds: TimeInterval, caret: Int = 100, y: CGFloat = 500) -> ScreenContext.Snapshot {
        .init(text: "riga visibile", date: t0.addingTimeInterval(seconds), caret: caret, caretY: y)
    }

    private func reason(_ s: ScreenContext.Snapshot?, now: TimeInterval, caret: Int = 100, y: CGFloat = 500,
                        wokeAt: TimeInterval? = nil, revisit: Bool = false, atPause: Bool = false) -> ScreenContext.Reason? {
        ScreenContext.reason(snapshot: s, now: t0.addingTimeInterval(now), caret: caret, caretY: y,
                             wokeAt: wokeAt.map { t0.addingTimeInterval($0) }, revisit: revisit, atPause: atPause, t)
    }

    func testFirstKeystrokeInNewFieldCaptures() {
        XCTAssertEqual(reason(nil, now: 0), .firstLook)
    }

    func testTypingContinuouslyNeverCaptures() {
        // A whole paragraph typed in one go (caret moved 900 chars): no capture while typing…
        XCTAssertNil(reason(snap(at: 0), now: 200, caret: 1000, wokeAt: -1))
        // …only once the user pauses.
        XCTAssertEqual(reason(snap(at: 0), now: 200, caret: 1000, wokeAt: -1, atPause: true), .drift)
    }

    func testShortTextDoesNotDriftEvenAtPause() {
        // "Ciao, come va?" → "Spero male." is a few chars: the snapshot is still valid.
        XCTAssertNil(reason(snap(at: 0), now: 30, caret: 130, wokeAt: -1, atPause: true))
    }

    func testScrollingFarDriftsAtPause() {
        XCTAssertEqual(reason(snap(at: 0), now: 20, caret: 120, y: 900, wokeAt: -1, atPause: true), .drift)
    }

    func testWakeAfterIdleCaptures() {
        // Snapshot from before the idle period, new writing burst started at 300 s.
        XCTAssertEqual(reason(snap(at: 0), now: 300, wokeAt: 300), .wake)
        // Once captured in this burst, no more.
        XCTAssertNil(reason(snap(at: 301), now: 320, wokeAt: 300))
    }

    func testAppSwitchingReusesRecentSnapshot() {
        // Back to Obsidian 10 s later: reuse, no new screenshot.
        XCTAssertNil(reason(snap(at: 0), now: 10, wokeAt: -1, revisit: true))
        // Back after 5 minutes: look again.
        XCTAssertEqual(reason(snap(at: 0), now: 300, wokeAt: -1, revisit: true), .revisit)
    }

    func testGlobalCooldownBlocksBursts() {
        let screen = ScreenContext()
        XCTAssertEqual(screen.cooldownRemaining(t), 0)
    }
}

final class ActivityTests: XCTestCase {
    func testWakeOnFirstKeystrokeOnly() {
        let a = Activity()
        a.idleAfter = { 60 }
        var wakes = 0
        a.onWake = { wakes += 1 }
        a.keystroke(); a.keystroke(); a.keystroke()
        XCTAssertEqual(wakes, 1)
        XCTAssertFalse(a.isIdle)
        XCTAssertNotNil(a.wokeAt)
    }

    func testIdleFiresAfterQuietPeriod() {
        let a = Activity()
        a.idleAfter = { 0.2 }
        let idle = expectation(description: "idle")
        a.onIdle = { idle.fulfill() }
        a.keystroke()
        wait(for: [idle], timeout: 2)
        XCTAssertTrue(a.isIdle)
    }

    func testPauseCallbackWaitsForQuiet() {
        let a = Activity()
        a.idleAfter = { 60 }
        let paused = expectation(description: "paused")
        let start = Date()
        a.keystroke()
        a.whenPaused(0.3) {
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.4)   // re-armed by the later keystroke
            paused.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { a.keystroke() }
        wait(for: [paused], timeout: 2)
    }
}
