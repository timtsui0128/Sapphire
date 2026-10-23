import Foundation

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "F1LiveChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    init() { super.init(suiteName: "SapphireF1LiveChecks.\(UUID().uuidString)")! }
    override func object(forKey key: String) -> Any? { values[key] }
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

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [URL] = []
    func append(_ url: URL) { lock.lock(); entries.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return entries }
}

private func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockProtocol.self]
    return URLSession(configuration: config)
}

private func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
private let timestamp = "2026-10-11T12:00Z"
private let fixtureDate = CommunitySportsDecoder.date(timestamp)!

private func scoreboard(
    eventID: String = "weekend", sessionID: String = "race", state: String = "in",
    code: String = "Race", period: Int? = 23, driverCount: Int = 8
) -> Data {
    var status: [String: Any] = ["type": [
        "state": state, "completed": state == "post",
        "description": state == "in" ? "In Progress" : state == "post" ? "Final" : "Scheduled"
    ]]
    if let period { status["period"] = period }
    let competitors = (1...max(1, driverCount)).compactMap { position -> [String: Any]? in
        guard driverCount > 0 else { return nil }
        return [
            "id": "\(position)", "order": position,
            "athlete": ["displayName": "Driver \(position)", "shortName": "D. \(position)"]
        ]
    }.reversed()
    return data(["events": [[
        "id": eventID, "name": "Fixture Grand Prix",
        "links": [["href": "https://www.espn.com/racing/f1/race/_/id/\(eventID)", "rel": ["summary"]]],
        "competitions": [[
            "id": sessionID, "date": timestamp, "type": ["abbreviation": code],
            "status": status, "competitors": Array(competitors)
        ]]
    ]]])
}

private func core(eventID: String = "weekend", sessionID: String = "race", driverCount: Int = 8) -> Data {
    let base = "http://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/\(eventID)/competitions/\(sessionID)"
    let rows = (1...max(1, driverCount)).compactMap { position -> [String: Any]? in
        guard driverCount > 0 else { return nil }
        return [
            "id": "\(position)",
            "vehicle": ["number": "\(position * 3)", "manufacturer": position == 8 ? "Racing Bulls" : "Red Bull"],
            "status": ["$ref": "\(base)/competitors/\(position)/status?lang=en&region=us"]
        ]
    }
    return data(["competitors": rows, "statistics": ["$ref": "\(base)/statistics?lang=en&region=us"]])
}

private let statistics = data(["categories": [["name": "general", "stats": [["name": "laps", "value": 62]]]]])
private let latestRace = data(["MRData": ["RaceTable": ["Races": [[
    "season": "2026", "round": "18", "raceName": "Fixture Grand Prix",
    "date": "2026-10-11", "time": "12:00:00Z", "Circuit": ["circuitName": "Fixture Circuit"],
    "Results": []
]]]]])

private func normalResponse(_ request: URLRequest, log: RequestLog? = nil) -> (Int, Data, TimeInterval) {
    let url = request.url!
    log?.append(url)
    if url.path.hasSuffix("/scoreboard") { return (200, scoreboard(), 0) }
    if url.path.hasSuffix("/statistics") { return (200, statistics, 0) }
    if url.path.hasSuffix("/status") { return (200, data(["period": 22, "type": ["name": "STATUS_IN_PROGRESS"]]), 0) }
    return (200, core(), 0)
}

@main
private struct F1LiveChecks {
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            let store = F1LiveTimingStore(defaults: MemoryDefaults())
            await store.refresh(date: fixtureDate)
            guard let snapshot = store.snapshot else {
                throw NSError(domain: "F1LiveChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: store.errorMessage ?? "No live provider response"])
            }
            try check(snapshot.title.contains("Singapore") && snapshot.sessionTitle == "Race", "Historical request must select the Singapore race")
            try check(snapshot.isCompleted && !snapshot.isLive && snapshot.drivers.count >= 20, "Published classification must remain completed")
            try check(snapshot.lap == 62 && snapshot.totalLaps == 62, "Real provider race lap fields should decode")
            try check(snapshot.drivers.filter { $0.laps != nil }.count <= 5, "Optional driver status queries must remain bounded")
            try check(snapshot.drivers.allSatisfy { $0.constructorID != nil && $0.number != nil && $0.gap == nil }, "Core metadata should join without fabricated gaps")
            print("PASS: native URLSession public ESPN production — \(snapshot.title), \(snapshot.drivers.count) drivers, \(snapshot.lap!)/\(snapshot.totalLaps!) laps, \(snapshot.drivers.filter { $0.laps != nil }.count) bounded driver status rows")
            let upcoming = F1LiveTimingStore(defaults: MemoryDefaults())
            await upcoming.refresh()
            try check(upcoming.snapshot != nil && upcoming.errorMessage == nil, "Current public scoreboard must load")
            try check(!upcoming.availableDrivers.isEmpty, "Upcoming empty sessions must still load a recent favorite-picker roster")
            print("PASS: current session \(upcoming.snapshot!.sessionTitle), state \(upcoming.snapshot!.status), favorite roster \(upcoming.availableDrivers.count) drivers")
            return
        }

        let selected = try F1LiveDecoder.select(scoreboard(), now: fixtureDate)!
        let coreObject = try CommunitySportsDecoder.object(core())
        let statsObject = try CommunitySportsDecoder.object(statistics)
        let live = F1LiveDecoder.snapshot(
            selection: selected, core: coreObject, raceStatistics: statsObject,
            driverStatuses: ["8": ["period": 7, "type": ["name": "STATUS_RETIRED"]]],
            fetchedAt: fixtureDate, now: fixtureDate
        )
        try check(live.isLive && !live.isCompleted && live.lap == 23 && live.totalLaps == 62, "Live state and lap fields must follow provider")
        try check(live.drivers.compactMap(\.position) == Array(1...8), "Driver order must sort by actual position")
        try check(live.drivers.last?.constructorID == "f1:rb" && live.drivers.first?.constructorID == "f1:red_bull", "Constructor IDs must match Jolpica favorites")
        try check(live.drivers.last?.isRetired == true && live.drivers.last?.laps == 7, "Explicit driver retirement and lap count should decode")
        try check(live.drivers.first?.laps == nil && live.drivers.allSatisfy { $0.gap == nil }, "Absent per-driver laps/gaps must remain absent")
        try check(live.providerUpdatedAt == nil && !live.isStale, "Fetch time cannot fabricate provider update time")
        print("PASS: live positions, race laps, metadata join, retired status and honest missing values")

        let missingSelection = try F1LiveDecoder.select(scoreboard(period: nil), now: fixtureDate)!
        let missing = F1LiveDecoder.snapshot(selection: missingSelection, core: [:], raceStatistics: nil, driverStatuses: [:], fetchedAt: fixtureDate, now: fixtureDate)
        try check(missing.lap == nil && missing.totalLaps == nil, "Missing lap fields must not become zero")
        let practiceSelection = try F1LiveDecoder.select(scoreboard(code: "FP1"), now: fixtureDate)!
        let practice = F1LiveDecoder.snapshot(selection: practiceSelection, core: [:], raceStatistics: statsObject, driverStatuses: ["1": ["period": 20]], fetchedAt: fixtureDate, now: fixtureDate)
        try check(practice.sessionTitle == "Practice 1" && practice.lap == nil && practice.totalLaps == nil && practice.drivers.first?.laps == nil, "Practice periods must not be labeled race laps")
        let finalSelection = try F1LiveDecoder.select(scoreboard(state: "post", period: 62), now: fixtureDate, historical: true)!
        let final = F1LiveDecoder.snapshot(selection: finalSelection, core: coreObject, raceStatistics: statsObject, driverStatuses: [:], fetchedAt: fixtureDate, now: fixtureDate.addingTimeInterval(61))
        try check(final.isCompleted && !final.isLive && final.isStale, "Final classification must be completed and old snapshots marked stale")
        let none = try F1LiveDecoder.select(data(["events": []]), now: fixtureDate)
        try check(none == nil, "Empty event dates are valid")
        do {
            _ = try F1LiveDecoder.select(data(["error": "unavailable"]), now: fixtureDate)
            throw NSError(domain: "Expected decode failure", code: 1)
        } catch CommunitySportsError.invalidData {}
        try check(F1LiveDecoder.referencedURL(["$ref": "http://sports.core.api.espn.com/v2/sports/racing/fixture"])?.scheme == "https", "Known public references must use TLS")
        try check(F1LiveDecoder.referencedURL(["$ref": "https://untrusted.example/private"]) == nil, "Unexpected ref hosts must not be fetched")
        print("PASS: final/practice/missing lap handling, stale snapshots, provider errors and constrained references")

        let coalescingLog = RequestLog()
        MockProtocol.handler = { request in
            coalescingLog.append(request.url!)
            return (200, scoreboard(), 0.03)
        }
        let client = F1LiveTimingClient(session: session(), now: { fixtureDate })
        let testURL = URL(string: "https://site.api.espn.com/test")!
        async let first = client.fetch(testURL, ttl: 15)
        async let second = client.fetch(testURL, ttl: 15)
        _ = try await (first, second)
        _ = try await client.fetch(testURL, ttl: 15)
        try check(coalescingLog.urls.count == 1, "Simultaneous and cached requests must be coalesced")
        print("PASS: concurrent request coalescing and TTL caching")

        var clock = fixtureDate
        let log = RequestLog()
        MockProtocol.handler = { normalResponse($0, log: log) }
        let defaults = MemoryDefaults()
        defaults.set(["f1:rb", "soccer:42"], forKey: "CommunitySportsFavoriteTeamIDs")
        let store = F1LiveTimingStore(session: session(), defaults: defaults, now: { clock })
        try check(store.isNotchEnabled && store.favoriteConstructorIDs == ["f1:rb"], "Default notch setting and existing F1 favorites should migrate narrowly")
        await store.refresh()
        try check(store.snapshot?.drivers.count == 8 && store.errorMessage == nil, "Store should publish real fixture standings")
        let statusURLs = log.urls.filter { $0.path.hasSuffix("/status") }
        try check(statusURLs.count == 5 && statusURLs.contains { $0.path.contains("/8/status") }, "At most five drivers may be queried, with favorites included first")
        try check(log.urls.count == 8 && log.urls.allSatisfy { $0.scheme == "https" }, "One refresh should use scoreboard, metadata, stats and at most five statuses")
        let initialCount = log.urls.count
        await store.refresh(force: true)
        try check(log.urls.count == initialCount, "Explicit refreshes must respect minimum interval")
        clock = clock.addingTimeInterval(16)
        await store.refresh()
        try check(log.urls.count == initialCount + 1, "Stable metadata/statistics and 30-second status cache must avoid refetch")
        store.toggleFavorite(driver: store.snapshot!.drivers[0])
        store.isNotchEnabled = false
        let restored = F1LiveTimingStore(session: session(), defaults: defaults)
        try check(restored.favoriteDriverIDs == ["espn:f1:1"] && !restored.isNotchEnabled, "Favorites and notch preferences must persist")
        print("PASS: bounded favorite status queries, minimum refresh rate, stable caches and preference persistence")

        let lastFetch = store.snapshot!.fetchedAt
        clock = clock.addingTimeInterval(61)
        MockProtocol.handler = { _ in (503, Data(), 0) }
        await store.refresh()
        try check(store.snapshot?.isStale == true && store.snapshot?.fetchedAt == lastFetch && store.errorMessage != nil, "Failure must retain original timestamp and mark stale values")
        let failedLog = RequestLog()
        MockProtocol.handler = { request in failedLog.append(request.url!); return (503, Data(), 0) }
        let failed = F1LiveTimingStore(session: session(), defaults: MemoryDefaults(), now: { fixtureDate })
        await failed.refresh()
        await failed.refresh(force: true)
        try check(failedLog.urls.count == 1 && failed.snapshot == nil && failed.errorMessage != nil, "Failures must back off without fake live values")
        print("PASS: stale retention and failure backoff")

        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("/scoreboard") {
                let old = request.url!.query?.contains("20261011") == true
                return (200, scoreboard(sessionID: old ? "old" : "new"), old ? 0.15 : 0)
            }
            return normalResponse(request)
        }
        let switching = F1LiveTimingStore(session: session(), defaults: MemoryDefaults(), now: { fixtureDate })
        let oldRequest = Task { await switching.refresh(date: fixtureDate) }
        try await Task.sleep(for: .milliseconds(20))
        await switching.refresh(date: fixtureDate.addingTimeInterval(86_400))
        await oldRequest.value
        try check(switching.snapshot?.sessionID == "new" && !switching.isLoading, "Canceled older selection cannot replace newer state")
        MockProtocol.handler = { _ in (200, scoreboard(), 0.12) }
        let stopped = F1LiveTimingStore(session: session(), defaults: MemoryDefaults(), now: { fixtureDate })
        let pending = Task { await stopped.refresh() }
        try await Task.sleep(for: .milliseconds(20))
        stopped.stopPolling()
        await pending.value
        try check(stopped.snapshot == nil && !stopped.isLoading, "Stopped polling must not publish pending data")
        print("PASS: out-of-order request isolation and cancellation")

        MockProtocol.handler = { request in
            let url = request.url!
            if url.host == "api.jolpi.ca" { return (200, latestRace, 0) }
            if url.path.hasSuffix("/scoreboard") {
                return url.query == nil
                    ? (200, scoreboard(sessionID: "upcoming", state: "pre", driverCount: 0), 0)
                    : (200, scoreboard(state: "post", period: 62), 0)
            }
            if url.path.contains("/upcoming") { return (200, core(sessionID: "upcoming", driverCount: 0), 0) }
            return normalResponse(request)
        }
        let offWeekend = F1LiveTimingStore(session: session(), defaults: MemoryDefaults(), now: { fixtureDate })
        await offWeekend.refresh()
        try check(offWeekend.snapshot?.sessionID == "upcoming" && offWeekend.snapshot?.drivers.isEmpty == true && offWeekend.snapshot?.isLive == false, "Favorite roster cannot replace scheduled event with historic live-looking data")
        try check(offWeekend.availableDrivers.count == 8, "Recent completed roster should support off-weekend favorites")
        print("PASS: recent favorite roster remains separate from an upcoming empty session")
    }
}
