import AppKit
import SwiftUI

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

// Minimal dependency types for the unmodified production surface resolver.
enum LiquidGlassBackend { case automatic, visualEffect }
enum LiquidGlassMaterial { case frosted, hud, menu }
enum LiquidGlassBlendingMode { case behindWindow }
enum LiquidGlassAppearance { case dark, light, auto }
enum LiquidGlassInteraction { case normal }
struct LiquidGlassShadow: Equatable {
    var color: NSColor
    var opacity: Double
    var radius: CGFloat
    var offset: CGSize
}
struct FixtureGlassOptions {
    var material: LiquidGlassMaterial = .frosted
    var tintColor: NSColor? = nil
    var appearance: LiquidGlassAppearance = .dark
    var interaction: LiquidGlassInteraction = .normal
}
struct FixtureColor {
    var color: Color = .black
    var location: Double = 0
}
struct NotchAppearanceSettings {
    enum Mode { case standard, custom, liquidGlass, blur }
    enum Background { case solid, gradient, radial }
    var mode: Mode = .standard
    var backgroundStyle: Background = .solid
    var opacity: Double = 1
    var solidColor = FixtureColor()
    var gradientColors: [FixtureColor] = []
    var gradientAngle: Double = 90
    var usesLiquidGlass = false
    var enableTransparencyBlur = false
    var liquidGlassOptions = FixtureGlassOptions()
    var liquidGlassStyle: LiquidGlassMaterial = .frosted
}
struct ResolvedNotchConfiguration {
    var expandedShadowRadius: CGFloat = 20
    var expandedShadowOffsetY: CGFloat = 8
    var expandedShadowColor: Color = .black
    var isFloatingIsland = false
    var usesExternalDisplayBar = false
    var initialSize = CGSize(width: 180, height: 32)
    var restingShadowOpacity: Double = 0
    var restingShadowRadius: CGFloat = 12
    var restingShadowOffsetY: CGFloat = 6
}
enum NotchController {
    enum NotchState { case initial, hoverExpanded, autoExpanded, clickExpanded }
}
enum NotchLayerSurfaceView {
    struct Shadow: Equatable {
        var color: NSColor
        var opacity: Double
        var radius: CGFloat
        var offset: CGSize
        static let none = Shadow(color: .clear, opacity: 0, radius: 0, offset: .zero)
    }
}
enum NotchIslandBar {
    static let height: CGFloat = 38
    static let itemWidth: CGFloat = 36
}
enum NotchConfiguration {
    static let batteryTextFontSize: CGFloat = 12
    static let batteryIconSize: CGFloat = 22
    static let batteryValueFontSize: CGFloat = 7
    static let batteryBoltIconSize: CGFloat = 6
    static let batteryIconPadding: CGFloat = 2.7
    static let batteryHStackSpacing: CGFloat = 6
    static let batteryTextTrailingPadding: CGFloat = 2
    static let batteryFrameWidth: CGFloat = 22
    static let batteryFrameHeight: CGFloat = 10
}
private struct NotchBandHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
extension EnvironmentValues {
    var notchBandHeight: CGFloat {
        get { self[NotchBandHeightKey.self] }
        set { self[NotchBandHeightKey.self] = newValue }
    }
}
