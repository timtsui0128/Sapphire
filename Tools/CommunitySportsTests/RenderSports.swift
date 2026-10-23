import AppKit
import Foundation
import SwiftUI

/// Renders the production Sports board without presenting a window or using live data.
private final class RenderDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    init() { super.init(suiteName: "SapphireSportsRender.\(UUID().uuidString)")! }
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

private final class RenderProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let data: Data
        if url.path.contains("constructors") {
            data = Data(#"{"MRData":{"ConstructorTable":{"Constructors":[{"constructorId":"team1","name":"Team One"},{"constructorId":"team2","name":"Team Two"}]}}}"#.utf8)
        } else if url.path.contains("/ergast/f1/") {
            data = raceFixture(results: url.path.contains("results"))
        } else if url.path.hasSuffix("/teams") {
            data = Data(#"{"sports":[{"leagues":[{"teams":[{"team":{"id":"42","displayName":"North London Athletic","abbreviation":"NLA"}},{"team":{"id":"43","displayName":"Manchester City","abbreviation":"MCI"}}]}]}]}"#.utf8)
        } else {
            data = footballFixture()
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func footballFixture() -> Data {
    func event(id: String, state: String, status: String) -> [String: Any] {
        [
            "id": id, "date": "2024-07-07T12:00Z",
            "links": [["href": "https://www.espn.com/soccer/match/_/gameId/\(id)", "rel": ["summary"]]],
            "competitions": [[
                "status": ["displayClock": "67′", "type": ["state": state, "completed": state == "post", "shortDetail": status]],
                "competitors": [
                    ["homeAway": "away", "score": "1", "team": ["id": "43", "displayName": "Manchester City", "abbreviation": "MCI"]],
                    ["homeAway": "home", "score": "2", "team": ["id": "42", "displayName": "North London Athletic", "abbreviation": "NLA"]]
                ]
            ]]
        ]
    }
    return try! JSONSerialization.data(withJSONObject: ["events": [
        event(id: "1", state: "in", status: "67′"),
        event(id: "2", state: "pre", status: "Scheduled")
    ]])
}

private func raceFixture(results: Bool) -> Data {
    func race(_ number: String, _ date: String) -> [String: Any] {
        var row: [String: Any] = [
            "season": "2024", "round": number,
            "raceName": number == "1" ? "British Grand Prix" : "Hungarian Grand Prix",
            "date": date, "time": "13:00:00Z",
            "Circuit": ["circuitName": number == "1" ? "Silverstone Circuit" : "Hungaroring"],
            "url": "https://en.wikipedia.org/wiki/Grand_Prix"
        ]
        if results {
            row["Results"] = [
                ["position": "1", "points": "25", "Time": ["time": "1:20:00.000"],
                 "Driver": ["driverId": "first", "givenName": "First", "familyName": "Driver"],
                 "Constructor": ["constructorId": "team1", "name": "Team One"]],
                ["position": "2", "points": "18", "Time": ["time": "+2.521"],
                 "Driver": ["driverId": "second", "givenName": "Second", "familyName": "Driver"],
                 "Constructor": ["constructorId": "team2", "name": "Team Two"]],
                ["position": "3", "points": "15", "status": "Finished",
                 "Driver": ["driverId": "third", "givenName": "Third", "familyName": "Driver"],
                 "Constructor": ["constructorId": "team1", "name": "Team One"]]
            ]
        }
        return row
    }
    return try! JSONSerialization.data(withJSONObject: [
        "MRData": ["RaceTable": ["Races": [race("1", "2024-07-07"), race("2", "2024-07-14")]]]
    ])
}

@main
private struct RenderSports {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/sapphire-sports-renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-sports-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        UserDefaults.standard.setVolatileDomain(
            [AppAppearance.defaultsKey: "system"], forName: UserDefaults.argumentDomain
        )
        _ = AppAppearance.shared
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RenderProtocol.self]
        let session = URLSession(configuration: config)

        for league: CommunitySportsLeague in [.premierLeague, .f1] {
            let store = CommunitySportsStore(
                session: session,
                defaults: RenderDefaults(),
                storageURL: temporary.appendingPathComponent("\(league.rawValue).json")
            )
            store.selectedLeague = league
            store.selectedDate = CommunitySportsDecoder.date(league.isRacing ? "2024-07-20T12:00Z" : "2024-07-07T12:00Z")!
            await store.load()
            guard store.events.count == 2, store.errorMessage == nil else {
                throw NSError(domain: "SportsRender", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture load failed: \(store.errorMessage ?? "missing events")"])
            }
            if let team = store.teams.first { store.toggleFavorite(team) }
            let timing = F1LiveTimingStore(session: session, defaults: RenderDefaults())
            for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                // Render the actual shared modifier after its system appearance observer updates.
                try await Task.sleep(for: .milliseconds(50))
                guard AppAppearance.shared.resolvedColorScheme == (scheme == "dark" ? .dark : .light) else {
                    throw NSError(domain: "SportsRender", code: 4)
                }
                let panelScheme: ColorScheme = scheme == "dark" ? .dark : .light
                try await checkEmbeddedWidget(CommunitySportsBoardView(store: store, timing: timing, width: 590),
                    size: CGSize(width: 590, height: 430), scheme: panelScheme,
                    to: output.appendingPathComponent("sports-\(league.rawValue)-panel-\(scheme).png"))
                try await checkEmbeddedWidget(CommunitySportsCompactView(store: store, timing: timing),
                    size: CGSize(width: 196, height: 160), scheme: panelScheme,
                    to: output.appendingPathComponent("sports-\(league.rawValue)-compact-panel-\(scheme).png"))
                for width in [590, 500] {
                    let board = CommunitySportsBoardView(store: store, timing: timing, width: width == 590 ? 590 : nil)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                        .frame(width: CGFloat(width), height: 430, alignment: .top)
                    let host = NSHostingView(rootView: board)
                    let frame = NSRect(x: 0, y: 0, width: width, height: 430)
                    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: appearance)
                    window.contentView = host
                    host.frame = frame
                    host.layoutSubtreeIfNeeded()
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                        throw NSError(domain: "SportsRender", code: 2)
                    }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else {
                        throw NSError(domain: "SportsRender", code: 3)
                    }
                    let name = "\(league.isRacing ? "f1" : "football")-\(width)-\(scheme).png"
                    try png.write(to: output.appendingPathComponent(name))
                    print("Rendered \(name): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
                    window.close()
                }
            }
        }
    }
}
