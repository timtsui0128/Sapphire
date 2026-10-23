import AppKit
import Combine
import Foundation

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "SessionPrivacyChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
private struct SessionPrivacyChecks {
    @MainActor static func main() async throws {
        let active = SessionPrivacySnapshot(screenIsLocked: false, sessionIsActive: true)
        let locked = SessionPrivacySnapshot(screenIsLocked: true, sessionIsActive: true)
        let inactive = SessionPrivacySnapshot(screenIsLocked: false, sessionIsActive: false)
        let console: [String: Any] = ["kCGSSessionOnConsoleKey": true, "kCGSessionLoginDoneKey": true]
        try check(SessionPrivacySnapshot.decode(console) == active, "An unlocked console may omit the private lock key")
        var dictionary = console
        dictionary["CGSSessionScreenIsLocked"] = true
        try check(SessionPrivacySnapshot.decode(dictionary) == locked, "System lock flag must suppress")
        dictionary = console
        dictionary["kCGSSessionOnConsoleKey"] = false
        try check(SessionPrivacySnapshot.decode(dictionary) == inactive, "Inactive console must suppress")
        dictionary = console
        dictionary["kCGSessionLoginDoneKey"] = false
        try check(SessionPrivacySnapshot.decode(dictionary).requiresSuppression, "Incomplete login must suppress")
        try check(SessionPrivacySnapshot.decode(nil).requiresSuppression && SessionPrivacySnapshot.decode([:]).requiresSuppression, "Unknown session must fail closed")
        print("PASS: system dictionary decoding for active, locked, inactive, incomplete and unknown sessions")

        for snapshot in [locked, inactive, .unknown] {
            let launch = SessionPrivacyState(snapshotProvider: { snapshot }, observesNotifications: false)
            try check(launch.isSuppressed, "Launch must never briefly expose a locked/inactive/unknown session")
        }
        let unlockedLaunch = SessionPrivacyState(snapshotProvider: { active }, observesNotifications: false)
        try check(!unlockedLaunch.isSuppressed, "An active unlocked launch may show UI")
        print("PASS: launch-locked and launch-inactive state is suppressed before any notification")

        var state = SessionPrivacyReducer(snapshot: active)
        state.setLocked(true, snapshot: active) // Simulate a lagging CG read.
        try check(state.isSuppressed, "Lock notification must override a stale unlocked snapshot")
        state.setSessionActive(false, snapshot: active)
        state.setSessionActive(true, snapshot: active)
        state.refresh(active) // A screen wake merely refreshes.
        try check(state.isSuppressed, "Session active/wake must not clear an observed lock")
        state.setLocked(false, snapshot: locked)
        try check(state.isSuppressed, "Unlock notification must not override a still-locked system snapshot")
        state.refresh(active)
        try check(!state.isSuppressed, "Confirmed unlock should restore availability")
        state.setSessionActive(false, snapshot: active)
        state.setLocked(false, snapshot: active)
        try check(state.isSuppressed, "Unlock must not override a resigned session")
        state.setSessionActive(true, snapshot: active)
        try check(!state.isSuppressed, "Both lock and inactive reasons must clear before showing UI")
        print("PASS: independent lock/session latches and conservative event ordering")

        let distributed = NotificationCenter()
        let workspace = NotificationCenter()
        var system = active
        let service = SessionPrivacyState(
            snapshotProvider: { system }, distributedCenter: distributed, workspaceCenter: workspace
        )
        var changes: [Bool] = []
        let subscription = service.$isSuppressed.dropFirst().sink { changes.append($0) }
        distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        try check(service.isSuppressed && changes == [true], "Repeated lock and wake notifications must keep one stable suppression state")
        system = locked
        distributed.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        try check(service.isSuppressed, "Delayed system unlock must remain suppressed")
        system = active
        try await Task.sleep(for: .milliseconds(110))
        try check(!service.isSuppressed && changes == [true, false], "Bounded settling refresh must restore only after CG confirms unlock")
        workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        distributed.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        try check(service.isSuppressed, "Inactive notification latch survives an unlock")
        workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        try check(!service.isSuppressed, "Active notification restores an already unlocked session")
        subscription.cancel()
        print("PASS: isolated notification-center integration, deduplicated publishing and delayed unlock recovery")

        service.setLocked(true)
        system = locked
        service.setLocked(false) // Schedules a delayed recheck.
        service.setLocked(true) // A new lock must invalidate that pending unlock.
        system = active
        try await Task.sleep(for: .milliseconds(110))
        try check(service.isSuppressed, "Older unlock settling work must never bypass a newer lock")
        service.setLocked(false)
        try check(!service.isSuppressed, "A later genuine unlock remains functional")
        system = .unknown
        service.refreshFromSystem()
        try check(service.isSuppressed, "Loss of system-session information must hide existing UI")
        print("PASS: interrupted unlock retries and unknown-session refresh remain fail-closed")

        try check(SessionPrivacyState.isSuppressedSnapshot, "Process input gate must be closed before shared service initialization")
        system = active
        let processService = SessionPrivacyState(
            snapshotProvider: { system }, observesNotifications: false, publishesProcessState: true
        )
        try check(!SessionPrivacyState.isSuppressedSnapshot, "Known unlocked initialization opens cached input gate")
        var gateMatchesPublished = true
        let gateSubscription = processService.$isSuppressed.dropFirst().sink { value in
            gateMatchesPublished = gateMatchesPublished && SessionPrivacyState.isSuppressedSnapshot == value
        }
        processService.setLocked(true)
        try check(SessionPrivacyState.shouldSuppressUI() && gateMatchesPublished, "Synchronous UI gate must close before suppression subscribers run")
        let backgroundRead = await Task.detached {
            (0..<10_000).allSatisfy { _ in SessionPrivacyState.isSuppressedSnapshot }
        }.value
        try check(backgroundRead, "Event taps must read the cached gate safely off the main actor")
        processService.setLocked(false)
        try check(!SessionPrivacyState.isSuppressedSnapshot && gateMatchesPublished, "Input gate and published unlock must agree")
        gateSubscription.cancel()
        print("PASS: thread-safe synchronous input/display gate and publish ordering")
        print("All checks used injected state and private notification centers; no system lock or preferences were changed.")
    }
}
