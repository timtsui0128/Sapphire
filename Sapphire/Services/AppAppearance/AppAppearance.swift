import AppKit
import Combine
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ExpandedPanelSurface: String, CaseIterable, Identifiable {
    case matchPanel, liquidGlass, white, black

    var id: String { rawValue }
    var title: String {
        switch self {
        case .matchPanel: return "Match Panel"
        case .liquidGlass: return "Liquid Glass"
        case .white: return "White"
        case .black: return "Black"
        }
    }

    func colorScheme(following scheme: ColorScheme) -> ColorScheme {
        switch self {
        case .white: return .light
        case .black: return .dark
        case .matchPanel, .liquidGlass: return scheme
        }
    }
}

private struct ExpandedNotchColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme? = nil
}

extension EnvironmentValues {
    var expandedNotchColorScheme: ColorScheme? {
        get { self[ExpandedNotchColorSchemeKey.self] }
        set { self[ExpandedNotchColorSchemeKey.self] = newValue }
    }
}

/// App content appearance is independent of the notch's per-display materials.
@MainActor
final class AppAppearance: ObservableObject {
    static let shared = AppAppearance()
    static let defaultsKey = "SapphireAppAppearanceMode"
    static let panelSurfaceDefaultsKey = "SapphireExpandedPanelSurface"

    @Published var mode: AppAppearanceMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.defaultsKey) }
    }
    @Published var expandedPanelSurface: ExpandedPanelSurface {
        didSet { defaults.set(expandedPanelSurface.rawValue, forKey: Self.panelSurfaceDefaultsKey) }
    }
    @Published private(set) var systemColorScheme: ColorScheme

    private let defaults: UserDefaults
    private var systemObservation: NSKeyValueObservation?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.defaultsKey)
            .flatMap(AppAppearanceMode.init(rawValue:)) ?? .system
        expandedPanelSurface = defaults.string(forKey: Self.panelSurfaceDefaultsKey)
            .flatMap(ExpandedPanelSurface.init(rawValue:)) ?? .matchPanel
        let application = NSApplication.shared
        systemColorScheme = Self.colorScheme(for: application.effectiveAppearance)
        systemObservation = application.observe(\.effectiveAppearance, options: [.new]) { [weak self] application, _ in
            let isDark = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            Task { @MainActor [weak self] in
                self?.systemColorScheme = isDark ? .dark : .light
            }
        }
    }

    var resolvedColorScheme: ColorScheme { mode.colorScheme ?? systemColorScheme }
    var expandedPanelColorScheme: ColorScheme {
        expandedPanelSurface.colorScheme(following: resolvedColorScheme)
    }

    func panelColorScheme(matchingGlass glassColorScheme: ColorScheme?) -> ColorScheme {
        expandedPanelSurface == .matchPanel ? (glassColorScheme ?? expandedPanelColorScheme) : expandedPanelColorScheme
    }

    private static func colorScheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

@MainActor
private struct AppWindowAppearanceModifier: ViewModifier {
    @ObservedObject var appearance: AppAppearance

    func body(content: Content) -> some View {
        // Resolve System explicitly so a legacy child view's preferred scheme
        // cannot turn the entire Settings window dark.
        content.preferredColorScheme(appearance.resolvedColorScheme)
    }
}

@MainActor
private struct AppContentAppearanceModifier: ViewModifier {
    @ObservedObject var appearance: AppAppearance
    @Environment(\.expandedNotchColorScheme) private var panelColorScheme

    func body(content: Content) -> some View {
        let colorScheme = panelColorScheme ?? appearance.resolvedColorScheme
        content
            .foregroundStyle(.primary)
            .background(
                // Embedded widgets reveal the single native panel material.
                // Standalone Settings previews still need their own canvas.
                panelColorScheme != nil ? Color.clear
                    : (colorScheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .environment(\.colorScheme, colorScheme)
    }
}

@MainActor
private struct AppPanelAppearanceModifier: ViewModifier {
    @ObservedObject var appearance: AppAppearance
    @Environment(\.expandedNotchColorScheme) private var inheritedColorScheme

    func body(content: Content) -> some View {
        let colorScheme = inheritedColorScheme ?? appearance.expandedPanelColorScheme
        content
            .foregroundStyle(.primary)
            .environment(\.colorScheme, colorScheme)
            .environment(\.expandedNotchColorScheme, colorScheme)
    }
}

extension View {
    @MainActor
    func appAppearance(_ appearance: AppAppearance? = nil) -> some View {
        modifier(AppWindowAppearanceModifier(appearance: appearance ?? .shared))
    }

    @MainActor
    func appContentAppearance(_ appearance: AppAppearance? = nil) -> some View {
        modifier(AppContentAppearanceModifier(appearance: appearance ?? .shared))
    }

    /// Expanded notch content shares the native surface rather than painting a
    /// separate card. Its top bar and content use one selected surface.
    @MainActor
    func appPanelAppearance(_ appearance: AppAppearance? = nil) -> some View {
        modifier(AppPanelAppearanceModifier(appearance: appearance ?? .shared))
    }
}
