import AppKit

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
        print("PASS: snap geometry, verified placement/retry, cancellation and release identity")
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
            setSize: { actual.size = $0; writes += 1 },
            setPosition: { actual.origin = $0; writes += 1 }, shouldContinue: { true },
            pause: { _ in pauses += 1; if pauses == 1 { actual = start } })
        try check(recover == .applied && actual == target && pauses == 2, "Did not recover from source app's final drag reset")
        try check(writes == 8, "Retry count is unbounded or insufficient")
        writes = 0
        let noop = SnapWindowPlacement.apply(target, read: { target },
            setSize: { _ in writes += 1 }, setPosition: { _ in writes += 1 },
            shouldContinue: { true }, pause: { _ in })
        try check(noop == .applied && writes == 0, "An already arranged window was written again")
        actual = start; writes = 0; pauses = 0
        let constrained = SnapWindowPlacement.apply(target, read: { actual },
            setSize: { actual.size = CGSize(width: max(1000, $0.width), height: $0.height); writes += 1 },
            setPosition: { actual.origin = $0; writes += 1 }, shouldContinue: { true }, pause: { _ in pauses += 1 })
        try check(constrained == .failed && writes == 12 && pauses == 3, "Minimum-size refusal reported success or retried indefinitely")
        writes = 0
        let cancelled = SnapWindowPlacement.apply(target, read: { start },
            setSize: { _ in writes += 1 }, setPosition: { _ in writes += 1 },
            shouldContinue: { false }, pause: { _ in })
        try check(cancelled == .cancelled && writes == 0, "Cancelled snap wrote to a window")
        var keepGoing = true
        let interrupted = SnapWindowPlacement.apply(target, read: { start },
            setSize: { _ in writes += 1 }, setPosition: { _ in writes += 1 },
            shouldContinue: { keepGoing }, pause: { _ in keepGoing = false })
        try check(interrupted == .cancelled && writes == 4, "New drag or request failed to stop pending retries")
        try check(SnapWindowPlacement.matches(target.offsetBy(dx: 1, dy: 1), target), "Rounding tolerance too strict")
        try check(!SnapWindowPlacement.matches(target.offsetBy(dx: 10, dy: 0), target), "Incorrect frame accepted")
        try check(!SnapWindowPlacement.matches(nil, target), "Missing AX readback reported success")
        print("PASS: drag reset recovery, minimum sizes, no-op and cancelled/replaced placement")
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
