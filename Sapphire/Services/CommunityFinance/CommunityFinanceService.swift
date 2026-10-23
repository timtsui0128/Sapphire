import Combine
import Foundation

struct FinanceHistoryPoint: Identifiable, Codable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let price: Double
}

struct FinanceQuote: Codable, Equatable, Sendable {
    let symbol: String
    let price: Double
    let change: Double
    let changePercent: Double
    let name: String
    let isAfterHours: Bool
    var currency: String = ""
    var exchange: String = ""
    var quotedAt: Date? = nil
    var fetchedAt: Date = .distantPast
    var marketState: String = "Session unavailable"
    var source: String = "Yahoo Finance"
    var history: [FinanceHistoryPoint] = []
    var hasChange: Bool = true
    var isDailyClose: Bool = false
    var pricePrecision: Int = 2
    var exchangeTimezone: String = "UTC"

    var priceText: String {
        let value = Self.number(price, digits: pricePrecision)
        return currency.isEmpty ? value : "\(value) \(currency)"
    }

    var changeText: String {
        hasChange ? Self.signed(change, digits: pricePrecision) : "—"
    }

    var changePercentText: String {
        hasChange ? "\(Self.signed(changePercent, digits: 2))%" : "—"
    }

    var timestampText: String {
        guard let quotedAt else { return "Quote time unavailable" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: exchangeTimezone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = isDailyClose ? "d MMM yyyy" : "d MMM yyyy, HH:mm z"
        return formatter.string(from: quotedAt)
    }

    var providerURL: URL? {
        var url = URLComponents(string: "https://finance.yahoo.com")
        url?.path = "/quote/\(symbol)/"
        return url?.url
    }

    static func number(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = max(0, min(digits, 4))
        formatter.maximumFractionDigits = max(0, min(digits, 4))
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    private static func signed(_ value: Double, digits: Int) -> String {
        (value > 0 ? "+" : "") + number(value, digits: digits)
    }
}

struct CommunityFinanceSearchResult: Identifiable, Equatable, Sendable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let exchange: String
}

enum CommunityFinanceError: LocalizedError {
    case invalidSymbol, invalidData, http(Int), unavailable(String), watchlistFull
    var errorDescription: String? {
        switch self {
        case .invalidSymbol: return "Enter a stock symbol such as AAPL, 0700.HK, or VOD.L."
        case .invalidData: return "The quote provider did not return a valid price and timestamp."
        case .http(429): return "The quote provider is busy. Try again shortly."
        case .http(let code): return "The quote provider is unavailable (HTTP \(code))."
        case .unavailable(let message): return message
        case .watchlistFull: return "You can follow up to 25 symbols."
        }
    }
}

enum CommunityFinanceDecoder {
    static func symbol(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !value.isEmpty, value.count <= 32,
              value.range(of: "^[A-Z0-9^][A-Z0-9.^=-]*$", options: .regularExpression) != nil else { return nil }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let result = value.doubleValue
        return result.isFinite ? result : nil
    }

    static func yahoo(_ data: Data, requestedSymbol: String, now: Date = Date()) throws -> FinanceQuote {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]], let result = results.first,
              let meta = result["meta"] as? [String: Any],
              let receivedSymbol = meta["symbol"] as? String,
              symbol(receivedSymbol) == symbol(requestedSymbol),
              let price = number(meta["regularMarketPrice"]), price > 0,
              let timestamp = number(meta["regularMarketTime"]), timestamp > 0,
              let currency = meta["currency"] as? String, !currency.isEmpty else {
            throw CommunityFinanceError.invalidData
        }
        let quoteDate = Date(timeIntervalSince1970: timestamp)
        guard quoteDate <= now.addingTimeInterval(300) else { throw CommunityFinanceError.invalidData }
        let timezone = meta["exchangeTimezoneName"] as? String ?? "UTC"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)!
        let timestamps = result["timestamp"] as? [Any] ?? []
        let indicators = result["indicators"] as? [String: Any]
        let indicatorQuotes = indicators?["quote"] as? [[String: Any]]
        let closes = indicatorQuotes?.first?["close"] as? [Any] ?? []
        var history: [FinanceHistoryPoint] = []
        var seen: Set<Date> = []
        for (time, close) in zip(timestamps, closes) {
            guard let time = number(time), let close = number(close), close > 0 else { continue }
            let date = Date(timeIntervalSince1970: time)
            guard date <= now.addingTimeInterval(300), seen.insert(date).inserted else { continue }
            history.append(FinanceHistoryPoint(date: date, price: close))
        }
        history.sort { $0.date < $1.date }
        // chartPreviousClose is the close before the requested RANGE, not yesterday's close.
        // Prefer explicit daily baselines; otherwise select the preceding exchange-local date.
        let priorDay = history.last {
            calendar.startOfDay(for: $0.date) < calendar.startOfDay(for: quoteDate)
        }?.price
        let explicitPrevious = number(meta["regularMarketPreviousClose"]) ?? number(meta["previousClose"])
        let previous = explicitPrevious ?? priorDay
        let change: Double
        let percent: Double
        let hasChange: Bool
        if let previous, previous > 0 {
            change = price - previous
            percent = change / previous * 100
            hasChange = true
        } else {
            change = 0
            percent = 0
            hasChange = false
        }
        let periods = meta["currentTradingPeriod"] as? [String: Any] ?? [:]
        func inPeriod(_ key: String) -> Bool {
            guard let period = periods[key] as? [String: Any],
                  let start = number(period["start"]), let end = number(period["end"]) else { return false }
            return now.timeIntervalSince1970 >= start && now.timeIntervalSince1970 < end
        }
        let state: String
        if inPeriod("regular") { state = "Regular session" }
        else if inPeriod("pre") { state = "Pre-market" }
        else if inPeriod("post") { state = "After-hours" }
        else { state = periods.isEmpty ? "Session unavailable" : "Market closed" }
        return FinanceQuote(
            symbol: symbol(receivedSymbol)!, price: price, change: change, changePercent: percent,
            name: meta["longName"] as? String ?? meta["shortName"] as? String ?? receivedSymbol,
            isAfterHours: state != "Regular session", currency: currency,
            exchange: meta["fullExchangeName"] as? String ?? meta["exchangeName"] as? String ?? "Exchange unavailable",
            quotedAt: quoteDate, fetchedAt: now, marketState: state,
            history: Array(history.suffix(32)), hasChange: hasChange,
            pricePrecision: min(4, max(2, (meta["priceHint"] as? Int) ?? 2)),
            exchangeTimezone: timezone
        )
    }

    static func search(_ data: Data) throws -> [CommunityFinanceSearchResult] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = root["quotes"] as? [[String: Any]] else { throw CommunityFinanceError.invalidData }
        var seen: Set<String> = []
        return quotes.compactMap { quote in
            guard let raw = quote["symbol"] as? String, let symbol = symbol(raw),
                  ["EQUITY", "ETF", "INDEX"].contains(quote["quoteType"] as? String ?? ""),
                  seen.insert(symbol).inserted else { return nil }
            return CommunityFinanceSearchResult(
                symbol: symbol, name: quote["longname"] as? String ?? quote["shortname"] as? String ?? symbol,
                exchange: quote["exchDisp"] as? String ?? quote["exchange"] as? String ?? ""
            )
        }
    }

    /// Only unqualified US equities have an unambiguous fallback currency mapping.
    static func stooqSymbol(_ symbol: String) -> String? {
        guard symbol.range(of: "^[A-Z][A-Z0-9-]*$", options: .regularExpression) != nil else { return nil }
        return symbol.lowercased() + ".us"
    }

    static func stooq(_ data: Data, symbol: String, now: Date = Date()) throws -> FinanceQuote {
        guard stooqSymbol(symbol) != nil, let text = String(data: data, encoding: .utf8) else {
            throw CommunityFinanceError.invalidData
        }
        let rows = text.split(whereSeparator: \.isNewline)
        guard rows.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "Date,Open,High,Low,Close,Volume" else {
            throw CommunityFinanceError.invalidData
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var values: [Date: Double] = [:]
        for row in rows.dropFirst() {
            let fields = row.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 5, let date = formatter.date(from: String(fields[0])),
                  date <= now, let price = Double(fields[4]), price.isFinite, price > 0 else { continue }
            values[date] = price
        }
        let history = values.map { FinanceHistoryPoint(date: $0.key, price: $0.value) }.sorted { $0.date < $1.date }
        guard let latest = history.last else { throw CommunityFinanceError.invalidData }
        let previous = history.dropLast().last?.price
        let change = previous.map { latest.price - $0 } ?? 0
        return FinanceQuote(
            symbol: symbol, price: latest.price, change: change,
            changePercent: previous.map { change / $0 * 100 } ?? 0, name: symbol, isAfterHours: true,
            currency: "USD", exchange: "US market", quotedAt: latest.date, fetchedAt: now,
            marketState: "Daily close", source: "Stooq", history: Array(history.suffix(32)),
            hasChange: previous != nil, isDailyClose: true, exchangeTimezone: "UTC"
        )
    }
}

struct CommunityFinanceClient: Sendable {
    typealias Transport = @Sendable (URL) async throws -> Data
    static let shared = CommunityFinanceClient()
    private let transport: Transport

    init(transport: @escaping Transport = { try await CommunityFinanceClient.load($0) }) {
        self.transport = transport
    }

    func quote(symbol raw: String) async throws -> FinanceQuote {
        guard let symbol = CommunityFinanceDecoder.symbol(raw) else { throw CommunityFinanceError.invalidSymbol }
        let url = try Self.url(host: "query1.finance.yahoo.com", path: "/v8/finance/chart/\(symbol)",
                               query: ["interval": "1d", "range": "1mo"])
        do {
            return try CommunityFinanceDecoder.yahoo(await transport(url), requestedSymbol: symbol)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            guard let fallback = CommunityFinanceDecoder.stooqSymbol(symbol) else { throw error }
            let yahooError = error
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dateFormatter.dateFormat = "yyyyMMdd"
            let now = Date()
            let dailyURL = try Self.url(host: "stooq.com", path: "/q/d/l/", query: [
                "s": fallback, "i": "d", "d1": dateFormatter.string(from: now.addingTimeInterval(-45 * 86400)),
                "d2": dateFormatter.string(from: now)
            ])
            do {
                return try CommunityFinanceDecoder.stooq(await transport(dailyURL), symbol: symbol)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw CommunityFinanceError.unavailable(
                    "\(yahooError.localizedDescription) The daily fallback is also unavailable."
                )
            }
        }
    }

    func search(_ query: String) async throws -> [CommunityFinanceSearchResult] {
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !query.isEmpty else { return [] }
        let url = try Self.url(host: "query1.finance.yahoo.com", path: "/v1/finance/search",
                               query: ["q": query, "quotesCount": "8", "newsCount": "0"])
        return try CommunityFinanceDecoder.search(await transport(url))
    }

    private static func url(host: String, path: String, query: [String: String]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw CommunityFinanceError.invalidSymbol }
        return url
    }

    static func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Sapphire/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommunityFinanceError.invalidData }
        guard (200...299).contains(http.statusCode) else { throw CommunityFinanceError.http(http.statusCode) }
        guard data.count <= 2_000_000 else { throw CommunityFinanceError.invalidData }
        return data
    }
}

@MainActor
final class CommunityFinanceStore: ObservableObject {
    static let shared = CommunityFinanceStore()
    @Published private(set) var watchlist: [String]
    @Published private(set) var quotes: [String: FinanceQuote]
    @Published private(set) var isLoading = false
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var searchError: String?
    @Published private(set) var addError: String?
    @Published var selectedSymbol: String {
        didSet { defaults.set(selectedSymbol, forKey: Self.selectionKey) }
    }
    private let defaults: UserDefaults
    private let client: CommunityFinanceClient
    private var lastAttempt: [String: Date] = [:]
    private var pending: [String: Task<FinanceQuote, Error>] = [:]
    private static let watchlistKey = "CommunityFinanceWatchlist"
    private static let selectionKey = "CommunityFinanceSelectedSymbol"
    private static let cacheKey = "CommunityFinanceQuotesV1"

    init(defaults: UserDefaults = .standard, client: CommunityFinanceClient = .shared) {
        self.defaults = defaults
        self.client = client
        let stored = defaults.stringArray(forKey: Self.watchlistKey) ?? ["AAPL", "MSFT", "NVDA"]
        var seen: Set<String> = []
        let symbols = stored.compactMap(CommunityFinanceDecoder.symbol).filter { seen.insert($0).inserted }
        let initialWatchlist = Array(symbols.prefix(25))
        watchlist = initialWatchlist
        let savedSelection = defaults.string(forKey: Self.selectionKey) ?? ""
        selectedSymbol = initialWatchlist.contains(savedSelection) ? savedSelection : initialWatchlist.first ?? ""
        if let data = defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode([String: FinanceQuote].self, from: data) {
            quotes = cached.filter {
                $0.key == $0.value.symbol && $0.value.price.isFinite && $0.value.price > 0
                    && $0.value.quotedAt != nil && initialWatchlist.contains($0.key)
            }
        } else { quotes = [:] }
    }

    func isCached(symbol: String, now: Date = Date()) -> Bool {
        guard let quote = quotes[symbol] else { return false }
        let allowedQuoteAge: TimeInterval = quote.isAfterHours ? 7 * 86400 : 20 * 60
        return errors[symbol] != nil || now.timeIntervalSince(quote.fetchedAt) > 180
            || quote.quotedAt.map { now.timeIntervalSince($0) > allowedQuoteAge } != false
    }

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        // Bound concurrent requests so opening a long watchlist does not burst the provider.
        let symbols = watchlist
        for start in stride(from: 0, to: symbols.count, by: 3) {
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                for symbol in symbols[start..<min(start + 3, symbols.count)] {
                    group.addTask { @MainActor in _ = await self.fetch(symbol: symbol, force: force) }
                }
            }
        }
    }

    @discardableResult
    func fetch(symbol raw: String, force: Bool = false) async -> FinanceQuote? {
        guard let symbol = CommunityFinanceDecoder.symbol(raw) else { return nil }
        if let task = pending[symbol] { return try? await task.value }
        if !force, let attempted = lastAttempt[symbol], Date().timeIntervalSince(attempted) < 60 {
            return quotes[symbol]
        }
        lastAttempt[symbol] = Date()
        let task = Task { [client] in try await client.quote(symbol: symbol) }
        pending[symbol] = task
        defer { pending[symbol] = nil }
        do {
            let quote = try await task.value
            quotes[symbol] = quote
            errors[symbol] = nil
            saveCache()
            return quote
        } catch {
            if !(error is CancellationError) { errors[symbol] = error.localizedDescription }
            return quotes[symbol]
        }
    }

    @discardableResult
    func add(symbol raw: String) async -> Bool {
        addError = nil
        guard let symbol = CommunityFinanceDecoder.symbol(raw) else {
            addError = CommunityFinanceError.invalidSymbol.localizedDescription
            return false
        }
        if watchlist.contains(symbol) { selectedSymbol = symbol; return true }
        guard watchlist.count < 25 else {
            addError = CommunityFinanceError.watchlistFull.localizedDescription
            return false
        }
        guard let quote = await fetch(symbol: symbol, force: true), errors[symbol] == nil else {
            addError = errors[symbol] ?? "No quote was found for \(symbol)."
            return false
        }
        // An add can overlap another add while awaiting the provider.
        guard watchlist.count < 25 else {
            addError = CommunityFinanceError.watchlistFull.localizedDescription
            return false
        }
        if !watchlist.contains(symbol) { watchlist.append(quote.symbol) }
        selectedSymbol = quote.symbol
        saveWatchlist()
        return true
    }

    func remove(symbol: String) {
        watchlist.removeAll { $0 == symbol }
        errors[symbol] = nil
        if selectedSymbol == symbol { selectedSymbol = watchlist.first ?? "" }
        saveWatchlist()
    }

    func search(_ query: String) async -> [CommunityFinanceSearchResult] {
        searchError = nil
        do { return try await client.search(query) }
        catch {
            if !(error is CancellationError) && !Task.isCancelled {
                searchError = "Search is unavailable. You can still enter an exact symbol. \(error.localizedDescription)"
            }
            return []
        }
    }

    private func saveWatchlist() {
        defaults.set(watchlist, forKey: Self.watchlistKey)
        saveCache()
    }

    private func saveCache() {
        let saved = quotes.filter { watchlist.contains($0.key) }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.cacheKey) }
    }
}
