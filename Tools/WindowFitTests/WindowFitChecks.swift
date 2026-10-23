import AppKit
import SwiftUI

// The production geometry section is compiled verbatim; only unrelated app constants are fixtures.
enum NotchConfiguration {
    static let settingsWindowWidth: CGFloat = 950
    static let settingsWindowMinWidth: CGFloat = 800
    static let settingsWindowMinHeight: CGFloat = 520
    static let onboardingWindowWidth: CGFloat = 950
}

private enum FitError: Error { case failed(String) }
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw FitError.failed(message) }
}
private func contains(_ outer: NSRect, _ inner: NSRect) -> Bool {
    inner.minX >= outer.minX - 0.01 && inner.maxX <= outer.maxX + 0.01
        && inner.minY >= outer.minY - 0.01 && inner.maxY <= outer.maxY + 0.01
}

@main
struct WindowFitChecks {
    @MainActor static func main() async {
        do {
            try checkTopology()
            try checkGeometry()
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            try await checkNativeWindow(fullSizeContent: false)
            try await checkNativeWindow(fullSizeContent: true)
            print("PASS: all Settings window fit checks")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    static func checkTopology() throws {
        let builtIn = UtilityWindowMetrics.ScreenGeometry(
            displayID: 11, frame: NSRect(x: 0, y: 0, width: 1280, height: 800),
            visibleFrame: NSRect(x: 0, y: 48, width: 1280, height: 728)
        )
        let external = UtilityWindowMetrics.ScreenGeometry(
            displayID: 22, frame: NSRect(x: 1280, y: 0, width: 2560, height: 1440),
            visibleFrame: NSRect(x: 1280, y: 48, width: 2560, height: 1368)
        )
        let left = UtilityWindowMetrics.ScreenGeometry(
            displayID: 33, frame: NSRect(x: -1920, y: -200, width: 1920, height: 1080),
            visibleFrame: NSRect(x: -1850, y: -200, width: 1850, height: 1056)
        )
        let oldFrame = NSRect(x: 1460, y: 180, width: 1400, height: 1100)
        try require(UtilityWindowMetrics.targetVisibleFrame(for: oldFrame, preferredDisplayID: 22, screens: [builtIn, external]) == external.visibleFrame,
                    "Existing external window selected the wrong connected display")
        try require(UtilityWindowMetrics.targetVisibleFrame(for: oldFrame, preferredDisplayID: 22, screens: [builtIn]) == builtIn.visibleFrame,
                    "A stale external display identity survived unplug")
        let mostlyExternal = NSRect(x: 1200, y: 200, width: 1200, height: 600)
        try require(UtilityWindowMetrics.targetVisibleFrame(for: mostlyExternal, preferredDisplayID: 11, screens: [builtIn, external]) == external.visibleFrame,
                    "Stale window.screen overrode the largest actual overlap")
        let disconnectedLeft = NSRect(x: -3500, y: 300, width: 900, height: 700)
        try require(UtilityWindowMetrics.targetVisibleFrame(for: disconnectedLeft, preferredDisplayID: 99, screens: [builtIn, left]) == left.visibleFrame,
                    "Offscreen rehoming ignored the nearest remaining display")
        try require(UtilityWindowMetrics.targetVisibleFrame(for: oldFrame, preferredDisplayID: 22, screens: []) == nil,
                    "No-display transition fabricated a destination")
        print("PASS: connected display identity, maximum overlap, unplug fallback and negative-origin selection")
    }

    static func checkGeometry() throws {
        let visible = NSRect(x: -1280, y: 48, width: 1280, height: 728)
        let unchanged = NSRect(x: -1100, y: 160, width: 900, height: 560)
        try require(UtilityWindowMetrics.fittedFrame(unchanged, minimumSize: NSSize(width: 800, height: 520), visibleFrame: visible) == unchanged,
                    "A window already fitting the screen moved or resized")
        let old = NSRect(x: 1500, y: 100, width: 1700, height: 1300)
        let fitted = UtilityWindowMetrics.fittedFrame(old, minimumSize: NSSize(width: 800, height: 520), visibleFrame: visible)
        try require(contains(visible, fitted), "External-sized window did not fit a negative-origin built-in frame")
        let tiny = NSRect(x: 70, y: 32, width: 640, height: 400)
        let reduced = UtilityWindowMetrics.fittedFrame(old, minimumSize: NSSize(width: 800, height: 520), visibleFrame: tiny)
        try require(reduced == tiny, "Nominal minimum size exceeded a smaller visible frame")
        let dockInset = NSRect(x: 88, y: 70, width: 1192, height: 706)
        let clipped = UtilityWindowMetrics.fittedFrame(NSRect(x: 0, y: 0, width: 950, height: 740), minimumSize: NSSize(width: 800, height: 520), visibleFrame: dockInset)
        try require(contains(dockInset, clipped), "Window overlaps the Dock or menu-bar exclusion")
        print("PASS: size caps, stable fitting frames, Dock/menu-bar bounds and screens below nominal minimum")
    }

    @MainActor static func checkNativeWindow(fullSizeContent: Bool) async throws {
        var style: NSWindow.StyleMask = [.titled, .resizable, .closable]
        if fullSizeContent { style.insert(.fullSizeContentView) }
        let window = NSWindow(contentRect: NSRect(x: 1500, y: 100, width: 1700, height: 1200),
                              styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: Text("Settings fixture with a deliberately oversized intrinsic request")
            .frame(minWidth: 1400, minHeight: 1200))
        // Matches the production Settings host: child intrinsic dimensions cannot grow the window.
        host.sizingOptions = []
        window.contentView = host
        window.minSize = NSSize(width: 1400, height: 1100)
        window.contentMinSize = NSSize(width: 1500, height: 1150)
        window.maxSize = NSSize(width: 3000, height: 2200)
        window.setFrame(NSRect(x: 1500, y: 100, width: 1700, height: 1250), display: false)
        let visible = NSRect(x: 0, y: 48, width: 1280, height: 728)
        UtilityWindowMetrics.constrain(window: window, minimumSize: NSSize(width: 800, height: 520), visibleFrame: visible)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try require(contains(visible, window.frame), "Native titled window overflowed after external-to-built-in fit: \(window.frame)")
        // Attaching NSHostingView can asynchronously reset its window's limits once.
        // Match AppDelegate's settled retry after Cocoa has finished attaching/relocating.
        UtilityWindowMetrics.constrain(window: window, minimumSize: NSSize(width: 800, height: 520), visibleFrame: visible)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try require(contains(visible, window.frame), "Hosting layout grew the window after settled refit")
        try require(window.minSize.width <= 800 && window.minSize.height <= 520, "Old frame minimum survived the shrink")
        try require(window.maxSize.width <= visible.width && window.maxSize.height <= visible.height, "Old maximum survived display switch: frame=\(window.frame), max=\(window.maxSize), contentMax=\(window.contentMaxSize), visible=\(visible)")
        try require(window.contentMinSize.width <= window.contentMaxSize.width && window.contentMinSize.height <= window.contentMaxSize.height,
                    "Content constraints became inconsistent")
        try require(!window.isVisible, "Refitting presented a hidden test window")
        let first = window.frame
        UtilityWindowMetrics.constrain(window: window, minimumSize: NSSize(width: 800, height: 520), visibleFrame: visible)
        try require(window.frame == first, "Settled retry moved an already fitted window")
        let small = NSRect(x: -720, y: 30, width: 640, height: 420)
        UtilityWindowMetrics.constrain(window: window, minimumSize: NSSize(width: 800, height: 520), visibleFrame: small)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try require(contains(small, window.frame), "Host intrinsic size overrode a small visibleFrame")
        UtilityWindowMetrics.constrain(window: window, minimumSize: NSSize(width: 800, height: 520), visibleFrame: small)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try require(contains(small, window.frame), "Small display frame changed after settled retry")
        try require(window.maxSize.width <= small.width && window.maxSize.height <= small.height,
                    "Small display maximum was not retained after settled retry")
        try require(window.minSize.width <= small.width && window.minSize.height <= small.height,
                    "Native minimum was not capped below 800×520")
        print("PASS: hidden native \(fullSizeContent ? "fullSizeContentView" : "titled") window fits after stale frame/content limits and oversized hosting content")
    }
}
