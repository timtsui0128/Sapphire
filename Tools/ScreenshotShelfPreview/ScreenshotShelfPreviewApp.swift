import AppKit
import SwiftUI

/// A small host for the same screenshot feature embedded in Sapphire's file shelf.
/// It can be built without Sapphire's unrelated services and private extensions.
@main
struct ScreenshotShelfPreviewApp: App {
    @NSApplicationDelegateAdaptor(ScreenshotShelfPreviewDelegate.self) private var delegate

    var body: some Scene {
        Window("Sapphire Screenshots", id: "screenshots") {
            ScreenshotShelfView()
                .frame(width: 680)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.bottomTrailing)

        MenuBarExtra("Sapphire Screenshots", systemImage: "camera.viewfinder") {
            ScreenshotShelfMenu()
        }
    }
}

@MainActor
private final class ScreenshotShelfPreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ScreenshotShelfManager.shared.startMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScreenshotShelfManager.shared.stopMonitoring()
    }
}

private struct ScreenshotShelfMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var manager = ScreenshotShelfManager.shared

    var body: some View {
        Button("Open Screenshots (\(manager.items.count))") {
            openWindow(id: "screenshots")
            NSApp.activate(ignoringOtherApps: true)
        }
        Toggle("Automatically Collect Screenshots", isOn: $manager.captureEnabled)
        Divider()
        Button("Quit Sapphire Screenshots") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
