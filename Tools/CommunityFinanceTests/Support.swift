import Foundation

// The focused checks compile the production adapter without the rest of Sapphire's models.
struct FinancePayload {
    let symbol: String
    let price: String
    let change: String
    let changePercent: String
    let isPositive: Bool
    let name: String
    let isAfterHours: Bool
    let closingPrice: String?
}

enum FinanceFixtures {
    static func yahoo(
        symbol: String = "AAPL", currency: String = "USD", now: Date = Date(),
        withPrevious: Bool = true, withPrice: Bool = true, withCurrency: Bool = true
    ) throws -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let today = calendar.startOfDay(for: now)
        let yesterday = today.addingTimeInterval(-86400)
        var meta: [String: Any] = [
            "symbol": symbol, "regularMarketTime": now.timeIntervalSince1970,
            "longName": symbol == "AAPL" ? "Apple Inc." : symbol,
            "fullExchangeName": symbol.hasSuffix(".L") ? "LSE" : "NasdaqGS",
            "exchangeTimezoneName": "America/New_York",
            "chartPreviousClose": 50, "priceHint": 2,
            "currentTradingPeriod": [
                "regular": ["start": now.addingTimeInterval(-3600).timeIntervalSince1970,
                            "end": now.addingTimeInterval(3600).timeIntervalSince1970]
            ]
        ]
        if withPrice { meta["regularMarketPrice"] = 110 }
        if withCurrency { meta["currency"] = currency }
        let dates: [Double] = withPrevious
            ? [yesterday.timeIntervalSince1970, today.timeIntervalSince1970]
            : [today.timeIntervalSince1970]
        let closes: [Any] = withPrevious ? [105, NSNull()] : [NSNull()]
        let result: [String: Any] = [
            "meta": meta, "timestamp": dates,
            "indicators": ["quote": [["close": closes]]]
        ]
        return try JSONSerialization.data(withJSONObject: ["chart": ["result": [result], "error": NSNull()]])
    }

    static let csv = Data("""
    Date,Open,High,Low,Close,Volume
    2026-10-15,100,108,99,105,1000
    2026-10-16,105,111,104,110,2000
    """.utf8)
}

actor FinanceFixtureNetwork {
    private var offline = false
    private(set) var requestCount = 0
    func setOffline(_ value: Bool) { offline = value }
    func load(_ url: URL) throws -> Data {
        requestCount += 1
        if offline { throw URLError(.notConnectedToInternet) }
        if url.host == "stooq.com" { return FinanceFixtures.csv }
        return try FinanceFixtures.yahoo(symbol: url.lastPathComponent)
    }
}
