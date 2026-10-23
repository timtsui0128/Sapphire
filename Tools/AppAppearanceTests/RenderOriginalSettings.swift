import AppKit
import SwiftUI

@main
struct RenderOriginalSettings {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let session = SettingsEditingSession()
        let layout = SnapLayout(name: "Two columns", zones: [
            SnapZone(x: 0.02, y: 0.03, width: 0.47, height: 0.94),
            SnapZone(x: 0.51, y: 0.03, width: 0.47, height: 0.94)
        ])
        try await render(IconPickerView(onSelect: { _ in }), name: "icon-picker",
                         size: CGSize(width: 350, height: 700), session: session, output: output)
        try await render(NearbyShareSettingsView(), name: "nearby-share",
                         size: CGSize(width: 650, height: 900), session: session, output: output)
        try await render(BluetoothSettingsView(), name: "bluetooth",
                         size: CGSize(width: 650, height: 650), session: session, output: output)
        try await render(LayoutEditorView(layout: .constant(layout), onSave: { _ in }), name: "snap-layout",
                         size: CGSize(width: 650, height: 550), session: session, output: output)
    }

    @MainActor private static func render<Content: View>(
        _ content: Content, name: String, size: CGSize,
        session: SettingsEditingSession, output: URL
    ) async throws {
        let content = content
            .environmentObject(session)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .appAppearance()
        let host = NSHostingView(rootView: content)
        let frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: AppAppearance.shared.resolvedColorScheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = frame
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "OriginalSettingsRender", code: 1)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let path = output.appendingPathComponent("original-\(name)-\(AppAppearance.shared.mode.rawValue).png")
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "OriginalSettingsRender", code: 2)
        }
        try png.write(to: path)
        print("Rendered \(path.lastPathComponent)")
        window.close()
    }
}
