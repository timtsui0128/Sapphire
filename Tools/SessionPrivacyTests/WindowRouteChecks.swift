import AppKit
import Foundation

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "WindowRouteChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
private struct WindowRouteChecks {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try await Task.sleep(for: .milliseconds(80))
        // Initialize the real singleton once, then inject only this process's
        // gate. These calls do not lock the Mac or post OS notifications.
        _ = SessionPrivacyState.shared
        var system = SessionPrivacySnapshot(screenIsLocked: true, sessionIsActive: true)
        let simulated = SessionPrivacyState(
            snapshotProvider: { system },
            observesNotifications: false, publishesProcessState: true
        )
        try check(simulated.isSuppressed, "Fixture must close the process gate")
        let rect = NSRect(x: 20, y: 20, width: 120, height: 80)
        let windows: [NSWindow] = [
            KeyableWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: true),
            KeyablePanel(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: true),
            KeyableNonMainPanel(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: true)
        ]
        for window in windows {
            window.isReleasedWhenClosed = false
            try check(!window.canBecomeKey && !window.canBecomeMain, "Suppressed window must reject key/main focus")
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.orderFront(nil)
            window.order(.above, relativeTo: 0)
            try check(!window.isVisible && !window.isKeyWindow && !window.isMainWindow, "All native window ordering routes must remain hidden")
        }
        print("PASS: actual KeyableWindow, KeyablePanel and KeyableNonMainPanel block ordering and focus")

        let plain = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: true)
        plain.isReleasedWhenClosed = false
        let initialActivationPolicy = app.activationPolicy()
        system = .init(screenIsLocked: false, sessionIsActive: true)
        simulated.setLocked(false)
        UtilityWindowPresenter.presentSettingsWindow(plain)
        UtilityWindowPresenter.present(plain)
        // Both show requests are queued; lock before either main-queue closure runs.
        simulated.setLocked(true)
        UtilityWindowPresenter.activateAsRegularApp()
        try await Task.sleep(for: .milliseconds(120))
        try check(!plain.isVisible && !plain.isKeyWindow, "Deferred presenter closures must recheck suppression")
        try check(app.activationPolicy() == initialActivationPolicy, "Suppressed presentation must not change app activation policy")
        print("PASS: actual utility presentation closures reject plain windows and app activation after deferral")

        let progress = FileOperationProgressPresenter.shared
        progress.update(FileTransferTask(isComplete: false))
        try await Task.sleep(for: .milliseconds(60))
        progress.update(FileTransferTask(isComplete: true))
        try check(!progress.hasPrivacyTestPanel, "Ongoing file transfer callbacks must not create a popup while suppressed")
        progress.update(nil)
        print("PASS: actual file progress presenter ignores ongoing and completed background updates while locked")
        for window in windows + [plain] { window.close() }
        print("Only hidden test windows were created; no OS lock, preferences or permissions changed.")
    }
}
