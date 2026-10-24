import AppKit
import Foundation
import SwiftUI

private final class SurfaceDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    init() { super.init(suiteName: "SapphireSurfaceChecks.\(UUID().uuidString)")! }
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}
private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "SurfaceChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
private func brightness(_ color: NSColor) -> CGFloat {
    let rgb = color.usingColorSpace(.sRGB)!
    return (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3
}
private func contrast(_ first: NSColor, _ second: NSColor) -> CGFloat {
    func luminance(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB)!
        func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
    let values = [luminance(first), luminance(second)]
    return (values.max()! + 0.05) / (values.min()! + 0.05)
}
private struct PanelProbe: View {
    let appearance: AppAppearance
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.primary).frame(width: 24, height: 24).offset(x: 16, y: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text("Expanded panel").font(.headline)
                Text("Semantic text under a dark notch host").font(.caption).foregroundStyle(.secondary)
            }
            .offset(x: 56, y: 14)
            Rectangle().fill(.primary).frame(width: 24, height: 24)
                .appContentAppearance(appearance)
                .offset(x: 300, y: 16)
            HStack(spacing: 4) {
                NotchIslandBarButton(systemName: "house.fill", isSelected: true, help: "Home") {}
                NotchIslandBarButton(systemName: "gearshape.fill", isSelected: false, help: "Settings") {}
                NotchIslandBarButton(systemName: "pin.fill", isSelected: false, activeTint: .primary, help: "Pinned") {}
                NotchCapsuleIconLabel(systemName: "chevron.left")
                SubtleIconButton(systemName: "tray", action: {})
                BatteryInfoView(level: 74, isCharging: false, timeRemaining: "2h 45m")
            }
            .offset(x: 16, y: 70)
        }
        .frame(width: 340, height: 124, alignment: .topLeading)
    }
}

private struct ExternalHandlePreview: View {
    let input: NotchSurfaceStyle.Inputs
    let scheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scheme == .dark ? "External display · dark menu bar" : "External display · light menu bar")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            ZStack {
                Rectangle().fill(scheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
                HStack {
                    Text("Sapphire").fontWeight(.semibold)
                    Text("File    Edit    View")
                    Spacer()
                    Image(systemName: "wifi")
                    Text("17:14")
                }
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                if case .solid(let ink)? = NotchSurfaceStyle.resolve(input).fill {
                    input.shape.fill(Color(nsColor: ink)).frame(width: 96, height: 26)
                }
            }
            .frame(height: 28)
        }
        .environment(\.colorScheme, scheme)
    }
}
@main
private struct SurfaceStyleChecks {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var input = NotchSurfaceStyle.Inputs(
            appearance: NotchAppearanceSettings(), config: ResolvedNotchConfiguration(),
            shape: CustomNotchShape(cornerRadius: 0, bottomCornerRadius: 0), notchState: .clickExpanded,
            isGeminiActive: false, isManuallyHidden: false, surfaceShadowOpacity: 0.3,
            radialEndRadius: 0, systemGlassAvailable: true, expandedColorScheme: .light,
            surfaceHeight: 400
        )
        let physical = NotchSurfaceStyle.resolve(input)
        guard case let .solid(canvas)? = physical.fill else {
            throw NSError(domain: "SurfaceChecks", code: 2)
        }
        try check(brightness(canvas) > 0.8, "Expanded software top bar and body must be one light canvas")
        try check(physical.glass == nil && physical.fillShadow.opacity == 0.3, "Light expanded surface must retain shadow without dark glass")
        input.surfaceHeight = 200
        guard case let .solid(resized)? = NotchSurfaceStyle.resolve(input).fill else {
            throw NSError(domain: "SurfaceChecks", code: 3)
        }
        try check(brightness(resized) > 0.8, "A resize must not restore the software black stripe")
        print("PASS: expanded surface has a continuous light top bar and body, including after resizing")
        input.config.isFloatingIsland = true
        let floating = NotchSurfaceStyle.resolve(input)
        guard case let .solid(canvas)? = floating.fill else { throw NSError(domain: "SurfaceChecks", code: 4) }
        try check(brightness(canvas) > 0.8, "Floating expanded island must be all light")
        for finish in ExpandedPanelSurface.allCases {
            input.expandedPanelSurface = finish
            input.config.isFloatingIsland = false
            input.notchState = .clickExpanded
            for scheme: ColorScheme in [.light, .dark] {
                input.expandedColorScheme = finish.colorScheme(following: scheme)
                let style = NotchSurfaceStyle.resolve(input)
                if finish == .white || finish == .black {
                    guard case .solid(let color)? = style.fill else { throw NSError(domain: "SurfaceChecks", code: 8) }
                    try check(finish == .white ? brightness(color) > 0.99 : brightness(color) < 0.01, "Explicit surface must honor White/Black in both app themes")
                    try check(style.glass == nil, "Solid finish must not stack glass under its fill")
                }
                if finish == .liquidGlass {
                    try check(style.glass?.backend == .automatic && style.fill == nil, "Glass must use one continuous native surface without opaque paint")
                    try check(style.glass?.appearance == (scheme == .light ? .light : .dark), "Glass appearance must match semantic text")
                    input.systemGlassAvailable = false
                    try check(NotchSurfaceStyle.resolve(input).glass?.backend == .visualEffect, "Older macOS must use a native blur fallback")
                    input.systemGlassAvailable = true
                    input.reduceTransparency = true
                    let opaque = NotchSurfaceStyle.resolve(input)
                    try check(opaque.glass == nil && opaque.fill != nil, "Reduce Transparency must use an opaque surface")
                    if case .solid(let color)? = opaque.fill {
                        try check(scheme == .light ? brightness(color) > 0.8 : brightness(color) < 0.01, "Opaque accessibility fallback must retain the selected light/dark contrast")
                    }
                    input.reduceTransparency = false
                }
            }
        }
        input.expandedPanelSurface = .matchPanel
        input.expandedColorScheme = .light
        input.appearance.mode = .liquidGlass
        input.appearance.usesLiquidGlass = true
        input.appearance.liquidGlassOptions.appearance = .auto
        try check(NotchSurfaceStyle.resolve(input).glass?.appearance == .light, "Match Panel must honor expanded Liquid Glass even in Light mode")
        input.appearance = NotchAppearanceSettings()
        input.appearance.mode = .blur
        input.appearance.opacity = 0.5
        input.appearance.enableTransparencyBlur = true
        try check(NotchSurfaceStyle.resolve(input).glass?.appearance == .light, "Light blur must use a light material under dark text")
        input.appearance = NotchAppearanceSettings()
        print("PASS: all panel finishes, explicit light/dark contrast, native glass/fallback, accessibility and existing material selection")
        for floating in [false, true] {
            input.config.isFloatingIsland = floating
            for finish in ExpandedPanelSurface.allCases {
            input.expandedPanelSurface = finish
            for state: NotchController.NotchState in [.initial, .autoExpanded, .hoverExpanded] {
                input.notchState = state
                let style = NotchSurfaceStyle.resolve(input)
                switch style.fill {
                case .solid(let color): try check(brightness(color) < 0.01, "Collapsed/activity surface must remain black")
                case .linearGradient(let colors, _, _, _): try check(colors.allSatisfy { brightness($0) < 0.1 }, "Floating activity surface must remain dark")
                default: throw NSError(domain: "SurfaceChecks", code: 5)
                }
            }
            }
        }
        input.expandedPanelSurface = .matchPanel
        input.notchState = .clickExpanded
        input.expandedColorScheme = .dark
        input.config.isFloatingIsland = false
        guard case let .solid(dark)? = NotchSurfaceStyle.resolve(input).fill else { throw NSError(domain: "SurfaceChecks", code: 6) }
        try check(brightness(dark) < 0.01, "Dark expanded surface must preserve original black canvas")
        print("PASS: floating light expansion, dark expansion and unchanged collapsed/activity surfaces")
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let defaults = SurfaceDefaults()
        let appearance = AppAppearance(defaults: defaults)
        try check(appearance.externalDisplayStyle == .menuBarLine, "External screens must default to the menu bar line")
        for builtIn in [true, false] {
            for hardwareNotch in [true, false] {
                try check(ExternalDisplayStyle.menuBarLine.usesIndicator(isBuiltIn: builtIn, hasHardwareNotch: hardwareNotch) == (!builtIn && !hardwareNotch), "Only external displays without a hardware cutout use the line")
                try check(!ExternalDisplayStyle.original.usesIndicator(isBuiltIn: builtIn, hasHardwareNotch: hardwareNotch), "Original must restore legacy per-display styling")
            }
        }
        appearance.externalDisplayStyle = .original
        try check(AppAppearance(defaults: defaults).externalDisplayStyle == .original, "External style must survive relaunch")
        appearance.externalDisplayStyle = .menuBarLine
        try check(appearance.externalGlassTone == .automatic, "External glass must default to wallpaper matching")
        try check(ExternalGlassTone.automatic.resolve(wallpaperColor: .white, fallback: .dark) == .light, "A pale wallpaper must use light glass even with system Dark Mode")
        try check(ExternalGlassTone.automatic.resolve(wallpaperColor: .black, fallback: .light) == .dark, "A dark wallpaper must retain dark glass")
        try check(ExternalGlassTone.light.resolve(wallpaperColor: .black, fallback: .dark) == .light, "A manual Light Glass override must remain available for dynamic wallpapers")
        appearance.externalGlassTone = .light
        try check(AppAppearance(defaults: defaults).externalGlassTone == .light, "External glass tone must persist independently of app appearance")
        appearance.externalGlassTone = .automatic
        let wallpaperFolder = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-wallpaper-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: wallpaperFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: wallpaperFolder) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 120, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let black = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
        for y in 0..<120 {
            for x in 0..<160 { bitmap.setColor(y < 10 ? black : white, atX: x, y: y) }
        }
        let wallpaperURL = wallpaperFolder.appendingPathComponent("wide-screen-crop.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: wallpaperURL)
        let full = MenuBarWallpaperTint.sampleTopStrip(of: wallpaperURL, aspectRatio: 4.0 / 3.0)
        let wide = MenuBarWallpaperTint.sampleTopStrip(of: wallpaperURL, aspectRatio: 16.0 / 9.0)
        try check(ExternalGlassTone.automatic.resolve(wallpaperColor: full?.center, fallback: .light) == .dark, "Original image top edge should sample dark")
        try check(ExternalGlassTone.automatic.resolve(wallpaperColor: wide?.center, fallback: .dark) == .light, "External aspect-fill crop must sample its visible light top edge, not the hidden black pixels")
        print("PASS: per-display visible wallpaper crop and light menu material independent of system Dark Mode")
        var indicatorInput = input
        indicatorInput.isExternalIndicator = true
        indicatorInput.notchState = .initial
        indicatorInput.expandedPanelSurface = .black
        for scheme: ColorScheme in [.light, .dark] {
            indicatorInput.systemColorScheme = scheme
            let indicator = NotchSurfaceStyle.resolve(indicatorInput)
            guard case .solid(let ink)? = indicator.fill else { throw NSError(domain: "IndicatorInk", code: 1) }
            try check((brightness(ink) > 0.5) == (scheme == .dark), "Menu bar ink follows macOS even when the panel is forced black")
            try check(indicator.glass == nil && indicator.fillShadow.opacity == 0 && indicator.glows.isEmpty, "No capsule material, shadow or glow may remain behind the idle line")
        }
        print("PASS: automatic external-display policy, original-style persistence and independent system menu-bar ink")
        indicatorInput.isExternalIndicator = false
        indicatorInput.config.usesExternalDisplayBar = true
        indicatorInput.notchState = .autoExpanded
        indicatorInput.systemGlassAvailable = false
        let activity = NotchSurfaceStyle.resolve(indicatorInput)
        try check(activity.glass?.backend == .visualEffect && activity.glass?.appearance == .dark && activity.fill == nil, "External live activities use native blur on macOS 15 and retain readable white ink")
        indicatorInput.reduceTransparency = true
        try check(NotchSurfaceStyle.resolve(indicatorInput).glass == nil, "External live activities must respect Reduce Transparency")
        indicatorInput.notchState = .clickExpanded
        indicatorInput.expandedPanelSurface = .white
        guard case .solid(let expandedInk)? = NotchSurfaceStyle.resolve(indicatorInput).fill else { throw NSError(domain: "ExternalExpanded", code: 1) }
        try check(brightness(expandedInk) > 0.8, "External expanded panels must still honor the chosen panel surface")
        indicatorInput.expandedPanelSurface = .liquidGlass
        indicatorInput.expandedColorScheme = .light
        indicatorInput.reduceTransparency = false
        let externalGlass = NotchSurfaceStyle.resolve(indicatorInput)
        try check(externalGlass.glass?.material == .menu && externalGlass.glass?.appearance == .light, "External panels must use light native menu material when matching a pale menu bar")
        print("PASS: external live activity material, macOS 15 fallback, Reduce Transparency and expanded surface selection")
        var lightInput = indicatorInput
        lightInput.reduceTransparency = false
        lightInput.isExternalIndicator = true
        lightInput.notchState = .initial
        lightInput.systemColorScheme = .light
        lightInput.shape.isExternalIndicator = true
        lightInput.shape.isFloatingIsland = true
        var darkInput = lightInput
        darkInput.systemColorScheme = .dark
        for scale: CGFloat in [1, 1.5, 2] {
            var shape = lightInput.shape
            shape.externalIndicatorScale = scale
            let rect = shape.externalIndicatorRect(in: CGRect(x: 0.5, y: 0, width: 95, height: 27))
            try check(abs(rect.minY * scale - (rect.minY * scale).rounded()) < 0.001, "4pt artwork edges must align to pixels at each display scale")
            try check(shape.path(in: CGRect(x: 0.5, y: 0, width: 95, height: 27)).boundingRect.height == 4, "The production path must paint only the thin line")
        }
        let previewRoot = VStack(spacing: 24) {
            ExternalHandlePreview(input: lightInput, scheme: .light)
            ExternalHandlePreview(input: darkInput, scheme: .dark)
        }.padding(24).frame(width: 560, height: 200).background(Color(white: 0.5))
        let previewHost = NSHostingView(rootView: previewRoot)
        let previewFrame = NSRect(x: 0, y: 0, width: 560, height: 200)
        let previewWindow = NSWindow(contentRect: previewFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        previewWindow.isReleasedWhenClosed = false
        previewWindow.contentView = previewHost
        previewHost.frame = previewFrame
        previewHost.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        let previewBitmap = previewHost.bitmapImageRepForCachingDisplay(in: previewHost.bounds)!
        previewHost.cacheDisplay(in: previewHost.bounds, to: previewBitmap)
        try previewBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("external-menu-bar-preview.png"))
        previewWindow.close()
        for mode: AppAppearanceMode in [.light, .dark] {
            appearance.mode = mode
            for finish in ExpandedPanelSurface.allCases {
            appearance.expandedPanelSurface = finish
            let isLight = appearance.expandedPanelColorScheme == .light
            let backdrop = finish == .white ? NSColor.white : (isLight ? canvas : NSColor.black)
            let root = PanelProbe(appearance: appearance)
                .appPanelAppearance(appearance)
                .notchHostEnvironment(bandHeight: 32, displayScale: 1)
                .background(Color(nsColor: backdrop))
            let host = NSHostingView(rootView: root)
            let frame = NSRect(x: 0, y: 0, width: 340, height: 124)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.frame = frame
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "SurfaceChecks", code: 7) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            func sample(_ x: CGFloat, _ y: CGFloat) -> NSColor {
                bitmap.colorAt(x: Int(x * CGFloat(bitmap.pixelsWide) / frame.width), y: Int(y * CGFloat(bitmap.pixelsHigh) / frame.height))!
            }
            let probe = sample(24, 24)
            print("Contrast probe \(mode.rawValue)/\(finish.rawValue): \(brightness(probe)), expected \(isLight ? "dark" : "light") ink")
            // System primary ink is slightly translucent, so test its real contrast.
            try check(contrast(probe, backdrop) >= 7, "Panel primary ink must retain high contrast under the forced dark host: \(mode.rawValue)/\(finish.rawValue)")
            let cardProbe = sample(308, 24)
            try check(contrast(cardProbe, backdrop) >= 7, "Nested screenshot/sports/finance content must inherit the panel finish")
            let file = output.appendingPathComponent("expanded-panel-\(mode.rawValue)-\(finish.rawValue).png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: file)
            print("Rendered \(file.lastPathComponent)")
            if mode == .light && finish == .matchPanel {
                appearance.expandedPanelSurface = .black
                try await Task.sleep(for: .milliseconds(80))
                host.layoutSubtreeIfNeeded()
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try check(brightness(sample(24, 24)) > 0.8, "An already mounted panel must update immediately when surface changes")
                appearance.expandedPanelSurface = .white
                try await Task.sleep(for: .milliseconds(80))
                host.layoutSubtreeIfNeeded()
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try check(brightness(sample(24, 24)) < 0.4, "White must restore dark header text without reopening the panel")
            }
            window.close()
            }
        }
        for mode: AppAppearanceMode in [.light, .dark] {
            appearance.mode = mode
            appearance.expandedPanelSurface = .matchPanel
            let frame = NSRect(x: 0, y: 0, width: 560, height: 760)
            let root = AppAppearanceSettingsSection(appearance: appearance)
                .padding(16)
                .frame(width: frame.width, height: frame.height, alignment: .top)
                .background(mode == .light ? Color.white : Color.black)
                .appAppearance(appearance)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = frame
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "SurfaceChecks", code: 9) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("surface-settings-\(mode.rawValue).png"))
            window.close()
        }
        print("PASS: actual header/back/battery controls render for 8 theme/finish combinations; mounted panels update immediately")
        print("PASS: production controller, widget plane and floating chrome theme wiring verified")
    }
}
