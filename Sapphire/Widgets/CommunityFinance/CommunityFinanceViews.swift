import Charts
import SwiftUI

@MainActor
struct CommunityFinanceBoardView: View {
    @ObservedObject private var store: CommunityFinanceStore
    @State private var showSearch = false
    private let width: CGFloat?

    init(store: CommunityFinanceStore? = nil, width: CGFloat? = 600) {
        _store = ObservedObject(wrappedValue: store ?? .shared)
        self.width = width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if showSearch { CommunityFinanceSearchView(store: store) }
            if store.watchlist.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Your watchlist").font(.headline)
                    Text("Add a symbol to follow its price in TopLet.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Add stock") { showSearch = true }
                }
                .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    watchlist
                    Divider()
                    detail
                }
            }
            Text("Yahoo Finance · Quotes may be delayed. Stooq daily closes are used when available.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: width)
        .appContentAppearance()
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Stocks").font(.title2.bold())
            Text("\(store.watchlist.count) following").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button {
                showSearch.toggle()
            } label: { Image(systemName: showSearch ? "xmark" : "plus") }
                .help(showSearch ? "Close symbol search" : "Add stock")
                .accessibilityLabel(showSearch ? "Close symbol search" : "Add stock")
            Button { Task { await store.refresh(force: true) } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(store.isLoading)
            .help("Refresh quotes")
            .accessibilityLabel("Refresh quotes")
        }
    }

    private var watchlist: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(store.watchlist, id: \.self) { symbol in
                    Button { store.selectedSymbol = symbol } label: {
                        CommunityFinanceQuoteRow(
                            symbol: symbol, quote: store.quotes[symbol],
                            isCached: store.isCached(symbol: symbol),
                            selected: store.selectedSymbol == symbol
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove \(symbol) from watchlist") { store.remove(symbol: symbol) }
                    }
                    .accessibilityLabel("\(symbol), \(store.quotes[symbol]?.priceText ?? "Quote unavailable")")
                }
            }
        }
        .frame(width: 225, height: 260)
    }

    @ViewBuilder
    private var detail: some View {
        if let quote = store.quotes[store.selectedSymbol] {
            CommunityFinanceDetailView(
                quote: quote, cached: store.isCached(symbol: quote.symbol),
                error: store.errors[quote.symbol], remove: { store.remove(symbol: quote.symbol) }
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.selectedSymbol).font(.title2.bold())
                if store.isLoading {
                    ProgressView("Loading quote…").controlSize(.small)
                } else {
                    Label("Quote unavailable", systemImage: "wifi.exclamationmark").font(.headline)
                    Text(store.errors[store.selectedSymbol] ?? "Refresh to load this stock's latest available quote.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { Task { await store.refresh(force: true) } }
                }
                Spacer()
                Button("Remove from watchlist") { store.remove(symbol: store.selectedSymbol) }
                    .font(.caption).buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        }
    }
}

private struct CommunityFinanceQuoteRow: View {
    let symbol: String
    let quote: FinanceQuote?
    let isCached: Bool
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(symbol).font(.subheadline.bold())
                Spacer(minLength: 4)
                Text(quote?.priceText ?? "—").font(.caption.weight(.medium)).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(quote?.name ?? "Quote unavailable").lineLimit(1).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(quote?.changePercentText ?? "—")
                    .foregroundStyle(changeColor).monospacedDigit()
            }
            .font(.caption2)
            if isCached || quote?.isDailyClose == true {
                Text(isCached ? "Cached · \(quote?.timestampText ?? "")" : "Daily close · \(quote?.timestampText ?? "")")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(9)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }

    private var changeColor: Color {
        guard let quote, quote.hasChange else { return .secondary }
        return quote.change >= 0 ? .green : .red
    }
}

private struct CommunityFinanceDetailView: View {
    let quote: FinanceQuote
    let cached: Bool
    let error: String?
    let remove: () -> Void
    private var color: Color { quote.hasChange ? (quote.change >= 0 ? .green : .red) : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(quote.symbol).font(.title3.bold())
                Spacer()
                if let url = quote.providerURL {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                        .help("Open \(quote.symbol) on Yahoo Finance")
                }
            }
            Text(quote.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Text(quote.priceText).font(.system(size: 27, weight: .semibold, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text("\(quote.changeText) (\(quote.changePercentText)) vs previous close")
                .font(.caption.weight(.medium)).foregroundStyle(color)
            if quote.history.count >= 2 {
                Chart(quote.history) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Price", point.price))
                        .foregroundStyle(color)
                        .interpolationMethod(.linear)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                .frame(height: 84)
                .accessibilityLabel("One month of daily prices for \(quote.symbol), in \(quote.currency)")
                Text("1 month · daily prices").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Price history unavailable").font(.caption).foregroundStyle(.secondary)
                    .frame(height: 84)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(quote.exchange) · \(quote.marketState)")
                Text("\(quote.isDailyClose ? "Daily close" : "Regular-session quote") · \(quote.timestampText)")
                Text("\(cached ? "Cached · " : "")\(quote.source)")
                if let error { Text(error).foregroundStyle(.orange).lineLimit(3).help(error) }
            }
            .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Remove") { remove() }.buttonStyle(.borderless).font(.caption)
                    .help("Remove \(quote.symbol) from watchlist")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct CommunityFinanceSearchView: View {
    @ObservedObject var store: CommunityFinanceStore
    @State private var query = ""
    @State private var results: [CommunityFinanceSearchResult] = []
    @State private var searching = false
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Company or symbol: AAPL, 0700.HK, VOD.L", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add(query) }
                if searching || adding { ProgressView().controlSize(.small) }
                Button("Add symbol") { add(query) }
                    .disabled(adding || CommunityFinanceDecoder.symbol(query) == nil)
            }
            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { result in
                            Button { add(result.symbol) } label: {
                                HStack {
                                    Text(result.symbol).font(.subheadline.bold()).frame(width: 80, alignment: .leading)
                                    Text(result.name).lineLimit(1)
                                    Spacer()
                                    Text(result.exchange).foregroundStyle(.secondary)
                                    Image(systemName: store.watchlist.contains(result.symbol) ? "checkmark" : "plus")
                                }
                                .font(.caption).padding(.vertical, 7)
                            }
                            .buttonStyle(.plain).disabled(adding)
                        }
                    }
                }
                .frame(maxHeight: 125)
            }
            if let error = store.addError ?? store.searchError {
                Text(error).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: query) {
            let searched = query
            guard !searched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                results = []
                searching = false
                return
            }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            searching = true
            let found = await store.search(searched)
            guard !Task.isCancelled, query == searched else { return }
            results = found
            searching = false
        }
    }

    private func add(_ symbol: String) {
        guard !adding else { return }
        adding = true
        Task {
            if await store.add(symbol: symbol) { query = ""; results = [] }
            adding = false
        }
    }
}

@MainActor
struct CommunityFinanceCompactView: View {
    @ObservedObject private var store: CommunityFinanceStore

    init(store: CommunityFinanceStore? = nil) {
        _store = ObservedObject(wrappedValue: store ?? .shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Stocks", systemImage: "chart.line.uptrend.xyaxis").font(.caption.bold())
                Spacer()
                if store.isLoading { ProgressView().controlSize(.mini) }
            }
            if store.watchlist.isEmpty {
                Text("Add stocks to your watchlist").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(store.watchlist.prefix(3)), id: \.self) { symbol in
                HStack(spacing: 4) {
                    Text(symbol).font(.caption.weight(.semibold))
                    Spacer(minLength: 2)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(store.quotes[symbol]?.priceText ?? "—").font(.system(size: 10, weight: .medium))
                        Text(store.quotes[symbol]?.changePercentText ?? "Unavailable")
                            .font(.system(size: 9))
                            .foregroundStyle(store.quotes[symbol].map { $0.change >= 0 ? Color.green : Color.red } ?? .secondary)
                    }
                    .monospacedDigit()
                }
            }
            Text(statusText).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(9)
        .frame(width: 180, alignment: .leading)
        .appContentAppearance()
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var statusText: String {
        if store.watchlist.contains(where: { store.isCached(symbol: $0) }) { return "Cached quotes · Open for timestamps" }
        if store.watchlist.contains(where: { store.quotes[$0]?.isDailyClose == true }) { return "Daily closes · Open for dates" }
        return "Quotes may be delayed"
    }
}
