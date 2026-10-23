// Appended to the unchanged manager source so this fixture can drive its private async seams.
private enum PrivacyCheckError: Error { case failed(String) }

extension ClipboardManager {
    @MainActor static func checkSessionPrivacy() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw PrivacyCheckError.failed(message) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-clipboard-privacy-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ClipboardManager(storageDirectory: directory)
        defer { manager.stopMonitoring() }
        try await Task.sleep(for: .milliseconds(100))
        manager.startMonitoring()
        manager.prependText("Retained unlocked history")
        let retained = manager.recentItems
        let board = PrivacyFixture.pasteboard
        board.clearContents()
        try check(board.setString("Queued before lock", forType: .string), "Named pasteboard unavailable")
        manager.captureCurrentIfNeeded()
        try check(PasteboardLane.shared.queuedCount == 1, "Fixture did not queue a capture")
        manager.setSessionSuppressed(true)
        manager.startMonitoring()
        manager.beginHighPriorityMonitoring()
        manager.captureCurrentIfNeeded()
        manager.applyRemoteClipboard(text: "Locked remote content", from: "Fixture")
        manager.copyToClipboard("Locked explicit content")
        try check(manager.pasteboardSubscription == nil, "Lock did not unsubscribe polling")
        try check(PasteboardLane.shared.queuedCount == 1, "Locked callbacks queued pasteboard work")
        PasteboardLane.shared.flush()
        try await Task.sleep(for: .milliseconds(100))
        try check(manager.recentItems == retained, "Queued or locked content entered history")
        try check(board.string(forType: .string) == "Queued before lock", "Locked action wrote pasteboard")
        board.clearContents()
        board.setString("Changed while locked", forType: .string)
        manager.setSessionSuppressed(false)
        manager.captureCurrentIfNeeded()
        try check(manager.pasteboardSubscription != nil, "Unlock did not restore enabled polling")
        try check(PasteboardLane.shared.queuedCount == 0, "Unlock captured the locked clipboard")
        try check(manager.recentItems == retained, "Privacy transition changed history")
        print("PASS: lock suspends polling and actions, invalidates queued reads, and unlock skips locked clipboard")

        // A background payload may finish after a full lock/unlock cycle. Its generation stays invalid.
        let blocker = DispatchSemaphore(value: 0)
        manager.processingQueue.async { blocker.wait() }
        manager.receive(ClipboardRawCapture(changeCount: manager.lastChangeCount + 1, payload: .text("Late decoded payload")))
        manager.setSessionSuppressed(true)
        manager.setSessionSuppressed(false)
        blocker.signal()
        try await Task.sleep(for: .milliseconds(200))
        try check(manager.recentItems == retained, "Pre-lock decoded payload replayed after unlock")

        manager.writePlainText("Queued write before lock")
        manager.setSessionSuppressed(true)
        manager.setSessionSuppressed(false)
        PasteboardLane.shared.flush()
        try check(board.string(forType: .string) == "Changed while locked", "Queued write replayed after unlock")
        print("PASS: completed payloads and queued writes cannot replay across a lock/unlock cycle")

        board.clearContents()
        board.setString("New unlocked content", forType: .string)
        manager.captureCurrentIfNeeded()
        PasteboardLane.shared.flush()
        try await Task.sleep(for: .milliseconds(200))
        try check(manager.recentItems.first?.textContent == "New unlocked content", "Unlocked capture did not resume")
        SettingsModel.shared.settings.clipboardMonitoringEnabled = false
        manager.setSessionSuppressed(true)
        manager.setSessionSuppressed(false)
        try check(manager.pasteboardSubscription == nil, "Unlock enabled a disabled clipboard setting")
        try check(!SettingsModel.shared.settings.clipboardMonitoringEnabled, "Privacy altered clipboard preference")
        print("PASS: new unlocked changes capture normally and disabled preference remains disabled")
    }
}

extension PasteboardChangeMonitor {
    @MainActor static func checkSuppression() throws {
        let monitor = PasteboardChangeMonitor.shared
        var calls = 0
        let token = monitor.subscribe(interval: 0.1) { _ in calls += 1 }
        defer { monitor.unsubscribe(token) }
        monitor.setSessionSuppressed(true)
        PrivacyFixture.pasteboard.clearContents()
        PrivacyFixture.pasteboard.setString("Locked monitor event", forType: .string)
        monitor.scheduleEventChecks()
        monitor.tick()
        guard calls == 0, monitor.fallbackTimer == nil, monitor.pendingEventChecks.isEmpty else {
            throw PrivacyCheckError.failed("Suppressed shared monitor restarted or delivered a callback")
        }
        monitor.setSessionSuppressed(false)
        monitor.tick()
        guard calls == 0 else { throw PrivacyCheckError.failed("Monitor replayed locked change on unlock") }
        PrivacyFixture.pasteboard.clearContents()
        PrivacyFixture.pasteboard.setString("Unlocked monitor event", forType: .string)
        monitor.tick()
        guard calls == 1 else { throw PrivacyCheckError.failed("Monitor did not resume new changes") }
        print("PASS: shared event/fallback monitor stays stopped through workspace callbacks and resets its baseline")
    }
}

@main struct ClipboardPrivacyChecks {
    @MainActor static func main() async {
        defer { PrivacyFixture.pasteboard.releaseGlobally() }
        do {
            try await ClipboardManager.checkSessionPrivacy()
            try PasteboardChangeMonitor.checkSuppression()
            print("PASS: all clipboard session privacy checks")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
