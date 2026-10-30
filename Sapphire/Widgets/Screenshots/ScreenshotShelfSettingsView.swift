import AppKit
import SwiftUI

@MainActor
struct ScreenshotShelfSettingsView: View {
    @ObservedObject private var manager: ScreenshotShelfManager

    init(manager: ScreenshotShelfManager? = nil) {
        _manager = ObservedObject(wrappedValue: manager ?? .shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Screenshots", systemImage: "camera.viewfinder")
                .font(.headline)
            Toggle("Collect new screenshots into Sapphire", isOn: $manager.captureEnabled)
            Toggle("Copy new screenshots to clipboard", isOn: $manager.automaticallyCopyNewScreenshots)
            Text("After collection, the latest screenshot replaces your clipboard image so you can paste with Command-V. History and imports are not copied. Choose immediate collection to paste sooner.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Collect screenshots", selection: $manager.captureTiming) {
                ForEach(ScreenshotCaptureTiming.allCases) { timing in
                    Text(LocalizedStringKey(timing.title)).tag(timing)
                }
            }
            .pickerStyle(.menu)
            if let error = manager.captureTimingError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            Text(manager.captureTiming == .immediate
                 ? "Skips the macOS floating thumbnail while collection is enabled. Sapphire collects the image as soon as the saved file is complete. Your previous thumbnail setting is restored when collection stops or Sapphire quits."
                 : "Keeps the macOS floating thumbnail available for editing and sharing. Sapphire collects the file after the preview finishes and macOS saves it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Keep new screenshots", selection: $manager.retention) {
                ForEach(ScreenshotShelfRetention.allCases) { retention in
                    Text(LocalizedStringKey(retention.title)).tag(retention)
                }
            }
            .pickerStyle(.menu)
            Text("New system screenshots move from their save folder into Sapphire. Manually imported images are copied. The selected retention applies to new items.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if manager.retention == .afterSuccessfulDrag {
                Text("A canceled drag keeps your screenshots. After an accepted drop, files remain readable for two minutes so the destination can finish loading them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Show Sapphire folder") { NSWorkspace.shared.open(manager.storageFolderURL) }
                Button("Choose source folder…") { manager.chooseFolder() }
            }
            if let error = manager.lastError {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("Retry") { manager.retryFailedOperations() }
            }
        }
        .padding(16)
    }
}
