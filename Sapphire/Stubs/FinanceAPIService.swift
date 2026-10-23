import Foundation
import SwiftUI

/// Compatibility adapter for Sapphire's notch activity pipeline.
@MainActor
final class FinanceAPIService {
    static let shared = FinanceAPIService(store: .shared)
    private let store: CommunityFinanceStore

    init(store: CommunityFinanceStore) { self.store = store }

    func cachedQuote(symbol: String) -> FinanceQuote? {
        guard let symbol = CommunityFinanceDecoder.symbol(symbol),
              !store.isCached(symbol: symbol) else { return nil }
        return store.quotes[symbol]
    }

    func fetchQuote(symbol: String) async -> FinanceQuote? {
        _ = await store.fetch(symbol: symbol)
        return cachedQuote(symbol: symbol)
    }

    func makePayload(symbol: String, index: Int, quote: FinanceQuote?) -> FinancePayload {
        FinancePayload(
            symbol: symbol, price: quote?.priceText ?? "—",
            change: quote?.changeText ?? "—", changePercent: quote?.changePercentText ?? "—",
            isPositive: (quote?.change ?? 0) >= 0, name: quote?.name ?? symbol,
            isAfterHours: quote?.isAfterHours ?? true,
            closingPrice: quote?.isAfterHours == true ? quote?.priceText : nil
        )
    }
}

@MainActor
enum FinanceLiveActivityView {
    static func left(for payload: FinancePayload) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.green)
            Text(payload.symbol).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .lineLimit(1)
    }

    static func right(for payload: FinancePayload) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(payload.price).foregroundStyle(.white)
            Text(payload.changePercent).foregroundStyle(payload.isPositive ? Color.green : Color.red)
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
    }
}
