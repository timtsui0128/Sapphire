import Foundation

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "SportsChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    init() { super.init(suiteName: "SapphireSportsChecks.\(UUID().uuidString)")! }
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

private final class MockProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (URLRequest) -> (Int, Data, TimeInterval) = { _ in (500, Data(), 0) }
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data, delay) = Self.handler(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            lock.lock()
            defer { lock.unlock() }
            guard !stopped else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockProtocol.self]
    return URLSession(configuration: config)
}

private let teamsData = Data(#"{"sports":[{"leagues":[{"teams":[{"team":{"id":"42","displayName":"Test Home","abbreviation":"HOM"}},{"team":{"id":"43","displayName":"Test Away","abbreviation":"AWY"}}]}]}]}"#.utf8)

private func footballData(id: String = "1", state: String = "pre", complete: Bool = false, timestamp: String = "2024-07-07T12:00Z", status: String = "Scheduled") -> Data {
    let object: [String: Any] = ["events": [[
        "id": id, "date": timestamp,
        "links": [["href": "https://www.espn.com/soccer/match/_/gameId/\(id)", "rel": ["summary"]]],
        "competitions": [[
            "status": ["displayClock": "67'", "type": ["state": state, "completed": complete, "shortDetail": status]],
            // Intentionally reversed: order must not determine home/away.
            "competitors": [
                ["homeAway": "away", "score": "1", "team": ["id": "43", "displayName": "Test Away", "abbreviation": "AWY"]],
                ["homeAway": "home", "score": "2", "team": ["id": "42", "displayName": "Test Home", "abbreviation": "HOM"]]
            ]
        ]]
    ]]]
    return try! JSONSerialization.data(withJSONObject: object)
}

private func racingData(round: String? = nil) -> Data {
    func race(_ number: String, _ date: String) -> [String: Any] {
        var result: [String: Any] = [
            "season": "2024", "round": number, "raceName": "Test Grand Prix \(number)",
            "date": date, "time": "13:00:00Z", "Circuit": ["circuitName": "Test Circuit"],
            "url": "http://en.wikipedia.org/wiki/Test_Grand_Prix"
        ]
        if round != nil {
            result["Results"] = [
                ["position": "2", "points": "18", "status": "Finished", "Driver": ["driverId": "second", "givenName": "Second", "familyName": "Driver"], "Constructor": ["constructorId": "team2", "name": "Team Two"]],
                ["position": "1", "points": "25", "Time": ["time": "1:20:00"], "Driver": ["driverId": "first", "givenName": "First", "familyName": "Driver"], "Constructor": ["constructorId": "team1", "name": "Team One"]]
            ]
        }
        return result
    }
    let races = round == nil ? [race("1", "2024-07-07"), race("2", "2024-07-14")] :
        [race(round == "last" ? "2" : round!, round == "1" ? "2024-07-07" : "2024-07-14")]
    return try! JSONSerialization.data(withJSONObject: ["MRData": ["RaceTable": ["Races": races]]])
}

@main
private struct CommunitySportsChecks {
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            let client = CommunitySportsClient()
            let year = Calendar.current.component(.year, from: Date())
            let football = try await client.football(league: .premierLeague, date: Date())
            let teams = try await client.footballTeams(league: .championsLeague)
            let races = try await client.racing(year: year)
            let results = try await client.racing(year: year, round: "last")
            let constructors = try await client.racingTeams(year: year)
            try check(!teams.isEmpty && !races.isEmpty && !constructors.isEmpty, "Live provider catalogs must not be empty")
            print("PASS: native URLSession live providers — \(football.count) selected-day EPL matches, \(teams.count) UCL teams, \(races.count) F1 races, \(results.reduce(0) { $0 + $1.results.count }) published result rows, \(constructors.count) constructors")
            return
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("sports-fixtures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let date = CommunitySportsDecoder.date("2024-07-07T12:00Z")!

        let scheduled = try CommunitySportsDecoder.football(footballData(), league: .premierLeague)
        try check(scheduled.count == 1 && scheduled[0].homeTeam?.id == "soccer:42", "Home/away must follow homeAway, not array order")
        try check(scheduled[0].homeScore == nil && scheduled[0].awayScore == nil, "Scheduled scores must be absent")
        try check(scheduled[0].startDate == date, "Minute-precision ESPN timestamp must decode")
        let live = try CommunitySportsDecoder.football(footballData(state: "in", status: "67'"), league: .premierLeague)[0]
        try check(live.isLive && live.homeScore == "2" && live.awayScore == "1", "Live scores should be real values")
        let final = try CommunitySportsDecoder.football(footballData(state: "post", complete: true, status: "FT"), league: .premierLeague)[0]
        try check(final.isComplete && !final.isLive && final.status == "FT", "Completed status must remain distinct from live")
        let postponed = try CommunitySportsDecoder.football(footballData(status: "Postponed"), league: .premierLeague)[0]
        try check(postponed.status == "Postponed" && postponed.homeScore == nil, "Postponement must not become 0–0")
        let empty = try CommunitySportsDecoder.football(Data(#"{"events":[]}"#.utf8), league: .premierLeague)
        try check(empty.isEmpty, "Empty scoreboard is valid")
        do {
            _ = try CommunitySportsDecoder.football(Data(#"{"error":"unavailable"}"#.utf8), league: .premierLeague)
            throw NSError(domain: "Expected decoder failure", code: 1)
        } catch CommunitySportsError.invalidData {}
        print("PASS: football phases, provider errors, missing scores, timestamps and home/away mapping")

        let calendar = try CommunitySportsDecoder.racing(racingData())
        let race = try CommunitySportsDecoder.racing(racingData(round: "1"))[0]
        try check(calendar.allSatisfy { !$0.isLive && !$0.isComplete && $0.results.isEmpty }, "Calendar cannot fabricate race results or live telemetry")
        try check(race.isComplete && !race.isLive && race.results.map(\.position) == [1, 2], "Published F1 classification should sort numerically")
        try check(race.results[0].teamID == "f1:team1" && race.linkURL?.scheme == "https", "F1 IDs and links should normalize")
        print("PASS: F1 published classifications, stable constructor IDs and no fabricated live state")

        let counter = RequestCounter()
        MockProtocol.handler = { _ in counter.increment(); return (200, Data(#"{"events":[]}"#.utf8), 0.03) }
        let client = CommunitySportsClient(session: session())
        let testURL = URL(string: "https://site.api.espn.com/fixture")!
        async let first = client.data(from: testURL, ttl: 30)
        async let second = client.data(from: testURL, ttl: 30)
        _ = try await (first, second)
        _ = try await client.data(from: testURL, ttl: 30, force: true)
        try check(counter.count == 1, "In-flight and immediate forced requests must be coalesced")
        print("PASS: concurrent request coalescing and minimum refresh interval")

        let preferences = MemoryDefaults()
        let snapshotURL = temp.appendingPathComponent("scores.json")
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("/teams") { return (200, teamsData, 0) }
            return (200, footballData(), 0)
        }
        let store = CommunitySportsStore(session: session(), defaults: preferences, storageURL: snapshotURL)
        store.selectedLeague = .premierLeague
        store.selectedDate = date
        await store.load()
        try check(store.events.count == 1 && store.teams.count == 2 && store.errorMessage == nil, "Store should publish scoreboard and team catalog")
        store.toggleFavorite(store.teams[0])
        try check(store.isFavorite(store.events[0]), "Favorite IDs must match a game's teams")
        MockProtocol.handler = { _ in (503, Data(), 0) }
        let offline = CommunitySportsStore(session: session(), defaults: preferences, storageURL: snapshotURL)
        offline.selectedDate = date
        await offline.load()
        try check(offline.favoriteTeamIDs == store.favoriteTeamIDs, "Favorites must survive store recreation")
        try check(offline.events == store.events && offline.lastUpdated != nil && offline.errorMessage?.contains("saved scores") == true, "Offline load must retain dated saved scores and show error")
        print("PASS: favorites persistence and honest offline snapshots")

        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("/teams") { return (200, teamsData, 0) }
            let slow = request.url!.path.contains("eng.1")
            return (200, footballData(id: slow ? "old-league" : "new-league"), slow ? 0.12 : 0)
        }
        let switching = CommunitySportsStore(session: session(), defaults: MemoryDefaults(), storageURL: temp.appendingPathComponent("switch.json"))
        switching.selectedLeague = .premierLeague
        switching.selectedDate = date
        let old = Task { await switching.load() }
        try await Task.sleep(for: .milliseconds(20))
        switching.selectedLeague = .laLiga
        await switching.load()
        await old.value
        try check(switching.events.first?.id == "espn:esp.1:new-league" && !switching.isLoading, "Late response must not replace newer league")
        print("PASS: out-of-order league requests cannot overwrite visible results")

        MockProtocol.handler = { request in
            let path = request.url!.path
            if path.contains("constructors") {
                return (200, Data(#"{"MRData":{"ConstructorTable":{"Constructors":[{"constructorId":"team1","name":"Team One"}]}}}"#.utf8), 0)
            }
            if path.contains("/last/") { return (200, racingData(round: "last"), 0) }
            if path.contains("/1/results") { return (200, racingData(round: "1"), 0) }
            return (200, racingData(), 0)
        }
        let racing = CommunitySportsStore(session: session(), defaults: MemoryDefaults(), storageURL: temp.appendingPathComponent("f1.json"))
        racing.selectedDate = CommunitySportsDecoder.date("2024-07-20T12:00Z")!
        await racing.load()
        try check(racing.events.count == 2 && racing.events[0].results.isEmpty && racing.events[1].isComplete, "F1 calendar merges last published results")
        await racing.loadResults(for: racing.events[0])
        try check(racing.events[0].results.count == 2, "Historical race details should load on demand")
        await racing.load(force: true)
        try check(racing.events[0].results.count == 2, "Refreshing must preserve an opened historical classification")
        print("PASS: F1 season calendar, on-demand historic results and refresh preservation")

        let adapterCounter = RequestCounter()
        let today = ISO8601DateFormatter().string(from: Date())
        MockProtocol.handler = { _ in
            adapterCounter.increment()
            return (200, footballData(state: "in", timestamp: today, status: "67'"), 0)
        }
        let adapter = SportsAPIService(client: CommunitySportsClient(session: session()))
        await adapter.prefetchLiveScoreboards(for: ["soccer:42"])
        let legacy = await adapter.fetchLiveEvent(for: "Test Home", forceRefresh: true)
        try check(legacy?.isLive == true && legacy?.homeScore == 2 && legacy?.awayScore == 1, "Adapter should map real scoreboard to existing live activity")
        try check(adapter.cachedLiveEvent(for: "Premier League") != nil, "League aliases must map to fetched games")
        try check(adapter.cachedLiveEvent(for: "Unknown Club") == nil, "Unknown favorites must not show another team's score")
        try check(adapterCounter.count == 21, "Legacy per-team refresh should reuse three dated requests per football league")
        let failedCounter = RequestCounter()
        MockProtocol.handler = { _ in failedCounter.increment(); return (503, Data(), 0) }
        let unavailableAdapter = SportsAPIService(client: CommunitySportsClient(session: session()))
        await unavailableAdapter.prefetchLiveScoreboards(for: ["Test Home"])
        let failedAttempts = failedCounter.count
        _ = await unavailableAdapter.fetchLiveEvent(for: "Test Home", forceRefresh: true)
        _ = await unavailableAdapter.fetchLiveEvent(for: "Test Away", forceRefresh: true)
        try check(failedAttempts > 0 && failedCounter.count == failedAttempts, "Serial favorite refreshes must back off after provider failure")
        print("PASS: legacy live-activity adapter matches team IDs/names and coalesces league requests")

        let enabled = Set(AppFeature.allCases.filter { SubscriptionAccess.hasAccess(to: $0) })
        try check(enabled == [.sportsWidget, .liveSports, .financeWidget, .financeLiveActivity], "Only independently implemented Sports and Finance features may be enabled")
        try check(FeatureGate.shared.require(.sportsWidget, message: "test"), "Own widget should pass its gate")
        print("PASS: narrow feature allowlist leaves all other private features disabled")
    }
}
