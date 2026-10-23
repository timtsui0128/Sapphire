import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct CommunityFinanceChecks {
    @MainActor
    static func main() async {
        do {
            if CommandLine.arguments.contains("--live") {
                try await live()
            } else {
                try decoders()
                try await fallback()
                try await storeAndAdapter()
                print("PASS: all community finance fixture checks")
            }
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw CheckFailure(description: message) }
    }

    static func decoders() throws {
        let now = Date(timeIntervalSince1970: 1_792_563_000)
        let quote = try CommunityFinanceDecoder.yahoo(FinanceFixtures.yahoo(now: now), requestedSymbol: "AAPL", now: now)
        try check(quote.price == 110 && quote.change == 5, "Daily change used the month-range baseline")
        try check(abs(quote.changePercent - (5.0 / 105 * 100)) < 0.000001, "Daily percentage has the wrong denominator")
        try check(quote.hasChange && quote.history.count == 1, "Null history points were converted to zero")
        try check(quote.quotedAt == now && quote.marketState == "Regular session", "Provider time/session lost")
        try check(quote.currency == "USD" && quote.exchange == "NasdaqGS", "Currency or exchange lost")
        print("PASS: daily change uses preceding trading close, null candles stay absent, provider metadata preserved")

        let london = try CommunityFinanceDecoder.yahoo(
            FinanceFixtures.yahoo(symbol: "VOD.L", currency: "GBp", now: now), requestedSymbol: "VOD.L", now: now
        )
        try check(london.priceText.contains("GBp") && london.price == 110, "London pence were converted to pounds or dollars")
        let hk = try CommunityFinanceDecoder.yahoo(
            FinanceFixtures.yahoo(symbol: "0700.HK", currency: "HKD", now: now), requestedSymbol: "0700.HK", now: now
        )
        try check(hk.priceText.contains("HKD"), "Hong Kong currency lost")
        let noBaseline = try CommunityFinanceDecoder.yahoo(
            FinanceFixtures.yahoo(now: now, withPrevious: false), requestedSymbol: "AAPL", now: now
        )
        try check(!noBaseline.hasChange && noBaseline.changePercentText == "—", "Unknown daily change became fake 0%")
        for data in [
            try FinanceFixtures.yahoo(now: now, withPrice: false),
            try FinanceFixtures.yahoo(now: now, withCurrency: false),
            try FinanceFixtures.yahoo(symbol: "MSFT", now: now)
        ] {
            do {
                _ = try CommunityFinanceDecoder.yahoo(data, requestedSymbol: "AAPL", now: now)
                throw CheckFailure(description: "Incomplete or mismatched quote was accepted")
            } catch is CommunityFinanceError {}
        }
        print("PASS: GBp/HKD units preserved; missing prices, currencies, changes and mismatched symbols handled honestly")

        let daily = try CommunityFinanceDecoder.stooq(FinanceFixtures.csv, symbol: "AAPL", now: now)
        try check(daily.isDailyClose && daily.isAfterHours && daily.source == "Stooq", "Fallback advertised live data")
        try check(daily.price == 110 && daily.change == 5 && daily.timestampText.contains("2026"), "Daily fallback date or price lost")
        try check(CommunityFinanceDecoder.stooqSymbol("0700.HK") == nil, "Fallback guessed an unsupported market's currency")
        do {
            _ = try CommunityFinanceDecoder.stooq(Data("<html>Challenge</html>".utf8), symbol: "AAPL", now: now)
            throw CheckFailure(description: "HTML challenge became a stock quote")
        } catch is CommunityFinanceError {}
        let search = Data("""
        {"quotes":[{"symbol":"AAPL","longname":"Apple Inc.","quoteType":"EQUITY","exchDisp":"NASDAQ"},
        {"symbol":"AAPL","quoteType":"EQUITY"},{"symbol":"SAAPL=F","quoteType":"FUTURE"},
        {"symbol":"VOD.L","quoteType":"EQUITY","shortname":"Vodafone","exchange":"LSE"}]}
        """.utf8)
        let matches = try CommunityFinanceDecoder.search(search)
        try check(matches.map(\.symbol) == ["AAPL", "VOD.L"], "Search includes duplicate or non-stock results")
        try check(CommunityFinanceDecoder.symbol(" 0700.hk ") == "0700.HK", "Ticker normalization failed")
        try check(CommunityFinanceDecoder.symbol("../AAPL") == nil, "Invalid ticker path accepted")
        print("PASS: dated daily fallback rejects HTML; search de-duplicates valid stock symbols")
    }

    static func fallback() async throws {
        let client = CommunityFinanceClient { url in
            if url.host == "query1.finance.yahoo.com" { throw CommunityFinanceError.http(429) }
            return FinanceFixtures.csv
        }
        let quote = try await client.quote(symbol: "AAPL")
        try check(quote.isDailyClose && quote.source == "Stooq", "Unavailable primary provider did not use daily fallback")
        let unavailable = CommunityFinanceClient { _ in Data("<html>Unavailable</html>".utf8) }
        do {
            _ = try await unavailable.quote(symbol: "AAPL")
            throw CheckFailure(description: "Unavailable providers returned a fake quote")
        } catch is CommunityFinanceError {}
        print("PASS: primary failure uses explicit daily fallback, and two failures stay unavailable")
    }

    @MainActor
    static func storeAndAdapter() async throws {
        let name = "CommunityFinanceChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let network = FinanceFixtureNetwork()
        let client = CommunityFinanceClient { try await network.load($0) }
        let store = CommunityFinanceStore(defaults: defaults, client: client)
        try check(store.watchlist == ["AAPL", "MSFT", "NVDA"], "Default watchlist changed")
        let adapter = FinanceAPIService(store: store)
        try check(adapter.cachedQuote(symbol: "AAPL") == nil, "Missing cache returned a placeholder quote")
        let absent = adapter.makePayload(symbol: "AAPL", index: 0, quote: nil)
        try check(absent.price == "—" && absent.changePercent == "—", "Missing quote displayed $0.00 or 0%")
        await store.refresh()
        try check(store.quotes.count == 3 && store.errors.isEmpty, "Watchlist refresh failed")
        try check(adapter.cachedQuote(symbol: "AAPL")?.price == 110, "Fresh quote missing from activity adapter")
        let count = await network.requestCount
        await store.refresh()
        let secondCount = await network.requestCount
        try check(secondCount == count, "Immediate refresh ignored request throttle")
        let added = await store.add(symbol: " 0700.hk ")
        try check(added, "Valid Hong Kong ticker could not be added")
        try check(store.selectedSymbol == "0700.HK" && store.watchlist.last == "0700.HK", "Added symbol not selected")
        let reloaded = CommunityFinanceStore(defaults: defaults, client: client)
        try check(reloaded.watchlist == store.watchlist && reloaded.selectedSymbol == "0700.HK", "Watchlist or selection did not persist")
        try check(reloaded.quotes["AAPL"] == store.quotes["AAPL"], "Cached quote metadata did not persist")
        print("PASS: editable default watchlist, selection, quote cache and throttling work without placeholder values")

        await network.setOffline(true)
        await store.refresh(force: true)
        try check(store.quotes["AAPL"]?.price == 110 && store.errors["AAPL"] != nil, "Offline refresh destroyed good cached data")
        try check(store.isCached(symbol: "AAPL") && adapter.cachedQuote(symbol: "AAPL") == nil, "Offline cache was advertised as a fresh live activity")
        for symbol in store.watchlist { store.remove(symbol: symbol) }
        let empty = CommunityFinanceStore(defaults: defaults, client: client)
        try check(empty.watchlist.isEmpty && empty.selectedSymbol.isEmpty, "Empty watchlist was replaced by defaults on reload")
        print("PASS: offline errors retain dated cache, suppress stale live ticker, and preserve an intentionally empty watchlist")
    }

    static func live() async throws {
        for symbol in ["AAPL", "MSFT", "NVDA", "0700.HK", "VOD.L"] {
            let quote = try await CommunityFinanceClient.shared.quote(symbol: symbol)
            try check(quote.price > 0 && quote.quotedAt != nil && !quote.currency.isEmpty, "Native request lost metadata")
            print("\(quote.symbol): \(quote.priceText), \(quote.changePercentText), \(quote.exchange), \(quote.marketState), \(quote.timestampText), \(quote.source)")
        }
        let results = try await CommunityFinanceClient.shared.search("Apple")
        try check(results.contains { $0.symbol == "AAPL" }, "Native symbol search did not find Apple")
        print("PASS: native URLSession quotes across US/HK/London and company search")
    }
}
