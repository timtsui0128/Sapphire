import AppKit

// Keep external event registration inert. The real hover monitor, probe window
// run against this process's own offscreen NSWindow only.
@MainActor final class EventMonitorHub {
    static let shared = EventMonitorHub()
    func register(for type: NSEvent.EventType, handler: @escaping (NSEvent) -> Void) -> UUID { UUID() }
    func unregister(token: UUID, for type: NSEvent.EventType) {}
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func attachAuxiliaryNotchWindow(_ window: NSWindow) {}
    func detachAuxiliaryNotchWindow(_ window: NSWindow) {}
}

@main struct HandoffWindowChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let host = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 800, height: 300),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        let monitor = NotchHoverMonitor()
        let handlers = NotchHoverMonitorHandlers(onPointerEvent: {}, onMouseDrag: { _, _ in },
            onMouseDragEnded: { _ in }, onFileDrag: { _, _ in },
            onFileDragEnded: { _, _ in }, onFileDrop: { _, _, _ in false })
        let rect = CGRect(x: 250, y: 150, width: 300, height: 100)
        monitor.start(window: host, handlers: handlers)
        monitor.update(hoverRect: rect, pointerIsInside: false)
        precondition(monitor.isHoverProbeListeningForPointer)
        guard let probe = host.childWindows?.compactMap({ $0 as? HoverProbeWindow }).first else {
            fatalError("Missing production hover probe")
        }
        probe.setArmedForMouseSequence(true)
        precondition(!probe.ignoresMouseEvents)
        monitor.setSystemWindowDragSuppressed(true)
        precondition(!probe.isVisible && probe.ignoresMouseEvents && !probe.isArmedForMouseSequence)
        // SwiftUI can continue publishing animated geometry during collapse.
        monitor.update(hoverRect: rect.offsetBy(dx: 20, dy: 0), pointerIsInside: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.16))
        precondition(!probe.isVisible && !monitor.isHoverProbeListeningForPointer)
        monitor.setSystemWindowDragSuppressed(false)
        monitor.update(hoverRect: rect, pointerIsInside: false)
        precondition(monitor.isHoverProbeListeningForPointer)
        monitor.setSystemWindowDragSuppressed(true)
        monitor.stop()
        monitor.start(window: host, handlers: handlers)
        monitor.update(hoverRect: rect, pointerIsInside: false)
        precondition(monitor.isHoverProbeListeningForPointer, "Restart retained stale handoff state")
        monitor.stop()
        host.close()
        print("PASS: native hover probe disarms and parks during handoff, ignores stale geometry, resumes and restarts cleanly")
    }
}
