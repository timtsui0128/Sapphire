import Combine
import Foundation

struct F1LiveDriver: Identifiable, Hashable, Sendable {
    let id: String
    let position: Int?
    let number: String?
    let name: String
    let abbreviation: String
    let constructorID: String?
    let constructorName: String?
    var laps: Int? = nil
    var gap: String? = nil
    var isRetired = false
}

struct F1LiveSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let sessionID: String
    let title: String
    let sessionTitle: String
    let status: String
    let isLive: Bool
    let isCompleted: Bool
    var isStale: Bool
    let lap: Int?
    let totalLaps: Int?
    var drivers: [F1LiveDriver]
    let startDate: Date?
    let providerUpdatedAt: Date?
    let fetchedAt: Date
    let sourceURL: URL?
}

/// ESPN's public scoreboard and core competition resources describe the same sessions.
/// A successful fetch is not a guarantee of a particular provider update latency.
enum F1LiveDecoder {
    struct Selection {
        let event: [String: Any]
        let competition: [String: Any]
        var eventID: String { event["id"] as? String ?? "" }
        var sessionID: String { competition["id"] as? String ?? "" }
        var competitionURL: URL {
            URL(string: "https://sports.core.api.espn.com/v2/sports/racing/leagues/f1/events/\(eventID)/competitions/\(sessionID)?lang=en&region=us")!
        }
    }

    static func select(_ data: Data, now: Date, historical: Bool = false) throws -> Selection? {
        let object = try CommunitySportsDecoder.object(data)
        guard let events = object["events"] as? [[String: Any]] else { throw CommunitySportsError.invalidData }
        let selections = events.flatMap { event in
            (event["competitions"] as? [[String: Any]] ?? []).compactMap { competition -> Selection? in
                guard let eventID = event["id"] as? String, !eventID.isEmpty,
                      let sessionID = competition["id"] as? String, !sessionID.isEmpty else { return nil }
                return Selection(event: event, competition: competition)
            }
        }
        func date(_ selection: Selection) -> Date {
            CommunitySportsDecoder.date(selection.competition["date"] as? String) ?? .distantFuture
        }
        func state(_ selection: Selection) -> String {
            ((selection.competition["status"] as? [String: Any])?["type"] as? [String: Any])?["state"] as? String ?? "pre"
        }
        let live = selections.filter { state($0) == "in" }.sorted { date($0) > date($1) }
        if let selection = live.first { return selection }
        if historical {
            let completed = selections.filter { state($0) == "post" }
            if let race = completed.first(where: { ($0.competition["type"] as? [String: Any])?["abbreviation"] as? String == "Race" }) {
                return race
            }
            if let latest = completed.sorted(by: { date($0) > date($1) }).first { return latest }
        }
        if let upcoming = selections.filter({ state($0) == "pre" && date($0) >= now })
            .sorted(by: { date($0) < date($1) }).first { return upcoming }
        return selections.sorted { date($0) > date($1) }.first
    }

    static func integer(_ value: Any?) -> Int? {
        let number: Int?
        if let numberValue = value as? NSNumber { number = numberValue.intValue }
        else if let string = value as? String { number = Int(string) }
        else { number = nil }
        return number.flatMap { $0 >= 0 ? $0 : nil }
    }

    static func constructorID(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let slug = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "_")
        let aliases = [
            "red_bull": "red_bull", "red_bull_racing": "red_bull", "oracle_red_bull_racing": "red_bull",
            "racing_bulls": "rb", "rb_f1_team": "rb", "visa_cash_app_racing_bulls": "rb",
            "alpine_f1_team": "alpine", "haas_f1_team": "haas", "cadillac_f1_team": "cadillac",
            "aston_martin_aramco": "aston_martin", "mercedes_amg_petronas": "mercedes"
        ]
        return slug.isEmpty ? nil : "f1:\(aliases[slug] ?? slug)"
    }

    static func referencedURL(_ object: Any?) -> URL? {
        guard let dictionary = object as? [String: Any],
              let ref = dictionary["$ref"] as? String,
              var components = URLComponents(string: ref),
              components.host == "sports.core.api.espn.com",
              components.path.hasPrefix("/v2/sports/racing/") else { return nil }
        components.scheme = "https"
        return components.url
    }

    static func statistic(_ object: [String: Any], named name: String) -> Int? {
        let source = object["splits"] as? [String: Any] ?? object
        for category in source["categories"] as? [[String: Any]] ?? [] {
            for stat in category["stats"] as? [[String: Any]] ?? [] where stat["name"] as? String == name {
                return integer(stat["value"] ?? stat["displayValue"])
            }
        }
        return nil
    }

    static func snapshot(
        selection: Selection, core: [String: Any], raceStatistics: [String: Any]?,
        driverStatuses: [String: [String: Any]], fetchedAt: Date, now: Date
    ) -> F1LiveSnapshot {
        let status = selection.competition["status"] as? [String: Any] ?? [:]
        let type = status["type"] as? [String: Any] ?? [:]
        let code = (selection.competition["type"] as? [String: Any])?["abbreviation"] as? String ?? "Session"
        let isRace = code == "Race" || code == "SR"
        let completed = type["completed"] as? Bool ?? false
        let live = type["state"] as? String == "in" && !completed
        let metadata = Dictionary(
            (core["competitors"] as? [[String: Any]] ?? []).compactMap { row -> (String, [String: Any])? in
                guard let id = row["id"] as? String else { return nil }
                return (id, row)
            }, uniquingKeysWith: { first, _ in first }
        )
        let drivers = (selection.competition["competitors"] as? [[String: Any]] ?? []).compactMap { row -> F1LiveDriver? in
            guard let id = row["id"] as? String, let athlete = row["athlete"] as? [String: Any],
                  let name = athlete["displayName"] as? String ?? athlete["fullName"] as? String else { return nil }
            let vehicle = metadata[id]?["vehicle"] as? [String: Any] ?? [:]
            let constructor = vehicle["manufacturer"] as? String
            let driverStatus = driverStatuses[id] ?? [:]
            let statusName = (driverStatus["type"] as? [String: Any])?["name"] as? String ?? ""
            let rawPosition = integer(row["order"])
            let number = vehicle["number"] as? String ?? (vehicle["number"] as? NSNumber)?.stringValue
            // Short names come from the provider; do not invent an official three-letter code.
            let abbreviation = athlete["abbreviation"] as? String ?? athlete["shortName"] as? String ?? name
            return F1LiveDriver(
                id: "espn:f1:\(id)", position: rawPosition.flatMap { $0 > 0 ? $0 : nil },
                number: number, name: name, abbreviation: abbreviation,
                constructorID: constructorID(constructor), constructorName: constructor,
                laps: isRace ? integer(driverStatus["period"]) : nil,
                gap: nil,
                isRetired: ["STATUS_RETIRED", "STATUS_DISQUALIFIED", "STATUS_DID_NOT_FINISH"].contains(statusName)
            )
        }.sorted { ($0.position ?? Int.max) < ($1.position ?? Int.max) }
        let sessionNames = ["FP1": "Practice 1", "FP2": "Practice 2", "FP3": "Practice 3", "Qual": "Qualifying", "SS": "Sprint Qualifying", "SR": "Sprint", "Race": "Race"]
        let links = selection.event["links"] as? [[String: Any]] ?? []
        let link = links.first { ($0["rel"] as? [String])?.contains("summary") == true } ?? links.first
        let lap = isRace && (live || completed) ? integer(status["period"]).flatMap { $0 > 0 ? $0 : nil } : nil
        let total = isRace ? raceStatistics.flatMap { statistic($0, named: "laps") }.flatMap { $0 > 0 ? $0 : nil } : nil
        return F1LiveSnapshot(
            id: "espn:f1:\(selection.sessionID)", eventID: selection.eventID, sessionID: selection.sessionID,
            title: selection.event["name"] as? String ?? "Formula 1", sessionTitle: sessionNames[code] ?? code,
            status: type["description"] as? String ?? type["shortDetail"] as? String ?? "Scheduled",
            isLive: live, isCompleted: completed, isStale: now.timeIntervalSince(fetchedAt) > 60,
            lap: lap, totalLaps: total, drivers: drivers,
            startDate: CommunitySportsDecoder.date(selection.competition["date"] as? String),
            providerUpdatedAt: CommunitySportsDecoder.date(core["lastUpdated"] as? String),
            fetchedAt: fetchedAt, sourceURL: CommunitySportsDecoder.webURL(link?["href"] as? String) ?? selection.competitionURL
        )
    }
}

@MainActor
final class F1LiveTimingClient {
    struct Response {
        let data: Data
        let fetchedAt: Date
    }
    private let session: URLSession
    private let now: () -> Date
    private var cache: [URL: Response] = [:]
    private var inFlight: [URL: Task<Response, Error>] = [:]

    init(session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func fetch(_ url: URL, ttl: TimeInterval) async throws -> Response {
        if let cached = cache[url], now().timeIntervalSince(cached.fetchedAt) < ttl { return cached }
        if let task = inFlight[url] { return try await task.value }
        let session = session
        let now = now
        let task = Task<Response, Error> {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Sapphire-F1Standings/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CommunitySportsError.invalidData }
            guard (200..<300).contains(http.statusCode) else { throw CommunitySportsError.http(http.statusCode) }
            guard data.count <= 8_000_000 else { throw CommunitySportsError.tooLarge }
            try Task.checkCancellation()
            return Response(data: data, fetchedAt: now())
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let response = try await task.value
        cache[url] = response
        if cache.count > 100 {
            for key in cache.sorted(by: { $0.value.fetchedAt < $1.value.fetchedAt }).prefix(cache.count - 100).map(\.key) {
                cache[key] = nil
            }
        }
        return response
    }

    func cancelRequests() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }
}

@MainActor
final class F1LiveTimingStore: ObservableObject {
    static let shared = F1LiveTimingStore()
    @Published private(set) var snapshot: F1LiveSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var availableDrivers: [F1LiveDriver] = []
    @Published private(set) var favoriteDriverIDs: Set<String>
    @Published private(set) var favoriteConstructorIDs: Set<String>
    @Published var isNotchEnabled: Bool {
        didSet { defaults.set(isNotchEnabled, forKey: "F1LiveTimingNotchEnabled") }
    }

    private let defaults: UserDefaults
    private let client: F1LiveTimingClient
    private let now: () -> Date
    private var generation = UUID()
    private var pollingTask: Task<Void, Never>?
    private var activeKey: String?
    private var attemptedAt: [String: Date] = [:]
    private var catalogFetchedAt: Date?
    private var catalogAttemptedAt: Date?

    init(session: URLSession = .shared, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.client = F1LiveTimingClient(session: session, now: now)
        self.now = now
        favoriteDriverIDs = Set(defaults.stringArray(forKey: "F1LiveFavoriteDriverIDs") ?? [])
        favoriteConstructorIDs = Set(defaults.stringArray(forKey: "F1LiveFavoriteConstructorIDs")
            ?? (defaults.stringArray(forKey: "CommunitySportsFavoriteTeamIDs") ?? []).filter { $0.hasPrefix("f1:") })
        isNotchEnabled = defaults.object(forKey: "F1LiveTimingNotchEnabled") as? Bool ?? true
    }

    func toggleFavorite(driver: F1LiveDriver) {
        if favoriteDriverIDs.contains(driver.id) { favoriteDriverIDs.remove(driver.id) }
        else { favoriteDriverIDs.insert(driver.id) }
        defaults.set(favoriteDriverIDs.sorted(), forKey: "F1LiveFavoriteDriverIDs")
    }

    func toggleFavoriteConstructor(id: String) {
        if favoriteConstructorIDs.contains(id) { favoriteConstructorIDs.remove(id) }
        else { favoriteConstructorIDs.insert(id) }
        defaults.set(favoriteConstructorIDs.sorted(), forKey: "F1LiveFavoriteConstructorIDs")
    }

    func isFavorite(driver: F1LiveDriver) -> Bool {
        favoriteDriverIDs.contains(driver.id) || driver.constructorID.map(favoriteConstructorIDs.contains) == true
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                let interval: TimeInterval = snapshot?.isLive == true ? 15 : 60
                do { try await Task.sleep(for: .seconds(interval)) }
                catch { return }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        generation = UUID()
        client.cancelRequests()
        isLoading = false
        activeKey = nil
    }

    func refresh(date: Date? = nil, force: Bool = false) async {
        updateStaleness()
        let key = date.map { CommunitySportsClient.dayString($0) } ?? "current"
        if activeKey == key, isLoading { return }
        // Even an explicit refresh cannot create a high-frequency request loop.
        if let attempted = attemptedAt[key], now().timeIntervalSince(attempted) < 15 { return }
        if isLoading { client.cancelRequests() }
        if activeKey != key { snapshot = nil; lastUpdated = nil }
        activeKey = key
        attemptedAt[key] = now()
        let token = UUID()
        generation = token
        isLoading = true
        errorMessage = nil
        defer { if generation == token { isLoading = false } }
        do {
            var components = URLComponents(string: "https://site.api.espn.com/apis/site/v2/sports/racing/f1/scoreboard")!
            if let date { components.queryItems = [URLQueryItem(name: "dates", value: CommunitySportsClient.dayString(date))] }
            let response = try await client.fetch(components.url!, ttl: 15)
            guard let selection = try F1LiveDecoder.select(response.data, now: now(), historical: date != nil) else {
                guard generation == token else { return }
                snapshot = nil
                lastUpdated = response.fetchedAt
                await loadDriverCatalog(token: token)
                return
            }
            let coreResponse = try await client.fetch(selection.competitionURL, ttl: 300)
            let core = try CommunitySportsDecoder.object(coreResponse.data)
            var statistics: [String: Any]?
            if let url = F1LiveDecoder.referencedURL(core["statistics"]),
               let result = try? await client.fetch(url, ttl: 3_600) {
                statistics = try? CommunitySportsDecoder.object(result.data)
            }
            var value = F1LiveDecoder.snapshot(
                selection: selection, core: core, raceStatistics: statistics,
                driverStatuses: [:], fetchedAt: response.fetchedAt, now: now()
            )
            let prioritized = value.drivers.sorted {
                if isFavorite(driver: $0) != isFavorite(driver: $1) { return isFavorite(driver: $0) }
                return ($0.position ?? Int.max) < ($1.position ?? Int.max)
            }.prefix(5)
            let competitors = core["competitors"] as? [[String: Any]] ?? []
            var statuses: [String: [String: Any]] = [:]
            for driver in prioritized {
                try Task.checkCancellation()
                let rawID = String(driver.id.split(separator: ":").last ?? "")
                guard let competitor = competitors.first(where: { $0["id"] as? String == rawID }),
                      let url = F1LiveDecoder.referencedURL(competitor["status"]),
                      let result = try? await client.fetch(url, ttl: 30),
                      let object = try? CommunitySportsDecoder.object(result.data) else { continue }
                statuses[rawID] = object
            }
            value = F1LiveDecoder.snapshot(
                selection: selection, core: core, raceStatistics: statistics,
                driverStatuses: statuses, fetchedAt: response.fetchedAt, now: now()
            )
            guard generation == token, !Task.isCancelled else { return }
            snapshot = value
            lastUpdated = response.fetchedAt
            if !value.drivers.isEmpty { availableDrivers = value.drivers }
            else { await loadDriverCatalog(token: token) }
        } catch is CancellationError {
            // A dismissed view or newer selection owns subsequent updates.
        } catch {
            guard generation == token else { return }
            errorMessage = snapshot == nil ? error.localizedDescription : "Showing the last update. \(error.localizedDescription)"
            updateStaleness()
        }
    }

    private func updateStaleness() {
        guard var current = snapshot else { return }
        let stale = now().timeIntervalSince(current.fetchedAt) > 60
        if current.isStale != stale { current.isStale = stale; snapshot = current }
    }

    private func loadDriverCatalog(token: UUID) async {
        if let fetched = catalogFetchedAt, now().timeIntervalSince(fetched) < 3_600 { return }
        if let attempted = catalogAttemptedAt, now().timeIntervalSince(attempted) < 60 { return }
        catalogAttemptedAt = now()
        do {
            let year = Calendar.current.component(.year, from: now())
            var raceDate: Date?
            for season in [year, year - 1] {
                let url = URL(string: "https://api.jolpi.ca/ergast/f1/\(season)/last/results/?limit=100&format=json")!
                let response = try await client.fetch(url, ttl: 3_600)
                raceDate = try CommunitySportsDecoder.racing(response.data).first?.startDate
                if raceDate != nil { break }
            }
            guard let raceDate else { return }
            let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/racing/f1/scoreboard?dates=\(CommunitySportsClient.dayString(raceDate))")!
            let response = try await client.fetch(url, ttl: 3_600)
            guard let selection = try F1LiveDecoder.select(response.data, now: now(), historical: true) else { return }
            let coreResponse = try await client.fetch(selection.competitionURL, ttl: 3_600)
            let core = try CommunitySportsDecoder.object(coreResponse.data)
            let value = F1LiveDecoder.snapshot(selection: selection, core: core, raceStatistics: nil, driverStatuses: [:], fetchedAt: response.fetchedAt, now: now())
            guard generation == token, !Task.isCancelled else { return }
            availableDrivers = value.drivers
            catalogFetchedAt = now()
        } catch {
            // The session is still valid when the optional off-weekend roster is unavailable.
        }
    }
}
