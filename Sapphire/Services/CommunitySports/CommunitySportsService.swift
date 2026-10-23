import Combine
import Foundation

enum CommunitySportsLeague: String, CaseIterable, Identifiable, Codable, Sendable {
    case f1, premierLeague, championsLeague, laLiga, serieA, bundesliga, ligue1, mls

    var id: String { rawValue }
    var title: String {
        switch self {
        case .f1: return "Formula 1"
        case .premierLeague: return "Premier League"
        case .championsLeague: return "Champions League"
        case .laLiga: return "La Liga"
        case .serieA: return "Serie A"
        case .bundesliga: return "Bundesliga"
        case .ligue1: return "Ligue 1"
        case .mls: return "MLS"
        }
    }
    var symbol: String { isRacing ? "flag.checkered" : "soccerball" }
    var isRacing: Bool { self == .f1 }
    var route: String? {
        switch self {
        case .f1: return nil
        case .premierLeague: return "eng.1"
        case .championsLeague: return "uefa.champions"
        case .laLiga: return "esp.1"
        case .serieA: return "ita.1"
        case .bundesliga: return "ger.1"
        case .ligue1: return "fra.1"
        case .mls: return "usa.1"
        }
    }
}

struct CommunitySportsTeam: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let shortName: String
    var logoURL: URL? = nil
}

struct CommunitySportsResult: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let position: Int
    let name: String
    let team: String
    let detail: String
    var teamID: String? = nil
}

struct CommunitySportsEvent: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    var startDate: Date? = nil
    var status: String
    var isLive: Bool = false
    var isComplete: Bool = false
    var homeTeam: CommunitySportsTeam? = nil
    var awayTeam: CommunitySportsTeam? = nil
    var homeScore: String? = nil
    var awayScore: String? = nil
    var detail: String? = nil
    var results: [CommunitySportsResult] = []
    var linkURL: URL? = nil
}

enum CommunitySportsError: LocalizedError {
    case invalidData, http(Int), tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidData: return "The score provider returned an unreadable response."
        case .http(429): return "The score provider is busy. Please try again shortly."
        case .http(let code): return "The score provider is unavailable (HTTP \(code))."
        case .tooLarge: return "The score provider returned an unexpectedly large response."
        }
    }
}

/// Decoders use only published fields; absent scores and classifications stay absent.
enum CommunitySportsDecoder {
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd"] {
            fallback.dateFormat = format
            if let date = fallback.date(from: value) { return date }
        }
        return nil
    }

    static func webURL(_ value: String?) -> URL? {
        guard let value, var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme), components.host != nil else { return nil }
        // Both providers expose a mixture of older HTTP and current HTTPS links.
        components.scheme = "https"
        return components.url
    }

    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CommunitySportsError.invalidData
        }
        return value
    }

    static func footballTeam(_ object: [String: Any]) -> CommunitySportsTeam? {
        guard let id = object["id"] as? String, !id.isEmpty,
              let name = object["displayName"] as? String, !name.isEmpty else { return nil }
        let logos = object["logos"] as? [[String: Any]]
        return CommunitySportsTeam(
            id: "soccer:\(id)", name: name,
            shortName: object["abbreviation"] as? String ?? object["shortDisplayName"] as? String ?? name,
            logoURL: webURL(object["logo"] as? String ?? logos?.first?["href"] as? String)
        )
    }

    static func football(_ data: Data, league: CommunitySportsLeague) throws -> [CommunitySportsEvent] {
        let root = try object(data)
        guard let rows = root["events"] as? [[String: Any]] else { throw CommunitySportsError.invalidData }
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let competition = (row["competitions"] as? [[String: Any]])?.first,
                  let competitors = competition["competitors"] as? [[String: Any]],
                  let home = competitors.first(where: { $0["homeAway"] as? String == "home" }),
                  let away = competitors.first(where: { $0["homeAway"] as? String == "away" }),
                  let homeObject = home["team"] as? [String: Any],
                  let awayObject = away["team"] as? [String: Any],
                  let homeTeam = footballTeam(homeObject), let awayTeam = footballTeam(awayObject) else { return nil }
            let status = competition["status"] as? [String: Any] ?? row["status"] as? [String: Any] ?? [:]
            let type = status["type"] as? [String: Any] ?? [:]
            let state = type["state"] as? String ?? "pre"
            let complete = type["completed"] as? Bool ?? false
            let live = state == "in" && !complete
            let links = row["links"] as? [[String: Any]] ?? []
            let gameLink = links.first(where: { ($0["rel"] as? [String])?.contains("summary") == true }) ?? links.first
            let description = type["shortDetail"] as? String ?? type["description"] as? String ?? "Scheduled"
            let clock = status["displayClock"] as? String
            let detail = live ? clock : (competition["venue"] as? [String: Any])?["fullName"] as? String
            func score(_ value: Any?) -> String? {
                if let string = value as? String { return string }
                if let number = value as? NSNumber { return number.stringValue }
                return nil
            }
            return CommunitySportsEvent(
                id: "espn:\(league.route ?? league.rawValue):\(id)",
                title: "\(awayTeam.name) at \(homeTeam.name)",
                startDate: date(row["date"] as? String),
                status: description, isLive: live, isComplete: complete,
                homeTeam: homeTeam, awayTeam: awayTeam,
                homeScore: live || complete ? score(home["score"]) : nil,
                awayScore: live || complete ? score(away["score"]) : nil,
                detail: detail, linkURL: webURL(gameLink?["href"] as? String)
            )
        }
    }

    static func footballTeams(_ data: Data) throws -> [CommunitySportsTeam] {
        let root = try object(data)
        guard let sports = root["sports"] as? [[String: Any]],
              let leagues = sports.first?["leagues"] as? [[String: Any]],
              let rows = leagues.first?["teams"] as? [[String: Any]] else { throw CommunitySportsError.invalidData }
        return rows.compactMap { ($0["team"] as? [String: Any]).flatMap(footballTeam) }
    }

    static func racing(_ data: Data, now: Date = Date()) throws -> [CommunitySportsEvent] {
        let root = try object(data)
        guard let metadata = root["MRData"] as? [String: Any],
              let table = metadata["RaceTable"] as? [String: Any],
              let races = table["Races"] as? [[String: Any]] else { throw CommunitySportsError.invalidData }
        return races.compactMap { race in
            guard let season = race["season"] as? String, let round = race["round"] as? String,
                  let name = race["raceName"] as? String else { return nil }
            let dateString = race["date"] as? String
            let timestamp = dateString.map { $0 + "T" + (race["time"] as? String ?? "00:00:00Z") }
            let startDate = date(timestamp)
            let circuit = race["Circuit"] as? [String: Any] ?? [:]
            let results = (race["Results"] as? [[String: Any]] ?? []).compactMap { result -> CommunitySportsResult? in
                guard let driver = result["Driver"] as? [String: Any],
                      let id = driver["driverId"] as? String,
                      let position = (result["position"] as? String).flatMap(Int.init) else { return nil }
                let constructor = result["Constructor"] as? [String: Any] ?? [:]
                let fullName = [driver["givenName"], driver["familyName"]].compactMap { $0 as? String }.joined(separator: " ")
                let time = (result["Time"] as? [String: Any])?["time"] as? String
                let status = result["status"] as? String
                let points = (result["points"] as? String).map { "\($0) pts" }
                return CommunitySportsResult(
                    id: "f1:\(season):\(round):\(id)", position: position, name: fullName,
                    team: constructor["name"] as? String ?? "",
                    detail: [time ?? status, points].compactMap { $0 }.joined(separator: " · "),
                    teamID: (constructor["constructorId"] as? String).map { "f1:\($0)" }
                )
            }.sorted { $0.position < $1.position }
            let status: String
            if !results.isEmpty { status = "Final" }
            else if let startDate, startDate < now { status = "Results not loaded" }
            else { status = "Scheduled" }
            return CommunitySportsEvent(
                id: "f1:\(season):\(round)", title: name, startDate: startDate,
                status: status, isLive: false, isComplete: !results.isEmpty,
                detail: circuit["circuitName"] as? String,
                results: results, linkURL: webURL(race["url"] as? String)
            )
        }
    }

    static func racingTeams(_ data: Data) throws -> [CommunitySportsTeam] {
        let root = try object(data)
        guard let metadata = root["MRData"] as? [String: Any],
              let table = metadata["ConstructorTable"] as? [String: Any],
              let constructors = table["Constructors"] as? [[String: Any]] else { throw CommunitySportsError.invalidData }
        return constructors.compactMap {
            guard let id = $0["constructorId"] as? String, let name = $0["name"] as? String else { return nil }
            return CommunitySportsTeam(id: "f1:\(id)", name: name, shortName: name)
        }
    }
}

/// One cache and one in-flight request per URL, shared by the browser and notch adapter.
@MainActor
final class CommunitySportsClient {
    static let shared = CommunitySportsClient()
    private let session: URLSession
    private var cache: [URL: (data: Data, date: Date)] = [:]
    private var inFlight: [URL: Task<Data, Error>] = [:]

    init(session: URLSession = .shared) { self.session = session }

    func data(from url: URL, ttl: TimeInterval, force: Bool = false) async throws -> Data {
        if let cached = cache[url], Date().timeIntervalSince(cached.date) < (force ? min(ttl, 15) : ttl) {
            return cached.data
        }
        if let task = inFlight[url] { return try await task.value }
        let session = session
        let task = Task<Data, Error> {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Sapphire-CommunitySports/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CommunitySportsError.invalidData }
            guard (200..<300).contains(http.statusCode) else { throw CommunitySportsError.http(http.statusCode) }
            guard data.count <= 8_000_000 else { throw CommunitySportsError.tooLarge }
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let data = try await task.value
        cache[url] = (data, Date())
        if cache.count > 80 {
            for key in cache.sorted(by: { $0.value.date < $1.value.date }).prefix(cache.count - 80).map(\.key) {
                cache[key] = nil
            }
        }
        return data
    }

    static func dayString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    func football(league: CommunitySportsLeague, date: Date, force: Bool = false) async throws -> [CommunitySportsEvent] {
        guard let route = league.route else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let before = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let after = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        // ESPN's soccer feed accepts individual dates, but rejects date ranges.
        // Adjacent days cover the provider's day boundary; timestamps decide the local day.
        let rows = try await withThrowingTaskGroup(of: [CommunitySportsEvent].self) { group in
            for day in [before, start, after] {
                var components = URLComponents(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(route)/scoreboard")!
                components.queryItems = [
                    URLQueryItem(name: "dates", value: Self.dayString(day)),
                    URLQueryItem(name: "limit", value: "200")
                ]
                let url = components.url!
                group.addTask { @MainActor [self] in
                    let response = try await data(from: url, ttl: 30, force: force)
                    return try CommunitySportsDecoder.football(response, league: league)
                }
            }
            var events: [String: CommunitySportsEvent] = [:]
            for try await rows in group {
                for event in rows { events[event.id] = event }
            }
            return Array(events.values)
        }
        return rows
            .filter { $0.startDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    func footballTeams(league: CommunitySportsLeague, force: Bool = false) async throws -> [CommunitySportsTeam] {
        guard let route = league.route else { return [] }
        let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(route)/teams?limit=100")!
        return try CommunitySportsDecoder.footballTeams(await data(from: url, ttl: 86_400, force: force))
    }

    func racing(year: Int, round: String? = nil, force: Bool = false) async throws -> [CommunitySportsEvent] {
        let suffix = round.map { "\($0)/results/" } ?? ""
        let url = URL(string: "https://api.jolpi.ca/ergast/f1/\(year)/\(suffix)?limit=100&format=json")!
        return try CommunitySportsDecoder.racing(await data(from: url, ttl: round == nil ? 21_600 : 300, force: force))
    }

    func racingTeams(year: Int) async throws -> [CommunitySportsTeam] {
        let url = URL(string: "https://api.jolpi.ca/ergast/f1/\(year)/constructors/?limit=100&format=json")!
        return try CommunitySportsDecoder.racingTeams(await data(from: url, ttl: 21_600))
    }
}

@MainActor
final class CommunitySportsStore: ObservableObject {
    static let shared = CommunitySportsStore(client: .shared)
    @Published var selectedLeague: CommunitySportsLeague {
        didSet {
            guard oldValue != selectedLeague else { return }
            defaults.set(selectedLeague.rawValue, forKey: Self.leagueKey)
            clearSelection()
        }
    }
    @Published var selectedDate: Date {
        didSet {
            if !Calendar.current.isDate(oldValue, inSameDayAs: selectedDate) { clearSelection() }
        }
    }
    @Published private(set) var events: [CommunitySportsEvent] = []
    @Published private(set) var teams: [CommunitySportsTeam] = []
    @Published private(set) var favoriteTeamIDs: Set<String>
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private static let favoritesKey = "CommunitySportsFavoriteTeamIDs"
    private static let leagueKey = "CommunitySportsSelectedLeague"
    private let client: CommunitySportsClient
    private let defaults: UserDefaults
    private let storageURL: URL?
    private var generation = UUID()
    private var snapshots: [String: Snapshot] = [:]

    private struct Snapshot: Codable {
        let events: [CommunitySportsEvent]
        let teams: [CommunitySportsTeam]
        let updated: Date
    }

    convenience init(session: URLSession = .shared, defaults: UserDefaults = .standard, storageURL: URL? = nil) {
        self.init(client: CommunitySportsClient(session: session), defaults: defaults, storageURL: storageURL)
    }

    init(client: CommunitySportsClient, defaults: UserDefaults = .standard, storageURL: URL? = nil) {
        self.client = client
        self.defaults = defaults
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sapphire/CommunitySports/snapshots.json")
        selectedLeague = defaults.string(forKey: Self.leagueKey).flatMap(CommunitySportsLeague.init(rawValue:)) ?? .f1
        selectedDate = Date()
        favoriteTeamIDs = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
        if let url = self.storageURL, let data = try? Data(contentsOf: url), data.count < 4_000_000,
           let decoded = try? JSONDecoder().decode([String: Snapshot].self, from: data) {
            snapshots = decoded
        }
    }

    func toggleFavorite(_ team: CommunitySportsTeam) {
        if favoriteTeamIDs.contains(team.id) { favoriteTeamIDs.remove(team.id) }
        else { favoriteTeamIDs.insert(team.id) }
        defaults.set(favoriteTeamIDs.sorted(), forKey: Self.favoritesKey)
    }

    func isFavorite(_ event: CommunitySportsEvent) -> Bool {
        [event.homeTeam?.id, event.awayTeam?.id].compactMap { $0 }.contains(where: favoriteTeamIDs.contains)
            || event.results.contains { $0.teamID.map(favoriteTeamIDs.contains) == true }
    }

    private func clearSelection() {
        generation = UUID()
        events = []
        teams = []
        errorMessage = nil
        lastUpdated = nil
        isLoading = false
    }

    func load(force: Bool = false) async {
        let league = selectedLeague
        let date = selectedDate
        let key = "\(league.rawValue):\(CommunitySportsClient.dayString(date))"
        let token = UUID()
        generation = token
        isLoading = true
        errorMessage = nil
        if let snapshot = snapshots[key] {
            events = snapshot.events
            teams = snapshot.teams
            lastUpdated = snapshot.updated
        }
        let previousEvents = events
        defer { if generation == token { isLoading = false } }
        do {
            var loadedEvents: [CommunitySportsEvent]
            var loadedTeams: [CommunitySportsTeam]
            var warning: String?
            if league.isRacing {
                let year = Calendar.current.component(.year, from: date)
                loadedEvents = try await client.racing(year: year, force: force)
                // Keep classifications opened earlier when refreshing the calendar.
                loadedEvents = loadedEvents.map { event in
                    previousEvents.first(where: { $0.id == event.id && !$0.results.isEmpty }) ?? event
                }
                loadedTeams = (try? await client.racingTeams(year: year)) ?? []
                // Fetch the selected past race and the last published classification, not every round.
                let selected = loadedEvents.first { $0.startDate.map { Calendar.current.isDate($0, inSameDayAs: date) } == true }
                var rounds = ["last"]
                if let selected, let start = selected.startDate, start <= Date(),
                   let round = selected.id.split(separator: ":").last { rounds.append(String(round)) }
                for round in rounds {
                    do {
                        let results = try await client.racing(year: year, round: round, force: force)
                        for race in results where !race.results.isEmpty {
                            if let index = loadedEvents.firstIndex(where: { $0.id == race.id }) { loadedEvents[index] = race }
                        }
                    } catch { warning = "The calendar is available, but race results could not be refreshed." }
                }
            } else {
                loadedEvents = try await client.football(league: league, date: date, force: force)
                do { loadedTeams = try await client.footballTeams(league: league) }
                catch {
                    loadedTeams = loadedEvents.flatMap { [$0.homeTeam, $0.awayTeam].compactMap { $0 } }
                    warning = "Scores are available, but the full team list could not be refreshed."
                }
            }
            guard generation == token else { return }
            loadedTeams = Array(Set(loadedTeams)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            events = loadedEvents.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            teams = loadedTeams
            lastUpdated = Date()
            errorMessage = warning
            snapshots[key] = Snapshot(events: events, teams: teams, updated: lastUpdated!)
            persistSnapshots()
        } catch {
            guard generation == token else { return }
            errorMessage = events.isEmpty ? error.localizedDescription : "Showing saved scores. \(error.localizedDescription)"
        }
    }

    func loadResults(for event: CommunitySportsEvent) async {
        let parts = event.id.split(separator: ":")
        guard selectedLeague.isRacing, parts.count == 3, parts[0] == "f1",
              let year = Int(parts[1]), let start = event.startDate, start <= Date() else { return }
        let token = generation
        do {
            let results = try await client.racing(year: year, round: String(parts[2]))
            guard generation == token, let race = results.first,
                  let index = events.firstIndex(where: { $0.id == race.id }) else { return }
            events[index] = race
            errorMessage = race.results.isEmpty ? "Race results have not been published yet." : nil
            let key = "\(selectedLeague.rawValue):\(CommunitySportsClient.dayString(selectedDate))"
            snapshots[key] = Snapshot(events: events, teams: teams, updated: lastUpdated ?? Date())
            persistSnapshots()
        } catch {
            if generation == token { errorMessage = error.localizedDescription }
        }
    }

    private func persistSnapshots() {
        if snapshots.count > 24 {
            for key in snapshots.sorted(by: { $0.value.updated < $1.value.updated }).prefix(snapshots.count - 24).map(\.key) {
                snapshots[key] = nil
            }
        }
        guard let storageURL, let data = try? JSONEncoder().encode(snapshots) else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // A read-only cache directory does not prevent using current scores.
        }
    }
}
