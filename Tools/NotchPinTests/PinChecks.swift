import AppKit
import SwiftUI

// Small dependencies; all controls, sizing policy and native input gate are production code.
struct ResolvedNotchConfiguration: Equatable {}
enum NotchWidgetMode { case defaultWidgets, fileShelfLanding, snapZones, dragActivated, fileShelf, fileActionPreview, notesPlayer, clipboardPlayer, focusSessionDetailView, multiAudio, continuityDetail, batteryDetailView, blipHub, agentS }
enum NotchController { enum NotchState { case clickExpanded } }
struct Settings {
    var notchButtonOrder = NotchButtonType.allCases
    var fileShelfIconEnabled = true, notesIconEnabled = true, clipboardIconEnabled = true
    var intelligenceEnabled = true, focusSessionIconEnabled = true, caffeinateEnabled = true
    var batteryEstimatorEnabled = true, continuityEnabled = true, continuityShowPhoneBattery = true
    var showMultiAudioIcon = true, pinEnabled = true
}
@MainActor private final class PinState: ObservableObject {
    @Published var pinned = false
    var callbacks = 0
}
private struct PinFixtureView: View {
    @ObservedObject var state: PinState
    let floating: Bool
    let scheme: ColorScheme
    var body: some View {
        NotchPinButton(isPinned: $state.pinned, isFloatingIsland: floating, onPin: { _ in state.callbacks += 1 })
            .frame(width: 100, height: 70)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
            .accentColor(.blue)
    }
}
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "PinChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
@main private struct PinChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        setbuf(stdout, nil)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 3000, height: 2000), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let gate = NotchMouseInputGate(window: window)
        let visible = NSRect(x: 1300, y: 1700, width: 400, height: 300)
        gate.containsPoint = { visible.contains($0) }
        gate.setEnabled(true)
        gate.refresh(pointer: NSPoint(x: 1500, y: 1800), pressedButtons: 0)
        try check(!window.ignoresMouseEvents, "Visible panel must remain clickable while pinned")
        for point in [NSPoint(x: 100, y: 100), NSPoint(x: 2900, y: 1900), NSPoint(x: 1299, y: 1800)] {
            gate.refresh(pointer: point, pressedButtons: 0)
            try check(window.ignoresMouseEvents, "Transparent host margins must pass clicks even with stale enabled/pinned state")
            gate.refresh(pointer: point, pressedButtons: 1)
            try check(window.ignoresMouseEvents, "A drag/click started in another app must never capture the panel")
        }
        gate.refresh(pointer: NSPoint(x: 1500, y: 1800), pressedButtons: 1)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 1500, y: 1800), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        gate.beginMouseSequence(down)
        gate.refresh(pointer: NSPoint(x: 100, y: 100), pressedButtons: 1)
        try check(!window.ignoresMouseEvents, "A panel-owned drag must retain its mouse-up outside the outline")
        gate.refresh(pointer: NSPoint(x: 100, y: 100), pressedButtons: 0)
        try check(window.ignoresMouseEvents, "A lost mouse-up must clear capture on the next native sample")
        // Exercise the independent timer against an intentionally stale hover state.
        gate.containsPoint = { _ in false }
        window.ignoresMouseEvents = false
        try await Task.sleep(for: .milliseconds(120))
        try check(window.ignoresMouseEvents, "Native watchdog must release input without a SwiftUI hover-exit event")
        gate.setEnabled(false)
        gate.containsPoint = { _ in true }
        gate.refresh(pointer: .zero, pressedButtons: 1)
        try check(window.ignoresMouseEvents, "Hidden/privacy-disabled panel must always release input")
        window.close()
        print("PASS: native panel input stays inside its visible region; external clicks/drags pass; owned drag and lost mouse-up recover")

        for width: CGFloat in [100, 160, 260, 420, 640] {
            let items = NotchIslandBar.items(settings: Settings(), navigationDepth: 3, maxWidth: width)
            try check(NotchIslandBar.width(of: items) <= width, "Toolbar must still fit narrow screens")
            try check(items.contains(.button(.pin)), "Pin must remain available as other buttons are dropped")
        }
        print("PASS: Unpin survives floating toolbar compression from 640 to 100 points")

        for floating in [false, true] {
            for scheme: ColorScheme in [.light, .dark] {
                let state = PinState()
                let binding = Binding(get: { state.pinned }, set: { state.pinned = $0 })
                var context = NotchExpandedChrome.Context(config: .init(), mode: .defaultWidgets, notchState: .clickExpanded, barWidth: 400, fixedSpacer: false, showRightHUDOverlay: false, navigationStack: .constant([.defaultWidgets]), isPinned: binding, iconsLeftWidth: .constant(0), iconsRightWidth: .constant(0), iconsIntrinsicWidth: 40, onPin: { _ in }, onOpenBlipHub: {}, onOpenAgentS: {})
                let cached = CachedHeader()
                let host = cached.hosting
                let frame = NSRect(x: 0, y: 0, width: 100, height: 70)
                let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.contentView = host
                host.frame = frame
                let control = NotchPinButton(isPinned: binding, isFloatingIsland: floating, onPin: { _ in state.callbacks += 1 })
                func root() -> AnyView {
                    AnyView(PinFixtureView(state: state, floating: floating, scheme: scheme))
                }
                cached.setRootView(root(), key: NotchExpandedChrome.key(context))
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(60))
                var pinnedPixels: Data?
                var pinnedAccentCount = 0
                for index in 0..<20 {
                    let oldKey = NotchExpandedChrome.key(context)
                    control.toggle()
                    try check(state.pinned == (index % 2 == 0), "Repeated pin/unpin must toggle reliably")
                    let nextKey = NotchExpandedChrome.key(context)
                    try check(oldKey != nextKey, "Pin must invalidate the actual cached native header key")
                    cached.setRootView(root(), key: nextKey)
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(25))
                    if index < 2 {
                        // The floating bar animates its selection over a spring.
                        try await Task.sleep(for: .milliseconds(450))
                        host.layoutSubtreeIfNeeded()
                        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "No pin render", code: 3) }
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let data = bitmap.representation(using: .png, properties: [:])!
                        let name = "pin-\(floating ? "island" : "attached")-\(scheme == .dark ? "dark" : "light")-\(state.pinned ? "on" : "off").png"
                        try data.write(to: output.appendingPathComponent(name))
                        var accentCount = 0
                        for y in 0..<bitmap.pixelsHigh {
                            for x in 0..<bitmap.pixelsWide {
                                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                                if color.blueComponent - color.redComponent > 0.25 && color.blueComponent - color.greenComponent > 0.1 { accentCount += 1 }
                            }
                        }
                        if state.pinned {
                            pinnedPixels = data
                            pinnedAccentCount = accentCount
                            try check(accentCount >= 8, "Pinned control must visibly light up in its accent color")
                        } else {
                            try check(pinnedPixels != data && accentCount < pinnedAccentCount / 2, "Unpin must visibly clear the selected accent")
                        }
                    }
                    // A mode change must retain the same binding so unpin still works in details.
                    context.mode = index > 10 ? .fileShelf : .defaultWidgets
                }
                try check(!state.pinned && state.callbacks == 20, "All control actions must reach the shared callback, including in detail mode")
                panel.close()
            }
        }
        print("PASS: 80 Pin actions across attached/floating and light/dark; native cached headers refresh, highlighted renders differ, every toggle can be cancelled")
    }
}
