import AppKit
import SwiftUI

@main
struct RenderFinance {
    @MainActor
    static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/sapphire-finance-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        UserDefaults.standard.setVolatileDomain(
            [AppAppearance.defaultsKey: "system"], forName: UserDefaults.argumentDomain
        )
        _ = AppAppearance.shared
        let suiteName = "CommunityFinanceRender.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = CommunityFinanceClient { url in
            var object = try JSONSerialization.jsonObject(with: FinanceFixtures.yahoo(symbol: url.lastPathComponent)) as! [String: Any]
            var chart = object["chart"] as! [String: Any]
            var results = chart["result"] as! [[String: Any]]
            let prices: [Double] = [97, 99, 98, 100, 99, 104, 102, 101, 103, 106, 105, 107, 105, 109, 110]
            let dates = prices.indices.map { Date().addingTimeInterval(Double($0 - prices.count + 1) * 86400).timeIntervalSince1970 }
            results[0]["timestamp"] = dates
            results[0]["indicators"] = ["quote": [["close": prices]]]
            chart["result"] = results
            object["chart"] = chart
            return try JSONSerialization.data(withJSONObject: object)
        }
        let store = CommunityFinanceStore(defaults: defaults, client: client)
        await store.refresh()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            // Allow the production appearance observer to deliver its change on the main actor.
            try await Task.sleep(for: .milliseconds(50))
            try render(
                CommunityFinanceBoardView(store: store, width: 600),
                size: NSSize(width: 600, height: 405), appearance: appearance,
                to: output.appendingPathComponent("finance-\(name).png")
            )
            try render(
                CommunityFinanceCompactView(store: store),
                size: NSSize(width: 180, height: 180), appearance: appearance,
                to: output.appendingPathComponent("finance-compact-\(name).png")
            )
            let scheme: ColorScheme = name == "dark" ? .dark : .light
            try await checkEmbeddedWidget(CommunityFinanceBoardView(store: store, width: 600),
                size: CGSize(width: 600, height: 405), scheme: scheme,
                to: output.appendingPathComponent("finance-panel-\(name).png"))
            try await checkEmbeddedWidget(CommunityFinanceCompactView(store: store),
                size: CGSize(width: 180, height: 180), scheme: scheme,
                to: output.appendingPathComponent("finance-compact-panel-\(name).png"))
        }
        for symbol in store.watchlist { store.remove(symbol: symbol) }
        try render(
            CommunityFinanceBoardView(store: store, width: 600),
            size: NSSize(width: 600, height: 310), appearance: .darkAqua,
            to: output.appendingPathComponent("finance-empty.png")
        )
    }

    @MainActor
    static func render<Content: View>(
        _ content: Content, size: NSSize, appearance: NSAppearance.Name, to output: URL
    ) throws {
        let view = content
            .environment(\.locale, Locale(identifier: "en_GB"))
            .frame(width: size.width, height: size.height, alignment: .top)
        let host = NSHostingView(rootView: view)
        let frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.frame = frame
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: output)
        print("Rendered \(output.lastPathComponent): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
        window.close()
    }
}
