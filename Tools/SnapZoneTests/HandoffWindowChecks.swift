import AppKit
import Combine

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

@MainActor final class DragStateManager {
    static let shared = DragStateManager()
    var isDraggingFromShelf = false
}
@MainActor final class SettingsModel {
    struct Values { var snapActivationDelay = 0.08 }
    static let shared = SettingsModel()
    var current = Values()
}

@MainActor final class SessionPrivacyState: ObservableObject {
    static let shared = SessionPrivacyState()
    @Published var isSuppressed = false
    static func shouldSuppressUI() -> Bool { shared.isSuppressed }
}
enum L10n {
    static var localize: (String) -> String = { $0 }
    static func string(_ key: String) -> String { localize(key) }
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
        silentWindowDragDelivery(host: host)
        visibleTarget(host: host)
        host.close()
        print("PASS: native hover probe disarms and parks during handoff, ignores stale geometry, resumes and restarts cleanly")
    }

    // A successfully installed global monitor is intentionally silent. Native
    // window moves must reach the inset dwell target without entering the probe
    // or receiving another AX moved notification.
    @MainActor static func silentWindowDragDelivery(host: NSWindow) {
        let screen = CGRect(x: -20400, y: -20500, width: 1600, height: 1100)
        var location = CGPoint(x: screen.midX, y: screen.midY)
        var pressed = true
        var installations = 0
        var removals = 0
        var callbacks = 0
        var releases = 0
        let manager = GlobalDragManager(isPrimaryButtonPressed: { pressed })
        manager.startMonitoring()
        let monitor = NotchHoverMonitor(
            mouseLocation: { location }, isPrimaryButtonPressed: { pressed },
            installGlobalDragMonitor: { _ in installations += 1; return NSObject() },
            removeGlobalDragMonitor: { _ in removals += 1 })
        let handlers = NotchHoverMonitorHandlers(onPointerEvent: {}, onMouseDrag: { _, point in
            callbacks += 1
            if SnapActivationRegion.isSystemTopEdge(point, in: screen) {
                manager.cancelActivation()
                monitor.setSystemWindowDragSuppressed(true)
            } else {
                manager.updateDrag(isInsideActivationZone: SnapActivationRegion.contains(point, in: screen),
                    canActivate: { SnapActivationRegion.contains(location, in: screen) })
            }
        }, onMouseDragEnded: { _ in releases += 1; manager.endDrag() }, onFileDrag: { _, _ in
            fatalError("A window move was routed to file sharing")
        }, onFileDragEnded: { _, _ in }, onFileDrop: { _, _, _ in false })
        monitor.start(window: host, handlers: handlers)
        let probeRect = CGRect(x: 250, y: 250, width: 300, height: 30)
        monitor.update(hoverRect: probeRect, pointerIsInside: false)
        let probe = host.childWindows!.compactMap { $0 as? HoverProbeWindow }.first!
        monitor.setExternalMouseDragActive(true)
        precondition(installations == 1)
        location = CGPoint(x: screen.midX, y: screen.maxY - 72)
        precondition(!probe.frame.contains(location), "Fixture must exercise entry outside the hover probe")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(manager.isDraggingInActivationZone,
                     "Silent event monitor lost inset activation after the first AX move")
        precondition(!probe.isArmedForMouseSequence, "Sampling must not capture mouse input")
        let stationaryCallbacks = callbacks
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(callbacks == stationaryCallbacks, "Stationary cursor was republished")

        // Releasing without any event must finish exactly once and stop sampling.
        pressed = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(releases == 1 && !manager.isDraggingInActivationZone)
        monitor.setExternalMouseDragActive(false)
        precondition(releases == 1 && removals == 1)
        let releasedCallbacks = callbacks
        location.y -= 150
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(callbacks == releasedCallbacks)

        // A quick pass cancels dwell; then entering the system edge parks input
        // and suppresses further callbacks even with the button still held.
        pressed = true
        monitor.setExternalMouseDragActive(true)
        location.y = screen.maxY - 72
        RunLoop.main.run(until: Date().addingTimeInterval(0.045))
        location.y -= 150
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        precondition(!manager.isDraggingInActivationZone)
        location.y = screen.maxY - 72
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(manager.isDraggingInActivationZone)
        location.y = screen.maxY
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        precondition(!manager.isDraggingInActivationZone && probe.ignoresMouseEvents && !probe.isVisible)
        let handedOffCallbacks = callbacks
        location.y -= 72
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(callbacks == handedOffCallbacks && !manager.isActivationPending)
        pressed = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(releases == 2, "Handoff must still clean up on release")
        monitor.setSystemWindowDragSuppressed(false)
        monitor.update(hoverRect: probeRect, pointerIsInside: false)
        pressed = true
        location.y -= 150
        monitor.setExternalMouseDragActive(true)
        location.y = screen.maxY - 72
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(manager.isDraggingInActivationZone, "The next drag must recover")
        monitor.stop()
        let stoppedCallbacks = callbacks
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(callbacks == stoppedCallbacks && installations == removals)
        manager.stopMonitoring()
        print("PASS: silent installed event monitor still supports inset dwell, release, system handoff and next-drag recovery without input capture")
    }


    @MainActor static func visibleTarget(host: NSWindow) {
        let hint = SnapActivationHint()
        let frame = CGRect(x: -20000, y: -20100, width: 320, height: 64)
        hint.show(frame: frame, isTargeted: false, relativeTo: host)
        guard let window = hint.window, let content = window.contentView as? SnapActivationHintView else {
            fatalError("Missing actual native snap target")
        }
        precondition(window.frame == frame && window.isVisible && window.ignoresMouseEvents)
        precondition(!window.canBecomeKey && !window.isKeyWindow && window.sharingType == .none)
        precondition(!content.isTargeted)
        hint.show(frame: frame, isTargeted: true, relativeTo: host)
        precondition(content.isTargeted && window.ignoresMouseEvents)
        SessionPrivacyState.shared.isSuppressed = true
        precondition(!window.isVisible, "Lock notification left the target visible")
        hint.show(frame: frame, isTargeted: true, relativeTo: host)
        precondition(!window.isVisible, "Locked session reopened the target")
        SessionPrivacyState.shared.isSuppressed = false
        hint.show(frame: frame, isTargeted: false, relativeTo: host)
        precondition(window.isVisible)
        hint.hide()
        precondition(!window.isVisible)

        if CommandLine.arguments.count > 2 {
            let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let catalog = try! JSONSerialization.jsonObject(with: Data(contentsOf:
                URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
            let strings = catalog["strings"] as! [String: [String: Any]]
            try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for language in ["en", "zh-Hans"] {
                L10n.localize = { key in
                    let locales = strings[key]!["localizations"] as! [String: [String: Any]]
                    return (locales[language]!["stringUnit"] as! [String: Any])["value"] as! String
                }
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    for targeted in [false, true] {
                        content.appearance = NSAppearance(named: appearance)
                        content.update(isTargeted: targeted)
                        content.layoutSubtreeIfNeeded()
                        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                        content.cacheDisplay(in: content.bounds, to: bitmap)
                        let name = "target-\(language)-\(appearance.rawValue)-\(targeted).png"
                        try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
                    }
                }
            }
            L10n.localize = { $0 }
        }
        content.appearance = NSAppearance(named: .darkAqua)
        content.update(isTargeted: true, reduceTransparency: true)
        if CommandLine.arguments.count > 1 {
            content.layoutSubtreeIfNeeded()
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("target-reduced-transparency.png"))
        }
        hint.stop()
        precondition(hint.window == nil)
        print("PASS: visible target matches its frame, highlights, never takes input/focus, hides on lock and cleans up")
    }

}
