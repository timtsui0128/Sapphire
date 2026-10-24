import AppKit
import Foundation
import SwiftUI

private final class AppearanceDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    init() { super.init(suiteName: "SapphireAppearanceChecks.\(UUID().uuidString)")! }
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@main
private struct CheckAppearance {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let defaults = AppearanceDefaults()
        let appearance = AppAppearance(defaults: defaults)
        precondition(appearance.mode == .system, "New installations should follow the system")
        precondition(appearance.expandedPanelSurface == .matchPanel, "Existing settings must default to one matching panel surface")
        for surface in ExpandedPanelSurface.allCases {
            appearance.expandedPanelSurface = surface
            precondition(AppAppearance(defaults: defaults).expandedPanelSurface == surface, "Panel surface must persist")
        }
        appearance.expandedPanelSurface = .white
        appearance.mode = .dark
        precondition(appearance.expandedPanelColorScheme == .light && appearance.resolvedColorScheme == .dark, "White panel must use dark text without changing Settings theme")
        appearance.expandedPanelSurface = .black
        appearance.mode = .light
        precondition(appearance.expandedPanelColorScheme == .dark && appearance.resolvedColorScheme == .light, "Black panel must use light text without changing Settings theme")
        defaults.set("unknown-future-surface", forKey: AppAppearance.panelSurfaceDefaultsKey)
        precondition(AppAppearance(defaults: defaults).expandedPanelSurface == .matchPanel, "Invalid stored surface must fall back safely")
        appearance.expandedPanelSurface = .matchPanel
        precondition(appearance.panelColorScheme(matchingGlass: .dark) == .dark, "Per-display dark glass must retain readable light text")
        appearance.mode = .light
        precondition(AppAppearance(defaults: defaults).mode == .light, "Mode should persist")
        precondition(appearance.resolvedColorScheme == .light)
        appearance.mode = .dark
        precondition(appearance.resolvedColorScheme == .dark)
        appearance.mode = .system
        // Change only this invisible test process, never macOS preferences.
        let priorAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        try await Task.sleep(for: .milliseconds(60))
        precondition(appearance.resolvedColorScheme == .light)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try await Task.sleep(for: .milliseconds(60))
        precondition(appearance.resolvedColorScheme == .dark)
        NSApp.appearance = priorAppearance
        print("PASS: system default, persisted explicit modes, panel finish persistence/contrast, and live system-appearance observation")

        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-theme-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let screenshotDefaults = AppearanceDefaults()
        screenshotDefaults.set(false, forKey: "ScreenshotShelfCaptureEnabled")
        let manager = ScreenshotShelfManager(storageURL: temporary.appendingPathComponent("owned"), defaults: screenshotDefaults)
        var files: [URL] = []
        for number in 1...5 {
            let image = NSImage(size: NSSize(width: 320, height: 200))
            image.lockFocus()
            NSColor(calibratedHue: CGFloat(number) / 6, saturation: 0.3, brightness: 0.9, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 320, height: 200).fill()
            ("Screenshot \(number)" as NSString).draw(at: NSPoint(x: 30, y: 90), withAttributes: [
                .font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black
            ])
            image.unlockFocus()
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            let file = temporary.appendingPathComponent("Screenshot \(number).png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: file)
            files.append(file)
        }
        manager.importFiles(from: files)
        for _ in 0..<100 where manager.items.count != 5 {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(manager.items.count == 5)

        let root = VStack(spacing: 16) {
            AppAppearanceSettingsSection().padding(.horizontal, 12)
            ScreenshotShelfView(manager: manager)
                // Reproduce the surrounding notch's dark host override.
                .environment(\.colorScheme, .dark)
        }
        .padding(.vertical, 12)
        .frame(width: 680, height: 1000, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .appAppearance()
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 1000),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: AppAppearance.shared.resolvedColorScheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 680, height: 1000)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "AppearanceRender", code: 1)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let file = output.appendingPathComponent("screenshots-\(AppAppearance.shared.mode.rawValue).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
        print("Rendered \(file.lastPathComponent)")
        window.close()
        manager.captureTiming = .immediate
        let settings = ScreenshotShelfSettingsView(manager: manager)
            .frame(width: 460, height: 500, alignment: .top)
            .background(AppAppearance.shared.resolvedColorScheme == .dark ? Color.black : Color.white)
            .appAppearance()
        // Native pop-up buttons cannot be rendered with SwiftUI ImageRenderer.
        let settingsHost = NSHostingView(rootView: settings)
        let settingsFrame = NSRect(x: 0, y: 0, width: 460, height: 500)
        let settingsWindow = NSWindow(contentRect: settingsFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.appearance = NSAppearance(named: AppAppearance.shared.resolvedColorScheme == .dark ? .darkAqua : .aqua)
        settingsWindow.contentView = settingsHost
        settingsHost.frame = settingsFrame
        settingsHost.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        guard let settingsBitmap = settingsHost.bitmapImageRepForCachingDisplay(in: settingsHost.bounds) else {
            throw NSError(domain: "CaptureSettingsRender", code: 1)
        }
        settingsHost.cacheDisplay(in: settingsHost.bounds, to: settingsBitmap)
        try settingsBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("capture-settings-\(AppAppearance.shared.mode.rawValue).png"))
        settingsWindow.close()
    }
}
