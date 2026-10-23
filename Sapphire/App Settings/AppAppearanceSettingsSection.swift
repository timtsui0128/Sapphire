import SwiftUI

@MainActor
struct AppAppearanceSettingsSection: View {
    @ObservedObject private var appearance: AppAppearance

    init(appearance: AppAppearance? = nil) {
        _appearance = ObservedObject(wrappedValue: appearance ?? .shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App appearance").font(.title2.bold())
            Picker("App appearance", selection: $appearance.mode) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Choose the appearance of Settings and all expanded notch panels. Follow System changes with macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            Text("Top bar & panel").font(.headline)
            Picker("Top bar & panel surface", selection: $appearance.expandedPanelSurface) {
                ForEach(ExpandedPanelSurface.allCases) { surface in
                    Text(surface.title).tag(surface)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Use one continuous surface for the expanded top bar and panel. Match Panel follows the Expanded Notch Appearance settings below.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Changes apply immediately. The physical camera cutout cannot change color.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
