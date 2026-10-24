import AppKit
import SwiftUI

// The hosting container, NSViewRepresentable, controller input wiring,
// coordinator lookup, shape paths and native hit/down/up methods are production
// code. Rendering/animation/services are replaced by a static outline fixture.
@MainActor final class NotchMorphEngine {}
@MainActor final class NotchStageCoordinator: ObservableObject {
    let engine = NotchMorphEngine()
    private(set) weak var view: NotchStageView?
    func attach(_ view: NotchStageView) { self.view = view }
}
struct NotchStageContent {
    var size: CGSize
    var shape: CustomNotchShape
    var onTap: () -> Void
}
struct FixtureSurface { var shape: CustomNotchShape }
struct FixtureSatellites {
    func restingRects(outline: CGRect, values: NotchMorphValues) -> [CGRect] { [] }
}
final class NotchStageView: NSView {
    let band = NotchPassthroughView()
    var surfaceStyle: FixtureSurface?
    var presentedFrame: NotchMorphFrame?
    var presentedRect = CGRect.zero
    var onTap: (() -> Void)?
    var isTapCandidate = false
    let satelliteStage = FixtureSatellites()
    private var outlineSize = CGSize.zero
    override var isFlipped: Bool { true }

    init(engine: NotchMorphEngine) {
        super.init(frame: .zero)
        addSubview(band)
    }
    required init?(coder: NSCoder) { fatalError() }
    func apply(_ content: NotchStageContent) {
        surfaceStyle = FixtureSurface(shape: content.shape)
        outlineSize = content.size
        onTap = content.onTap
        presentedFrame = NotchMorphFrame(time: 0,
            values: NotchMorphValues(width: content.size.width, height: content.size.height, cornerRadius: content.shape.cornerRadius, bottomCornerRadius: content.shape.bottomCornerRadius), isMoving: false)
        updateGeometry()
    }
    override func layout() { super.layout(); updateGeometry() }
    override func resizeSubviews(withOldSize oldSize: NSSize) { super.resizeSubviews(withOldSize: oldSize); updateGeometry() }
    private func updateGeometry() {
        band.frame = NSRect(x: 0, y: 8, width: bounds.width, height: max(0, bounds.height - 8))
        presentedRect = NotchMorphGeometry.rect(size: outlineSize, canvasWidth: band.bounds.width)
    }
    func tearDown() {}
}
final class DynamicFocusWindow: NSPanel {
    lazy var mouseInputGate = NotchMouseInputGate(window: self)
}
@MainActor final class ClickControllerFixture {
    let stage: NotchStageCoordinator
    weak var window: NSWindow?
    init(stage: NotchStageCoordinator, window: NSWindow) { self.stage = stage; self.window = window }
}
private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "ClickRoutingChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
@main private struct ClickRoutingChecks {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var deliveries = 0
        for kind in 0..<4 {
            for hostSize in [CGSize(width: 420, height: 150), CGSize(width: 1100, height: 600)] {
                let coordinator = NotchStageCoordinator()
                let window = DynamicFocusWindow(contentRect: NSRect(origin: .zero, size: hostSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                var shape = CustomNotchShape(cornerRadius: 12, bottomCornerRadius: 12)
                shape.isFloatingIsland = kind == 1
                shape.isNotchless = kind == 2
                shape.isExternalIndicator = kind == 3
                let collapsed = CGSize(width: 180, height: 32)
                let expanded = CGSize(width: 360, height: 110)
                var taps = 0
                let content = NotchStageContent(size: collapsed, shape: shape) { taps += 1 }
                let root = NotchStage(coordinator: coordinator, content: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                let host = NSHostingView(rootView: root)
                host.sizingOptions = []
                // Match the real hierarchy: window -> native container -> SwiftUI
                // hosting view -> representable -> native stage.
                let container = NotchStageContainerView(frame: NSRect(origin: .zero, size: hostSize), stageView: host, stageSize: CGSize(width: 1440, height: 650))
                window.contentView = container
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                guard let stage = coordinator.view else { throw NSError(domain: "No mounted native stage", code: 2) }
                try check(stage.window === window, "Representable must mount the real native stage in the fixture window")
                try check(!(container.stageView is NotchStageView), "Immediate stageView child must be a hosting view, reproducing the old cast failure")
                let controller = ClickControllerFixture(stage: coordinator, window: window)
                controller.connectInput()
                let point = stage.convert(NSPoint(x: stage.bounds.midX, y: 24), to: nil)
                // The previous callback cannot find the stage in this hierarchy.
                let legacyContains = (container.stageView as? NotchStageView)
                    .map { $0.stagePointIsInsideInteractiveRegion($0.convert(point, from: nil)) } ?? false
                try check(!legacyContains, "Negative control must reproduce the unclickable previous build")
                try check(coordinator.containsMousePoint(point, in: window), "Coordinator must resolve the native stage behind the hosting view")
                for cycle in 0..<10 {
                    stage.apply(content)
                    let edgeOffsets: [CGFloat] = [0, 0.5, 4, 24, 30]
                    let clickPoint = kind == 3
                        ? stage.convert(NSPoint(x: stage.bounds.midX, y: edgeOffsets[cycle % edgeOffsets.count]), to: nil) : point
                    if kind == 3 && cycle % edgeOffsets.count < 2 {
                        try check(abs(clickPoint.y - (hostSize.height - edgeOffsets[cycle % edgeOffsets.count])) < 0.01, "Edge taps must be at the actual native window top, not merely the top of the inset band")
                    }
                    window.setMouseEventHandlingEnabled(true)
                    window.mouseInputGate.refresh(pointer: clickPoint, pressedButtons: 0)
                    try check(!window.ignoresMouseEvents, "Collapsed notch must accept input through the real controller callback")
                    let hitPoint = stage.superview!.convert(clickPoint, from: nil)
                    guard let target = stage.hitTest(hitPoint) else { throw NSError(domain: "Collapsed notch rejected hit", code: 3) }
                    if kind == 3 {
                        try check(container.hitTest(clickPoint) === stage, "Top-edge clicks must traverse the real container and hosting view to reach the native stage")
                    }
                    func event(_ type: NSEvent.EventType) -> NSEvent {
                        NSEvent.mouseEvent(with: type, location: clickPoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: cycle, clickCount: 1, pressure: 1)!
                    }
                    target.mouseDown(with: event(.leftMouseDown))
                    target.mouseUp(with: event(.leftMouseUp))
                    try check(taps == cycle + 1, "Native down/up must deliver exactly one expansion tap")
                    deliveries += 1
                    if kind == 3 {
                        let paddingPoint = stage.convert(NSPoint(x: stage.bounds.midX, y: 30), to: nil)
                        try check(coordinator.containsMousePoint(paddingPoint, in: window), "The 4pt handle must retain a usable padded click target")
                        let oldCapsuleEdge = stage.convert(NSPoint(x: stage.bounds.midX + 60, y: 0.5), to: nil)
                        window.mouseInputGate.refresh(pointer: oldCapsuleEdge, pressedButtons: 0)
                        try check(window.ignoresMouseEvents, "Neighboring menu items outside the narrow activation corridor must keep their clicks")
                        let line = shape.externalIndicatorRect(in: CGRect(origin: .zero, size: collapsed))
                        try check(line.height == 4 && line.width == 80, "Idle artwork must be a thin 80×4 handle, not a shrunken black capsule")
                    }
                    var expandedShape = shape
                    expandedShape.isExternalIndicator = false
                    if kind == 3 {
                        expandedShape.cornerRadius = 40
                        expandedShape.bottomCornerRadius = 40
                        let contour = expandedShape.path(in: CGRect(origin: .zero, size: expanded))
                        try check(contour.contains(CGPoint(x: 10, y: 0.25)), "Expanded external panels must retain the original outward top shoulder")
                        try check(!contour.contains(CGPoint(x: 1, y: 20)), "The side must curve inward below the screen edge")
                        try check(expandedShape.shoulderInset(in: CGRect(origin: .zero, size: expanded)) == 35, "External top shoulders must match the original 40pt expanded notch contour")
                    }
                    stage.apply(NotchStageContent(size: expanded, shape: expandedShape, onTap: content.onTap))
                    let detailPoint = stage.convert(NSPoint(x: stage.bounds.midX + 100, y: 75), to: nil)
                    window.mouseInputGate.refresh(pointer: detailPoint, pressedButtons: 0)
                    try check(!window.ignoresMouseEvents, "Expanded content must still accept input")
                    let outside = stage.convert(NSPoint(x: stage.bounds.midX + 300, y: 200), to: nil)
                    window.mouseInputGate.refresh(pointer: outside, pressedButtons: 0)
                    try check(window.ignoresMouseEvents, "Transparent host margins must continue to pass clicks")
                }
                // A newly mounted representable must be found without reinstalling
                // the callback or depending on a fixed subview hierarchy.
                host.rootView = NotchStage(coordinator: coordinator, content: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
                try check(coordinator.containsMousePoint(point, in: window), "A mounted view update must preserve click routing")
                window.setMouseEventHandlingEnabled(false)
                window.close()
            }
        }
        print("PASS: legacy hosting-view cast reproduces blocked input in all 8 native hierarchies")
        print("PASS: collapsed notch native clicks expand (\(deliveries) tap deliveries); hardware/floating/notchless/external-handle layouts, large-stage/fitted-window coordinates, expanded content and transparent margins")
        print("PASS: external handle top-edge/corridor taps cross an 8pt band inset; neighboring menu items pass through; original expanded top shoulders restored")
        if let destination = CommandLine.arguments.dropFirst().first {
            let shape = CustomNotchShape(cornerRadius: 40, bottomCornerRadius: 40)
            let preview = VStack(alignment: .leading, spacing: 12) {
                Text("Attached top shoulders · production contour")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black)
                ZStack(alignment: .top) {
                    Color(red: 0.72, green: 0.88, blue: 0.93)
                    shape.fill(.black).frame(width: 520, height: 160)
                    VStack(spacing: 24) {
                        HStack {
                            Image(systemName: "gearshape")
                            Image(systemName: "tray")
                            Spacer()
                            Image(systemName: "battery.75percent")
                            Image(systemName: "pin")
                        }
                        .font(.system(size: 14))
                        Text("Expanded panel").font(.system(size: 20, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 56)
                    .padding(.top, 12)
                }.frame(width: 520, height: 180)
            }.padding(20).background(.white)
            let renderer = ImageRenderer(content: preview)
            renderer.scale = 2
            guard let image = renderer.nsImage, let data = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
            else { throw NSError(domain: "ContourRender", code: 1) }
            let folder = URL(fileURLWithPath: destination)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("attached-contour.png"))
        }
        print("Only hidden fixture windows and direct responder events were used; no application launch, global event injection or preference changes.")
    }
}
