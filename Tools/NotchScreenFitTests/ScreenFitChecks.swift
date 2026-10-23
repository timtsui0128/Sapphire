import AppKit
import SwiftUI

// Only external services are fixtures. The sizing, scrolling viewport, native
// stage, display refresh policy, and actual WeatherWidgetView compile verbatim.
extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
    }
}
class DynamicFocusWindow: NSWindow { var displayID: CGDirectDisplayID = 0 }
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func reassertNotchSpaceMembership(_ window: NSWindow) {}
}
@MainActor final class NotchMorphEngine {
    enum Event { case retarget }
    var endTime: CFTimeInterval? { nil }
    func addObserver(_ owner: AnyObject, handler: @escaping (Event) -> Void) {}
    func removeObserver(_ owner: AnyObject) {}
    func isAnimating(at: CFTimeInterval) -> Bool { false }
    func peakSize(from: CFTimeInterval) -> CGSize { .zero }
}
@MainActor final class WeatherViewModel: ObservableObject {
    static let shared = WeatherViewModel()
    let iconName = "icloud", temperature = "—°", locationName = "Unavailable"
    let conditionDescription = "Grant Location access in Sapphire’s Permissions settings to show weather."
    let windInfo = "— mph", precipChance = "—%", humidity = "—%"
}
enum Destination { case weatherPlayer }
struct NavigationKey: EnvironmentKey { static let defaultValue: Binding<[Destination]> = .constant([]) }
extension EnvironmentValues {
    var navigationStack: Binding<[Destination]> {
        get { self[NavigationKey.self] }
        set { self[NavigationKey.self] = newValue }
    }
}

private enum CheckError: Error { case failed(String) }
private func check(_ passes: @autoclosure () -> Bool, _ message: String) throws {
    if !passes() { throw CheckError.failed(message) }
}
@MainActor private final class PanelFixture: ObservableObject {
    @Published var maximumSize = CGSize(width: 3408, height: 700)
    @Published var extraWide = false
    var actualSize = CGSize.zero
    var reports = 0
    var overflowsHorizontally = false
}
private struct PhotoRow: View {
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Music").font(.headline)
                Text("A long music title from the screenshot").lineLimit(1)
                HStack(spacing: 20) { Image(systemName: "backward.end.fill"); Image(systemName: "play.fill"); Image(systemName: "forward.end.fill") }
            }.frame(width: 280)
            WeatherWidgetView()
            VStack(alignment: .leading) { Text("Formula 1").font(.caption); Text("MSC Cruises United States Grand Prix").font(.headline); Text("Lap —"); Text("Scheduled").foregroundStyle(.secondary) }.frame(width: 190)
            VStack(alignment: .leading) { Text("Stocks").font(.caption); Text("AAPL      348.22 USD"); Text("MSFT      521.08 USD"); Text("NVDA      212.21 USD") }.frame(width: 190)
            VStack { Text("Oct 21").font(.title2.bold()); Text("No more items today").foregroundStyle(.secondary) }.frame(width: 180)
        }.frame(height: 100)
    }
}
private struct PanelRoot: View {
    @ObservedObject var fixture: PanelFixture
    var body: some View {
        NotchPanelViewport(maximumSize: fixture.maximumSize, content:
            VStack(alignment: .leading, spacing: 10) {
                PhotoRow()
                if fixture.extraWide {
                    HStack { Text("First item"); Spacer(); Text("Last item remains reachable") }
                        .frame(width: 3600, height: 28)
                }
            },
            onHorizontalOverflow: { fixture.overflowsHorizontally = $0 }
        )
        .measureIdealSize(into: Binding(get: { fixture.actualSize }, set: {
            fixture.actualSize = $0
            fixture.reports += 1
        }))
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

@main private struct ScreenFitChecks {
    @MainActor static func main() async {
        do {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            try geometryChecks()
            try refreshChecks()
            try await panelChecks()
            print("PASS: all notch screen-fit checks")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor private static func geometryChecks() throws {
        for width: CGFloat in [960, 1280, 1512, 1920, 3440] {
            for scale: CGFloat in [1, 1.5, 2] {
                let screen = CGRect(x: -width, y: -100, width: width, height: 982)
                let visible = CGRect(x: -width, y: -40, width: width, height: 885)
                let maximum = NotchSizing.maximumExpandedSize(screenFrame: screen, visibleFrame: visible, topOffset: 0)
                let target = NotchSizing.fittedSize(CGSize(width: 4000, height: 1600), minimumSize: CGSize(width: 210, height: 32), maximumSize: maximum, scale: scale)
                try check(target.width <= width - 32 && target.height <= maximum.height, "Expanded outline exceeds current display")
                let extent = NotchHostWindowExtent(isFull: false, notchSize: CGSize(width: 4000, height: 1600), notchTopOffset: 0, collapsedHeight: 32, fullBandInset: 0)
                let frame = NotchHostWindowSizer.frame(for: extent, screenFrame: screen, visibleFrame: visible, scale: scale)
                try check(screen.insetBy(dx: -0.01, dy: -0.01).contains(frame), "Old external display extent escaped native bounds")
                let stage = NotchHostWindowSizer.stageSize(current: CGSize(width: width, height: 1600), extent: extent, windowSize: frame.size, screenFrame: screen, visibleFrame: visible, scale: scale)
                try check(stage.width <= width && stage.height <= screen.height, "Stage retained old display size")
            }
        }
        print("PASS: expanded outline/native window/stage bounded across 5 display widths, negative origins and 3 backing scales")
    }

    private static func refreshChecks() throws {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let first = NotchDisplayRefreshPolicy.Snapshot(displays: [.init(id: 11, frame: frame, visibleFrame: frame, scale: 2)], targets: [11])
        let dock = NotchDisplayRefreshPolicy.Snapshot(displays: [.init(id: 11, frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 30), scale: 2)], targets: [11])
        let scale = NotchDisplayRefreshPolicy.Snapshot(displays: [.init(id: 11, frame: frame, visibleFrame: frame, scale: 1)], targets: [11])
        try check(NotchDisplayRefreshPolicy.step(previous: first, current: dock, reads: 2) == .readAgain, "Dock change falsely treated as stable")
        try check(NotchDisplayRefreshPolicy.step(previous: first, current: scale, reads: 2) == .readAgain, "Backing-scale change falsely treated as stable")
        try check(NotchDisplayRefreshPolicy.step(previous: dock, current: dock, reads: 3) == .apply, "Stable geometry never applied")
        print("PASS: display stability includes work area and backing scale")
    }

    @MainActor private static func panelChecks() async throws {
        let weather = NSHostingView(rootView: WeatherWidgetView())
        try check(weather.fittingSize.width <= 260.5, "Photo's long weather permission message still widens its widget")
        let fixture = PanelFixture()
        let host = NSHostingView(rootView: PanelRoot(fixture: fixture))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 3440, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        for width: CGFloat in [3440, 1512, 1280, 960, 3440, 1280] {
            fixture.maximumSize = CGSize(width: width - 32, height: 400)
            window.setFrame(CGRect(x: 0, y: 0, width: width, height: 500), display: false)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(180))
            host.layoutSubtreeIfNeeded()
            try check(fixture.actualSize.width > 900 && fixture.actualSize.width <= width - 32 + 0.5,
                      "Actual photo row viewport exceeds \(width)-point display: \(fixture.actualSize)")
            try check(!window.isVisible, "Fixture window was shown")
            if width == 960 { try check(fixture.overflowsHorizontally, "Small-screen scroll navigation was not reserved for content") }
        }
        fixture.extraWide = true
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        host.layoutSubtreeIfNeeded()
        try check(fixture.actualSize.width <= 1248.5 && fixture.actualSize.height <= 400.5, "Oversized row escaped viewport")
        try check(fixture.overflowsHorizontally, "Wide content was not reported to the swipe-navigation guard")
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        guard let scroll = scrollViews(host).first(where: { ($0.documentView?.frame.width ?? 0) > 3500 }) else {
            throw CheckError.failed("Overflow has no horizontally scrollable document")
        }
        let rightEdge = max(0, scroll.documentView!.bounds.width - scroll.contentView.bounds.width)
        scroll.contentView.scroll(to: CGPoint(x: rightEdge, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        try check(scroll.contentView.bounds.minX > 2000, "Last widget cannot be reached by scrolling")
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("notch-overflow-scroll.png"))
        }
        fixture.extraWide = false
        try await Task.sleep(for: .milliseconds(180))
        host.layoutSubtreeIfNeeded()
        try check(!fixture.overflowsHorizontally, "Normal swipe navigation did not restore after overflow disappeared")
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("notch-photo-row-fit.png"))
        }
        try check(fixture.reports < 40, "Panel sizing oscillates instead of settling")
        print("PASS: actual weather error/photo row, persistent SwiftUI graph external→built-in→external, overflow last-item scroll access and stable size reports")
    }
}
