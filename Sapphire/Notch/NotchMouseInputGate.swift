import AppKit

/// A transparent panel must never intercept clicks merely because it is pinned
/// or still using a large host frame from an earlier expansion.
@MainActor
final class NotchMouseInputGate {
    var containsPoint: ((NSPoint) -> Bool)?

    private weak var window: NSWindow?
    private var isEnabled = false
    private var capturedButtons = 0
    private var watchdog: Timer?

    init(window: NSWindow) { self.window = window }

    deinit { watchdog?.invalidate() }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { capturedButtons = 0 }
        refresh()
        if enabled, watchdog == nil {
            // Independent of SwiftUI hover delivery, including during tracking.
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            watchdog = timer
        } else if !enabled {
            watchdog?.invalidate()
            watchdog = nil
        }
    }

    func beginMouseSequence(_ event: NSEvent) {
        guard [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
              isEnabled, window?.ignoresMouseEvents == false,
              containsPoint?(event.locationInWindow) == true else { return }
        capturedButtons |= 1 << event.buttonNumber
    }

    func endMouseSequence(_ event: NSEvent) {
        guard [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type) else { return }
        capturedButtons &= ~(1 << event.buttonNumber)
        refresh()
    }

    func refresh(pointer: NSPoint? = nil, pressedButtons: Int? = nil) {
        guard let window else { return }
        capturedButtons &= pressedButtons ?? NSEvent.pressedMouseButtons
        let inside = containsPoint?(pointer ?? window.mouseLocationOutsideOfEventStream) == true
        let receivesMouse = isEnabled && (inside || capturedButtons != 0)
        if window.ignoresMouseEvents == receivesMouse {
            window.ignoresMouseEvents = !receivesMouse
        }
    }
}
