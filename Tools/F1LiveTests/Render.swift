import AppKit
import Foundation
import SwiftUI

private final class RenderDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    init() { super.init(suiteName: "SapphireF1Render.\(UUID().uuidString)")! }
    override func object(forKey key: String) -> Any? { values[key] }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

private let names = [
    "Max Verstappen", "Lando Norris", "Charles Leclerc",
    "Oscar Piastri", "Lewis Hamilton", "Gabriel Bortoleto"
]
private let constructors = ["Red Bull", "McLaren", "Ferrari", "McLaren", "Ferrari", "Audi"]
private let fixtureDate = CommunitySportsDecoder.date("2026-10-11T13:00Z")!

private func fixtureData(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

private func fixtureScoreboard() -> Data {
    let drivers = names.enumerated().map { index, name in
        [
            "id": "\(index + 1)", "order": index + 1,
            "athlete": ["displayName": name, "shortName": name]
        ] as [String: Any]
    }
    return fixtureData(["events": [[
        "id": "fixture-weekend", "name": "Singapore Airlines Singapore Grand Prix",
        "links": [["href": "https://www.espn.com/racing/f1/", "rel": ["summary"]]],
        "competitions": [[
            "id": "fixture-race", "date": "2026-10-11T12:00Z",
            "type": ["abbreviation": "Race"],
            "status": ["period": 23, "type": ["state": "in", "completed": false, "description": "In Progress"]],
            "competitors": drivers
        ]]
    ]]])
}

private func fixtureCore() -> Data {
    let base = "https://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/fixture-weekend/competitions/fixture-race"
    let drivers = constructors.enumerated().map { index, constructor in
        [
            "id": "\(index + 1)",
            "vehicle": ["number": "\(index + 1)", "manufacturer": constructor],
            "status": ["$ref": "\(base)/competitors/\(index + 1)/status"]
        ] as [String: Any]
    }
    return fixtureData([
        "competitors": drivers, "statistics": ["$ref": "\(base)/statistics"]
    ])
}

private final class RenderProtocol: URLProtocol, @unchecked Sendable {
    static var failRequests = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let body: Data
        if url.path.hasSuffix("/scoreboard") {
            body = fixtureScoreboard()
        } else if url.path.hasSuffix("/statistics") {
            body = fixtureData(["categories": [["stats": [["name": "laps", "value": 62]]]]])
        } else if url.path.contains("/3/status") {
            body = fixtureData(["type": ["name": "STATUS_IN_PROGRESS"]])
        } else if url.path.hasSuffix("/status") {
            let retired = url.path.contains("/5/status")
            body = fixtureData([
                "period": retired ? 7 : 22,
                "type": ["name": retired ? "STATUS_RETIRED" : "STATUS_IN_PROGRESS"]
            ])
        } else {
            body = fixtureCore()
        }
        let response = HTTPURLResponse(url: url, statusCode: Self.failRequests ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private struct RenderF1 {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/sapphire-f1-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RenderProtocol.self]
        let defaults = RenderDefaults()
        defaults.set(["espn:f1:2"], forKey: "F1LiveFavoriteDriverIDs")
        var clock = fixtureDate
        let store = F1LiveTimingStore(
            session: URLSession(configuration: config), defaults: defaults, now: { clock }
        )
        await store.refresh()
        guard let snapshot = store.snapshot, snapshot.drivers.count == 6,
              snapshot.drivers[4].isRetired, snapshot.drivers[5].laps == nil else {
            throw NSError(domain: "F1Render", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture did not exercise retirement and missing laps"])
        }
        guard F1LiveTimingPanel.lapText(nil, total: nil) == "Lap —",
              F1LiveTimingPanel.lapText(23, total: 62) == "Lap 23 / 62" else {
            throw NSError(domain: "F1Render", code: 2, userInfo: [NSLocalizedDescriptionKey: "Incorrect displayed lap formatting"])
        }
        for state in ["live", "stale"] {
            if state == "stale" {
                clock = clock.addingTimeInterval(61)
                RenderProtocol.failRequests = true
                await store.refresh()
                guard store.snapshot?.isStale == true else { throw NSError(domain: "F1Render", code: 5) }
            }
            for width in [500, 590] {
                for scheme: ColorScheme in [.light, .dark] {
                let content = F1LiveTimingPanel(store: store)
                    .padding(16)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    .environment(\.colorScheme, scheme)
                    .frame(width: CGFloat(width), height: 430, alignment: .top)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: content)
                let frame = NSRect(x: 0, y: 0, width: width, height: 430)
                let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                host.frame = frame
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    throw NSError(domain: "F1Render", code: 3)
                }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "F1Render", code: 4)
                }
                let filename = "f1-\(state)-\(width)-\(scheme == .dark ? "dark" : "light").png"
                try png.write(to: output.appendingPathComponent(filename))
                print("Rendered \(filename): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
                window.close()
                }
            }
        }
    }
}
