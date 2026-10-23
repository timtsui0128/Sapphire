import AppKit
import SwiftUI

// Service fixtures let the real original views render without accessing the
// user's location, audio devices, files, or running developer processes.
final class WeatherViewModel: ObservableObject {
    static let shared = WeatherViewModel()
    let iconName = "cloud.sun.fill"
    let temperature = "18°"
    let locationName = "London"
    let conditionDescription = "Partly cloudy"
    let windInfo = "12 km/h"
    let precipChance = "10%"
    let humidity = "65%"
    let highLowTemp = "H: 20°  L: 13°"
    let feelsLike = "17°"
    let lastUpdated: Date? = Date()
    let isFetching = false
    let gradientColors: [Color] = [.blue, .cyan]
    let hourlyForecasts = (0..<7).map {
        HourlyForecastUIData(id: $0, time: "\(12 + $0):00", iconName: $0 < 4 ? "cloud.sun.fill" : "cloud.fill", temperatureMetric: "\(18 - $0 / 2)°", temperature: "64°")
    }
    func fetch() {}
}

struct HourlyForecastUIData: Identifiable {
    let id: Int
    let time: String
    let iconName: String
    let temperatureMetric: String
    let temperature: String
}

struct WidgetSettings { var weatherUseCelsius = true }
struct SettingsObserver { var settings = WidgetSettings() }
@propertyWrapper struct ObservedSettings: DynamicProperty {
    var wrappedValue = SettingsObserver()
}
enum WidgetDestination { case weatherPlayer }
private struct NavigationKey: EnvironmentKey {
    static let defaultValue: Binding<[WidgetDestination]> = .constant([])
}
extension EnvironmentValues {
    var navigationStack: Binding<[WidgetDestination]> {
        get { self[NavigationKey.self] }
        set { self[NavigationKey.self] = newValue }
    }
}

@main
private struct RenderOriginalWidgets {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let root = VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Original Sapphire widgets").font(.title2.bold())
                Spacer()
                Text(AppAppearance.shared.mode.title).foregroundStyle(.secondary)
            }
            HStack(spacing: 30) {
                WeatherWidgetView()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio levels").font(.headline)
                    ModernDarkSlider(label: "Input gain", value: .constant(0.58), range: 0...1, formatDisplay: { "\(Int($0 * 100))%" })
                    ModernDarkSlider(label: "Volume", value: .constant(0.12), range: 0...1, formatDisplay: { "\(Int($0 * 100))%" })
                }.frame(width: 250)
            }
            Divider()
            WeatherPlayerView()
                .frame(maxWidth: .infinity)
            Divider()
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Developer controls").font(.headline)
                    RoundedPillSwitcher(items: ["Tasks", "Usage", "Terminal"], title: { $0 }, selection: .constant("Terminal"))
                    HStack {
                        DevIconButton(symbol: "arrow.clockwise", help: "Refresh", action: {})
                        DevIconButton(symbol: "stop.fill", help: "Stop", tint: .red, action: {})
                    }
                }.frame(width: 210, alignment: .leading)
                DevMonospaceLog(text: "$ swift build\nBuilding for debugging…\n[1/2] Compiling Sapphire\n[2/2] Linking Sapphire\nBuild complete.")
                    .frame(height: 125)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(24)
        .frame(width: 760, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .appPanelAppearance()
        .appAppearance()

        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: AppAppearance.shared.resolvedColorScheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 640)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "OriginalWidgetRender", code: 1)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let file = output.appendingPathComponent("original-widgets-\(AppAppearance.shared.mode.rawValue).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
        print("Rendered \(file.lastPathComponent)")
        window.close()
    }
}
