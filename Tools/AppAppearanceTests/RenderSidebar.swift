import AppKit
import SwiftUI

@main
private struct RenderSidebar {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = HStack(spacing: 0) {
            SettingsSidebarView(
                selectedSection: .constant(.appearance),
                showAccountPane: .constant(false),
                onQuit: {}
            )
            .frame(width: 250)
            Divider()
            VStack(alignment: .leading, spacing: 24) {
                Text("Appearance").font(.largeTitle.bold())
                AppAppearanceSettingsSection()
                InfoContainer(
                    text: "Settings descriptions and permission guidance stay readable in either appearance.",
                    iconName: "info.circle",
                    color: .blue
                )
                VStack(spacing: 0) {
                    IconToggleRow(systemImage: "camera", color: .blue, title: "Screenshot collection", isOn: .constant(true))
                    Divider()
                    HStack {
                        SettingsRowLabel(title: "Widget order", description: "Drag to reorder your widgets.")
                        Spacer()
                        ReorderHandle()
                    }.padding()
                }
                .modifier(SettingsContainerModifier())
                Spacer()
            }
            .padding(24)
        }
        .frame(width: 850, height: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .appAppearance()
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: AppAppearance.shared.resolvedColorScheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 850, height: 760)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "SidebarRender", code: 1)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let file = output.appendingPathComponent("settings-sidebar-\(AppAppearance.shared.mode.rawValue).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
        print("Rendered \(file.lastPathComponent)")
        window.close()
    }
}
