import AppKit
import SwiftUI

// Only the progress-ring convenience overload requires this manager type.
@MainActor final class FocusSessionManager {
    var isRunning = false
    var totalSeconds: Double = 0
    func progress(at date: Date) -> Double { 0 }
}

private final class NativeAppearanceDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    init() { super.init(suiteName: "SapphireNativeAppearanceChecks.\(UUID().uuidString)")! }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@main private struct NativeLayerChecks {
    @MainActor static func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
    }

    static func brightness(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB)!
        return (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let appearance = AppAppearance(defaults: NativeAppearanceDefaults())
        let root = VStack(spacing: 12) {
            Text("Native controls").font(.headline)
            LayerNumericText(text: "123.4", font: .monospacedDigitSystemFont(ofSize: 24, weight: .medium), color: .labelColor)
                .frame(height: 32)
            HStack(spacing: 20) {
                LayerProgressRing(motion: .init(progress: 0.7), lineWidth: 4, activeColor: .primary)
                LayerGradientProgressRing(motion: .init(progress: 0.7), lineWidth: 4, colors: [.primary])
                LayerProgressBar(motion: .init(progress: 0.7), colors: [.primary], trackColor: .primary.opacity(0.18))
                    .frame(width: 140)
            }
            .frame(height: 32)
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .frame(height: 8)
        }
        .padding(20)
        .frame(width: 340, height: 160)
        .background(Color(nsColor: .windowBackgroundColor))
        .appPanelAppearance(appearance)
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = window.contentLayoutRect
        defer { window.close() }

        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for mode in [AppAppearanceMode.light, .dark, .light] {
            appearance.mode = mode
            try await Task.sleep(for: .milliseconds(180))
            host.layoutSubtreeIfNeeded()
            let numbers = descendants(host, of: LayerNumericTextView.self)
            precondition(numbers.count == 1)
            let number = numbers[0]
            let isDark = number.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            precondition(isDark == (mode == .dark), "Native number inherited the dark notch host")
            let textLayer = number.layer!.sublayers!.compactMap { $0 as? CATextLayer }.first!
            let attributed = textLayer.string as! NSAttributedString
            let numberColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
            precondition(mode == .dark ? brightness(numberColor) > 0.7 : brightness(numberColor) < 0.3,
                         "Unchanged native digits kept their previous appearance")
            let rings: [NSView] = descendants(host, of: LayerProgressRingView.self)
                + descendants(host, of: LayerGradientProgressRingView.self)
                + descendants(host, of: LayerProgressBarView.self)
            precondition(rings.count == 3)
            for ring in rings {
                precondition((ring.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) == (mode == .dark))
            }
            let materials = descendants(host, of: NSVisualEffectView.self)
            precondition(materials.count == 1)
            precondition((materials[0].effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) == (mode == .dark),
                         "The original native blur ignored the expanded panel appearance")
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("native-controls-\(mode.rawValue).png"))
        }
        print("PASS: expanded content overrides a dark host; unchanged native digits, progress views and native blur follow Light → Dark → Light")

        let glass = LiquidGlassHostView(frame: window.contentLayoutRect, backend: .automatic)
        window.contentView = glass
        for tone: LiquidGlassAppearance in [.light, .dark] {
            glass.configure(material: .clearGlass, cornerRadius: 0, tintColor: nil,
                            blendingMode: .behindWindow, appearance: tone,
                            interaction: .normal, contentLensing: nil, scrim: nil, subdued: nil)
            glass.setShapePath(CGPath(roundedRect: glass.bounds, cornerWidth: 24, cornerHeight: 24, transform: nil))
            precondition(!window.isOpaque && window.backgroundColor == .clear,
                         "An opaque backing window would cover the desktop behind the glass")
            if #available(macOS 26.0, *) {
                let native = descendants(glass, of: NSGlassEffectView.self).first!
                precondition(native.style == .clear, "The renderer must install Clear Glass instead of regular tinted glass")
                precondition((native.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) == (tone == .dark))
            }
        }
        glass.setBackend(.visualEffect)
        glass.configure(material: .hud, cornerRadius: 0, tintColor: nil,
                        blendingMode: .behindWindow, appearance: .light,
                        interaction: .normal, contentLensing: nil, scrim: nil, subdued: nil)
        let fallback = descendants(glass, of: NSVisualEffectView.self).first!
        precondition(fallback.material == .hudWindow && fallback.blendingMode == .behindWindow)
        print("PASS: real AppKit Clear Glass respects light/dark tone, keeps the backing window transparent, and falls back to behind-window blur")
    }
}
