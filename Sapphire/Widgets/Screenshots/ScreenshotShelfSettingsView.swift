import AppKit
import SwiftUI

@MainActor
struct ScreenshotShelfSettingsView: View {
    @ObservedObject private var manager = ScreenshotShelfManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Screenshots", systemImage: "camera.viewfinder")
                .font(.headline)
            Toggle("Collect new screenshots into Sapphire", isOn: $manager.captureEnabled)
            Picker("Keep new screenshots", selection: $manager.retention) {
                ForEach(ScreenshotShelfRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
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
