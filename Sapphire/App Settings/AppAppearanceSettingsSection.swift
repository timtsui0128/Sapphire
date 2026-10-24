import AppKit
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
            Text("The macOS menu bar and Dock use System Settings. Their transparent backgrounds can still show wallpaper colors in Dark Mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open macOS Appearance Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            Divider().padding(.vertical, 4)
            Text("External display").font(.headline)
            Picker("External display style", selection: $appearance.externalDisplayStyle) {
                ForEach(ExternalDisplayStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Menu Bar Line automatically replaces the idle capsule on external displays with a thin handle. Hover or click to open. Built-in displays keep their original style; live activities and expanded panels keep their content.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("External glass tone", selection: $appearance.externalGlassTone) {
                ForEach(ExternalGlassTone.allCases) { tone in
                    Text(tone.title).tag(tone)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Match Wallpaper adjusts the external handle and expanded Liquid Glass panel to the wallpaper's top edge. If a dynamic wallpaper or another background looks different, choose Light Glass or Dark Glass. Screenshot collection keeps the idle handle visible.")
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
