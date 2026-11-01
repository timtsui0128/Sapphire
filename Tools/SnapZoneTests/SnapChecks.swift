import AppKit

@MainActor final class DragStateManager {
    static let shared = DragStateManager()
    var isDraggingFromShelf = false
}
@MainActor final class SettingsModel {
    struct Values { var snapActivationDelay = 0.06 }
    static let shared = SettingsModel()
    var current = Values()
}

// Only OS event delivery and AX identity are replaced. Production drag-state
// methods and frame placement/readback/retry logic are compiled unchanged.
struct SnapWindowTarget: Equatable { let id: Int }
@MainActor final class EventMonitorHub {
    static let shared = EventMonitorHub()
    func register(for mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> UUID { UUID() }
    func unregister(token: UUID, for mask: NSEvent.EventTypeMask) {}
}
extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

private enum CheckError: Error { case failed(String) }
private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw CheckError.failed(message) }
}

@main struct SnapChecks {
    @MainActor static func main() throws {
        try geometry()
        try placement()
        try dragState()
        try activation()
        try systemDragHandoff()
        try asynchronousPlacement()
        try compatibility()
        print("PASS: snap geometry, placement/retry, release identity and bounded dwell activation")
    }

    @MainActor static func activation() throws {
        let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                        CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                        CGRect(x: 100, y: 900, width: 1920, height: 1080)]
        for screen in displays {
            try check(SnapActivationRegion.contains(CGPoint(x: screen.midX, y: screen.maxY - 72), in: screen), "Inset top-center target rejected")
            for x in [screen.minX, screen.midX, screen.maxX] {
                for depth in [CGFloat(0), 6, 12] {
                    let point = CGPoint(x: x, y: screen.maxY - depth)
                    try check(!SnapActivationRegion.contains(point, in: screen), "System top edge entered snap activation")
                    try check(SnapActivationRegion.isSystemTopEdge(point, in: screen), "System edge rejected on an offset display")
                }
            }
            try check(!SnapActivationRegion.isSystemTopEdge(CGPoint(x: screen.midX, y: screen.maxY - 72), in: screen), "Snap target handed off to system")
            for point in [CGPoint(x: screen.midX, y: screen.midY),
                          CGPoint(x: screen.midX + 200, y: screen.maxY - 72),
                          CGPoint(x: screen.midX, y: screen.maxY - 30),
                          CGPoint(x: screen.midX, y: screen.maxY - 100),
                          CGPoint(x: screen.midX, y: screen.maxY + 1)] {
                try check(!SnapActivationRegion.contains(point, in: screen), "Ordinary window drag entered activation region")
            }
        }
        try check(!SnapActivationRegion.contains(.zero, in: .zero), "Missing display triggered snap")

        var mouseDown = true
        let manager = GlobalDragManager(isPrimaryButtonPressed: { mouseDown })
        func wait(_ seconds: TimeInterval = 0.1) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        manager.startMonitoring()
        manager.updateDrag(isInsideActivationZone: false)
        wait()
        try check(!manager.isDraggingInActivationZone && !manager.isActivationPending, "Ordinary movement opened the panel")
        manager.updateDrag(isInsideActivationZone: true)
        try check(!manager.isDraggingInActivationZone && manager.isActivationPending, "Entering skipped the dwell")
        manager.updateDrag(isInsideActivationZone: false)
        wait()
        try check(!manager.isDraggingInActivationZone, "Brief crossing opened the panel after leaving")
        manager.updateDrag(isInsideActivationZone: true)
        wait()
        try check(manager.isDraggingInActivationZone, "Deliberate dwell did not open the panel")
        manager.updateDrag(isInsideActivationZone: false)
        try check(manager.isDraggingInActivationZone, "Moving from trigger to a layout dismissed the panel")
        manager.cancelActivation()
        manager.updateDrag(isInsideActivationZone: false)
        wait()
        try check(!manager.isDraggingInActivationZone, "Cancellation reopened away from the trigger")
        manager.updateDrag(isInsideActivationZone: true)
        mouseDown = false
        wait()
        try check(!manager.isDraggingInActivationZone, "Released mouse opened the panel")
        manager.endDrag()
        mouseDown = true
        var stillInside = true
        manager.updateDrag(isInsideActivationZone: true, canActivate: { stillInside })
        stillInside = false // final motion callback has not arrived yet
        wait()
        try check(!manager.isDraggingInActivationZone && !manager.isActivationPending, "Stale dwell fired after cursor left for Mission Control")
        DragStateManager.shared.isDraggingFromShelf = true
        manager.updateDrag(isInsideActivationZone: true)
        wait()
        try check(!manager.isDraggingInActivationZone, "Screenshot/file shelf drag triggered window snapping")
        manager.endDrag()
        manager.updateDrag(isInsideActivationZone: true)
        manager.stopMonitoring()
        wait()
        try check(!manager.isDraggingInActivationZone && !manager.isActivationPending, "Display teardown left a pending activation")
        print("PASS: main/left/stacked display trigger bounds; dwell, exit, release, cancellation and shelf exclusion")
    }

    @MainActor static func systemDragHandoff() throws {
        var mouseDown = true
        let state = WindowDragState(isPrimaryButtonPressed: { mouseDown })
        let manager = GlobalDragManager(isPrimaryButtonPressed: { mouseDown })
        manager.startMonitoring()
        func wait() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        for openFirst in [false, true] {
            state.beginDrag(target: SnapWindowTarget(id: 1), bypassModifierIsPressed: false)
            manager.updateDrag(isInsideActivationZone: true, canActivate: { !state.isYieldingToSystemDrag })
            if openFirst { wait(); try check(manager.isDraggingInActivationZone, "Fixture did not open snap panel") }
            state.yieldSnapZonesToSystem()
            manager.cancelActivation()
            wait()
            try check(!manager.isDraggingInActivationZone && !manager.isActivationPending, "Handoff retained open or pending snap panel")
            try check(state.shouldIgnoreSnapRelease, "System drag may apply a stale snap zone")
            // AX observer replacement must not reset a still-held physical drag.
            state.endDrag()
            state.beginDrag(target: SnapWindowTarget(id: 2), bypassModifierIsPressed: false)
            try check(state.isYieldingToSystemDrag && state.isSnapZoneDismissedForCurrentDrag, "Observer/display change rearmed system drag")
            manager.updateDrag(isInsideActivationZone: true, canActivate: { !state.isYieldingToSystemDrag })
            wait()
            try check(!manager.isDraggingInActivationZone, "Returning through target reopened during system drag")
            mouseDown = false
            wait()
            try check(!state.isYieldingToSystemDrag && !state.isDragging && state.shouldIgnoreSnapRelease, "Mouse-up lost cancellation or retained input handoff")
            manager.endDrag()
            mouseDown = true
            state.beginDrag(bypassModifierIsPressed: false)
            try check(!state.isSnapZoneDismissedForCurrentDrag && !state.shouldIgnoreSnapRelease, "New drag remained disabled")
            manager.updateDrag(isInsideActivationZone: true, canActivate: { !state.isYieldingToSystemDrag })
            wait()
            try check(manager.isDraggingInActivationZone, "New drag cannot open snap layouts")
            state.endDrag()
            manager.endDrag()
        }
        manager.stopMonitoring()
        print("PASS: Mission Control handoff before/after dwell, observer replacement, no reopen until mouse-up, next-drag recovery")
    }

    static func geometry() throws {
        let visible = CGRect(x: 0, y: 48, width: 1440, height: 828)
        let half = SnapZone(x: 0.5, y: 0, width: 0.5, height: 1)
        let right = SnapWindowPlacement.frame(for: half, in: visible)!
        try check(right == CGRect(x: 720, y: 48, width: 720, height: 828), "Half-screen ignores Dock or menu bar")
        try check(SnapWindowPlacement.axFrame(from: right, primaryDisplayMaxY: 900) == CGRect(x: 720, y: 24, width: 720, height: 828), "Primary AX Y flip")
        let leftDisplay = CGRect(x: -1920, y: -200, width: 1920, height: 1056)
        let topLeft = SnapZone(x: 0, y: 0, width: 0.5, height: 0.5)
        let quarter = SnapWindowPlacement.frame(for: topLeft, in: leftDisplay)!
        try check(quarter == CGRect(x: -1920, y: 328, width: 960, height: 528), "Negative-origin top quarter")
        try check(SnapWindowPlacement.axFrame(from: quarter, primaryDisplayMaxY: 900).minY == 44, "Offset secondary AX coordinates")
        let above = CGRect(x: 100, y: 900, width: 1920, height: 1056)
        let aboveHalf = SnapWindowPlacement.frame(for: half, in: above)!
        try check(SnapWindowPlacement.axFrame(from: aboveHalf, primaryDisplayMaxY: 900).minY == -1056, "Stacked display AX coordinates")
        for display in [visible, leftDisplay, above] {
            for layout in LayoutTemplate.allTemplates {
                for zone in layout.zones {
                    let result = SnapWindowPlacement.frame(for: zone, in: display)!
                    try check(result.minX >= display.minX - 0.001 && result.maxX <= display.maxX + 0.001
                        && result.minY >= display.minY - 0.001 && result.maxY <= display.maxY + 0.001,
                              "Template escaped the selected display")
                }
            }
        }
        try check(SnapWindowPlacement.frame(for: SnapZone(x: .nan, y: 0, width: 1, height: 1), in: visible) == nil, "NaN accepted")
        try check(SnapWindowPlacement.frame(for: SnapZone(x: 1, y: 0, width: 1, height: 1), in: visible) == nil, "Empty clipped zone accepted")
        try check(SnapWindowPlacement.frame(for: half, in: .zero) == nil, "Missing display accepted")
        print("PASS: all built-in layouts across main, left and stacked displays")
    }

    static func placement() throws {
        let start = CGRect(x: 300, y: 200, width: 900, height: 600)
        let target = CGRect(x: 0, y: 24, width: 720, height: 828)
        var actual = start, writes = 0, pauses = 0
        let recover = SnapWindowPlacement.apply(target, read: { actual },
            setSize: { actual.size = $0; writes += 1; return .accepted },
            setPosition: { actual.origin = $0; writes += 1; return .accepted }, shouldContinue: { true },
            pause: { _ in pauses += 1; if pauses == 1 { actual = start } })
        try check(recover == .applied && actual == target && pauses >= 2, "Did not recover from source app's final drag reset")
        try check(writes == 8, "Retry count is unbounded or insufficient")
        writes = 0
        let noop = SnapWindowPlacement.apply(target, read: { target },
            setSize: { _ in writes += 1; return .accepted }, setPosition: { _ in writes += 1; return .accepted },
            shouldContinue: { true }, pause: { _ in })
        try check(noop == .applied && writes == 0, "An already arranged window was written again")
        actual = start; writes = 0; pauses = 0
        let constrained = SnapWindowPlacement.apply(target, minimumSize: CGSize(width: 1000, height: 200), read: { actual },
            setSize: { actual.size = CGSize(width: max(1000, $0.width), height: $0.height); writes += 1; return .accepted },
            setPosition: { actual.origin = $0; writes += 1; return .accepted }, shouldContinue: { true }, pause: { _ in pauses += 1 })
        try check(constrained == .sizeLimited && writes <= 12, "Minimum-size refusal reported success or retried indefinitely")
        writes = 0
        let cancelled = SnapWindowPlacement.apply(target, read: { start },
            setSize: { _ in writes += 1; return .accepted }, setPosition: { _ in writes += 1; return .accepted },
            shouldContinue: { false }, pause: { _ in })
        try check(cancelled == .cancelled && writes == 0, "Cancelled snap wrote to a window")
        var keepGoing = true
        let interrupted = SnapWindowPlacement.apply(target, read: { start },
            setSize: { _ in writes += 1; return .accepted }, setPosition: { _ in writes += 1; return .accepted },
            shouldContinue: { keepGoing }, pause: { _ in keepGoing = false })
        try check(interrupted == .cancelled && writes == 1, "New drag or request failed to stop pending retries")
        try check(SnapWindowPlacement.matches(target.offsetBy(dx: 1, dy: 1), target), "Rounding tolerance too strict")
        try check(!SnapWindowPlacement.matches(target.offsetBy(dx: 10, dy: 0), target), "Incorrect frame accepted")
        try check(!SnapWindowPlacement.matches(nil, target), "Missing AX readback reported success")
        print("PASS: drag reset recovery, minimum sizes, no-op and cancelled/replaced placement")
    }

    static func asynchronousPlacement() throws {
        // Model an application that snapshots the other coordinate when an AX
        // write arrives, then commits the complete frame asynchronously. Sending
        // size/position back-to-back overwrites the pending resize with stale size.
        for target in [CGRect(x: 0, y: 38, width: 756, height: 900),
                       CGRect(x: 756, y: 38, width: 756, height: 900)] {
            var actual = CGRect(x: 140, y: 100, width: 1100, height: 700)
            var now = 0.0, writes = 0
            var pending: (time: Double, frame: CGRect)?
            let result = SnapWindowPlacement.apply(target, read: { actual },
                setSize: { size in
                    writes += 1
                    pending = (now + 0.16, CGRect(origin: actual.origin, size: size))
                    return .accepted
                },
                setPosition: { point in
                    writes += 1
                    pending = (now + 0.16, CGRect(origin: point, size: actual.size))
                    return .accepted
                }, shouldContinue: { true }, pause: { interval in
                    now += interval
                    if let update = pending, now >= update.time {
                        actual = update.frame
                        pending = nil
                    }
                })
            try check(result == .applied && SnapWindowPlacement.matches(actual, target), "Async half-screen writes clobbered each other")
            try check(writes <= 12 && now < 3, "Async placement exceeded retry/time bounds")
        }

        let target = CGRect(x: 0, y: 38, width: 756, height: 900)
        let start = CGRect(x: 140, y: 100, width: 1100, height: 700)
        for (status, expected) in [(SnapWindowPlacement.WriteResult.denied, SnapWindowPlacement.Result.permissionDenied),
                                   (.unavailable, .windowUnavailable), (.unsupported, .notSettable)] {
            var writes = 0
            let result = SnapWindowPlacement.apply(target, read: { start },
                setSize: { _ in writes += 1; return status },
                setPosition: { _ in writes += 1; return .accepted },
                shouldContinue: { true }, pause: { _ in })
            try check(result == expected && writes == 1, "Permanent AX error retried or mislabeled as minimum size")
        }
        var actual = start, sizeAttempts = 0
        let recovered = SnapWindowPlacement.apply(target, read: { actual },
            setSize: { size in
                sizeAttempts += 1
                if sizeAttempts == 1 { return .busy }
                actual.size = size
                return .accepted
            }, setPosition: { actual.origin = $0; return .accepted },
            shouldContinue: { true }, pause: { _ in })
        try check(recovered == .applied, "Busy AX call did not recover")
        var writes = 0
        let ignored = SnapWindowPlacement.apply(target, read: { start },
            setSize: { _ in writes += 1; return .accepted },
            setPosition: { _ in writes += 1; return .accepted },
            shouldContinue: { true }, pause: { _ in })
        try check(ignored == .failed && writes <= 12, "Ignored AX writes reported success or minimum-size restriction")
        print("PASS: asynchronous left/right halves, transient busy recovery, permanent errors and ignored writes")
    }

    static func compatibility() throws {
        for original: Bool? in [true, false, nil] {
            for assistiveActive in [true, false] {
                for outcome in [SnapWindowPlacement.Result.applied, .cancelled, .failed] {
                    var state = original
                    var writes: [Bool] = []
                    let result = SnapResizeCompatibility.perform(
                        assistiveTechnologyActive: assistiveActive,
                        readEnhancedUI: { state },
                        writeEnhancedUI: { writes.append($0); state = $0; return true }
                    ) { wasEnabled in
                        precondition(wasEnabled == (original == true))
                        return outcome
                    }
                    try check(result == outcome && state == original, "Enhanced UI state not restored on exit")
                    try check(writes == (original == true && !assistiveActive ? [false, true] : []), "Assistive technology or unknown Enhanced UI state changed")
                }
            }
        }
        var writes: [Bool] = []
        _ = SnapResizeCompatibility.perform(assistiveTechnologyActive: false,
            readEnhancedUI: { true }, writeEnhancedUI: { writes.append($0); return false },
            operation: { _ in SnapWindowPlacement.Result.failed })
        try check(writes == [false], "Restored state even though the compatibility write failed")
        print("PASS: scoped Enhanced UI compatibility, cancellation/failure restore and assistive-technology preservation")
    }

    @MainActor static func dragState() throws {
        // One uninterrupted main-actor turn: the real polling timer cannot fire.
        let state = WindowDragState.shared
        let first = SnapWindowTarget(id: 1), second = SnapWindowTarget(id: 2)
        state.beginDrag(target: first, bypassModifierIsPressed: false)
        state.recordDraggedWindowIfNeeded(second)
        try check(state.snapTarget == first, "Later notifications replaced the actual dragged window")
        state.endDrag()
        state.endDrag()
        try check(state.snapTarget == first && !state.shouldIgnoreSnapRelease, "Mouse-up cleared identity before drop handling")
        state.beginDrag(target: second, bypassModifierIsPressed: false)
        state.dismissSnapZonesForCurrentDrag()
        state.endDrag()
        try check(state.shouldIgnoreSnapRelease, "Escape cancellation lost at mouse-up")
        state.beginDrag(bypassModifierIsPressed: true)
        try check(state.snapTarget == nil, "New drag reused an old window")
        state.recordDraggedWindowIfNeeded(first)
        state.endDrag()
        try check(state.snapTarget == first && state.shouldIgnoreSnapRelease, "Command cancellation or late identity lost at mouse-up")
        state.beginDrag(bypassModifierIsPressed: false)
        state.endDrag()
        try check(!state.shouldIgnoreSnapRelease, "Previous cancellation blocked the next drag")
        print("PASS: stable window identity and Command/Escape cancellation across release ordering")
    }
}
