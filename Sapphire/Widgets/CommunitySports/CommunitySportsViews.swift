import AppKit
import SwiftUI

/// A local Sports implementation backed by public score and race-calendar feeds.
@MainActor
struct CommunitySportsBoardView: View {
    @ObservedObject private var store: CommunitySportsStore
    @ObservedObject private var timing: F1LiveTimingStore
    @State private var favoritesOnly = false
    @State private var expandedRace: String?
    @State private var racingPane = "timing"
    private let width: CGFloat?

    init(store: CommunitySportsStore? = nil, timing: F1LiveTimingStore? = nil, width: CGFloat? = 590) {
        _store = ObservedObject(wrappedValue: store ?? .shared)
        _timing = ObservedObject(wrappedValue: timing ?? .shared)
        self.width = width
    }

    private var requestID: String {
        "\(store.selectedLeague.rawValue)-\(Calendar.current.startOfDay(for: store.selectedDate).timeIntervalSince1970)"
    }

    private var displayedEvents: [CommunitySportsEvent] {
        let events = favoritesOnly && !store.selectedLeague.isRacing
            ? store.events.filter { store.isFavorite($0) } : store.events
        guard store.selectedLeague.isRacing else { return events }
        // Keep the nearest race weekend visible without hiding the season's results.
        let day = Calendar.current.startOfDay(for: store.selectedDate)
        let future = events.filter { ($0.startDate ?? .distantPast) >= day }
        let past = events.filter { ($0.startDate ?? .distantPast) < day }.reversed()
        return future + Array(past)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !store.selectedLeague.isRacing || racingPane == "calendar" { dateControls }
            if store.selectedLeague.isRacing {
                Picker("Formula 1 view", selection: $racingPane) {
                    Text("Live timing").tag("timing")
                    Text("Race calendar").tag("calendar")
                }
                .pickerStyle(.segmented)
            }
            if store.selectedLeague.isRacing && racingPane == "timing" {
                F1LiveTimingPanel(store: timing)
            } else {
            if let error = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Retry") { Task { await store.load(force: true) } }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if store.isLoading && store.events.isEmpty {
                ProgressView("Loading \(store.selectedLeague.title)…")
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else if displayedEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedEvents) { event in
                            CommunitySportsEventRow(
                                event: event,
                                isRacing: store.selectedLeague.isRacing,
                                expanded: expandedRace == event.id,
                                favoriteIDs: store.favoriteTeamIDs
                            ) {
                                expandedRace = expandedRace == event.id ? nil : event.id
                                if expandedRace == event.id && event.results.isEmpty {
                                    Task { await store.loadResults(for: event) }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 300)
            }
            footer
            }
        }
        .padding(16)
        .frame(width: width)
        .appContentAppearance()
        .task(id: requestID) { await store.load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await store.load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Sports", systemImage: "sportscourt.fill").font(.title3.bold())
            Spacer()
            Picker("Competition", selection: $store.selectedLeague) {
                ForEach(CommunitySportsLeague.allCases) { league in
                    Text(league.title).tag(league)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            if !store.selectedLeague.isRacing {
                Toggle("Following", isOn: $favoritesOnly)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Show events involving teams you follow in Sports settings.")
            }
            if !store.selectedLeague.isRacing || racingPane == "calendar" {
                Button {
                    Task { await store.load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isLoading)
                .help("Refresh scores")
                .accessibilityLabel("Refresh scores")
            }
        }
    }

    private var dateControls: some View {
        HStack {
            Button { changeDate(by: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(store.selectedLeague.isRacing ? "Previous season" : "Previous day")
            if store.selectedLeague.isRacing {
                Text("\(Calendar.current.component(.year, from: store.selectedDate), format: .number.grouping(.never)) season")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            } else {
                DatePicker("Match date", selection: $store.selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
            Button { changeDate(by: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(store.selectedLeague.isRacing ? "Next season" : "Next day")
            Button("Today") { store.selectedDate = Date() }
                .controlSize(.small)
        }
        .buttonStyle(.borderless)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: favoritesOnly ? "star" : "calendar")
                .font(.system(size: 26)).foregroundStyle(.secondary)
            Text(favoritesOnly ? "No followed teams playing here." : "No events for this date.")
                .font(.headline)
            Text(favoritesOnly ? "Choose teams in Settings → Sports, or turn off Following." : "Try another day or competition.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var footer: some View {
        HStack {
            Text(store.selectedLeague.isRacing ? "F1 schedules & published results · Jolpica" : "Scores & schedules · ESPN")
            Spacer()
            if let updated = store.lastUpdated {
                Text("Updated \(updated, style: .time)")
            }
            if store.isLoading { ProgressView().controlSize(.mini) }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func changeDate(by amount: Int) {
        let component: Calendar.Component = store.selectedLeague.isRacing ? .year : .day
        if let date = Calendar.current.date(byAdding: component, value: amount, to: store.selectedDate) {
            store.selectedDate = date
        }
    }
}

private struct CommunitySportsEventRow: View {
    let event: CommunitySportsEvent
    let isRacing: Bool
    let expanded: Bool
    let favoriteIDs: Set<String>
    let toggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(event.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(event.isLive ? Color.green : Color.secondary)
                Spacer()
                if let date = event.startDate {
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if isRacing {
                raceContent
            } else {
                teamLine(event.awayTeam, score: event.awayScore)
                teamLine(event.homeTeam, score: event.homeScore)
            }
            if let detail = event.detail, !detail.isEmpty, detail != event.status {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if let url = event.linkURL {
                Link("View event", destination: url).font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var raceContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flag.checkered")
                Text(event.title).font(.headline)
                Spacer(minLength: 8)
                if !event.results.isEmpty || (event.startDate ?? .distantFuture) < Date() {
                    Button(expanded ? "Hide results" : (event.results.isEmpty ? "Load results" : "Results"), action: toggleExpanded)
                        .controlSize(.small)
                }
            }
            if !event.results.isEmpty {
                ForEach(Array(event.results.prefix(expanded ? 30 : 3))) { result in
                    HStack(spacing: 8) {
                        Text("\(result.position)").monospacedDigit().frame(width: 22, alignment: .leading)
                        Text(result.name).fontWeight(result.position == 1 ? .semibold : .regular)
                        if let teamID = result.teamID, favoriteIDs.contains(teamID) {
                            Image(systemName: "star.fill").foregroundStyle(Color.accentColor)
                                .accessibilityLabel("Followed constructor")
                        }
                        Text(result.team).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(result.detail).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func teamLine(_ team: CommunitySportsTeam?, score: String?) -> some View {
        HStack(spacing: 9) {
            CommunitySportsTeamLogo(url: team?.logoURL)
            Text(team?.name ?? "Team unavailable").font(.subheadline.weight(.medium))
            Spacer()
            Text(score ?? "—").font(.title3.weight(.semibold).monospacedDigit())
        }
    }
}

private struct CommunitySportsTeamLogo: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "sportscourt").foregroundStyle(.secondary)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

@MainActor
struct CommunitySportsCompactView: View {
    @ObservedObject private var store: CommunitySportsStore
    @ObservedObject private var timing: F1LiveTimingStore

    init(store: CommunitySportsStore? = nil, timing: F1LiveTimingStore? = nil) {
        _store = ObservedObject(wrappedValue: store ?? .shared)
        _timing = ObservedObject(wrappedValue: timing ?? .shared)
    }

    private var event: CommunitySportsEvent? {
        let events = store.events
        return events.first(where: { $0.isLive && store.isFavorite($0) })
            ?? events.first(where: { $0.isLive })
            ?? events.first(where: { ($0.startDate ?? .distantPast) >= Date() })
            ?? events.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(store.selectedLeague.title, systemImage: store.selectedLeague.isRacing ? "flag.checkered" : "sportscourt")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if store.selectedLeague.isRacing, let snapshot = timing.snapshot {
                Text(snapshot.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(F1LiveTimingPanel.lapText(snapshot.lap, total: snapshot.totalLaps))
                    .font(.caption.monospacedDigit())
                if let driver = snapshot.drivers.first(where: { timing.isFavorite(driver: $0) }) ?? snapshot.drivers.first {
                    Text("\(driver.position.map { "P\($0)" } ?? "P—") · \(driver.abbreviation)")
                        .font(.caption.weight(.semibold))
                }
                Text(snapshot.isStale ? "Saved timing" : snapshot.status)
                    .font(.caption2).foregroundStyle(.secondary)
            } else if let event {
                if store.selectedLeague.isRacing {
                    Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let date = event.startDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption)
                    }
                } else {
                    compactTeam(event.awayTeam, score: event.awayScore)
                    compactTeam(event.homeTeam, score: event.homeScore)
                }
                Text(event.status).font(.caption2).foregroundStyle(event.isLive ? Color.green : Color.secondary)
            } else {
                Text(store.isLoading ? "Loading scores…" : "Open Sports for scores")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 180, alignment: .leading)
        .padding(8)
        .appContentAppearance()
        .task {
            while !Task.isCancelled {
                await store.load()
                if store.selectedLeague.isRacing { await timing.refresh() }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func compactTeam(_ team: CommunitySportsTeam?, score: String?) -> some View {
        HStack {
            Text(team?.shortName ?? "—").lineLimit(1)
            Spacer()
            Text(score ?? "—").monospacedDigit()
        }
        .font(.subheadline.weight(.medium))
    }
}

@MainActor
struct CommunitySportsSettingsView: View {
    @EditingSettings private var settings: SettingsEditingSession
    @ObservedObject private var store = CommunitySportsStore.shared
    @State private var teamSearch = ""

    private var matchingTeams: [CommunitySportsTeam] {
        guard !teamSearch.isEmpty else { return store.teams }
        return store.teams.filter { $0.name.localizedCaseInsensitiveContains(teamSearch) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sports").font(.largeTitle.bold())
                Text("Follow football and Formula 1 from Sapphire.")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show Sports widget in the notch", isOn: $settings.settings.sportsWidgetEnabled)
                    Toggle("Show live football scores", isOn: $settings.settings.sportsLiveActivityEnabled)
                    if settings.settings.sportsLiveActivityEnabled {
                        Toggle("Only show matches while live", isOn: $settings.settings.sportsLiveActivityWhenLiveOnly)
                    }
                }
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                CommunitySportsBoardView(width: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if store.selectedLeague.isRacing { F1FollowSettingsView() }

                if !store.selectedLeague.isRacing {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.selectedLeague.isRacing ? "Follow constructors" : "Follow teams")
                        .font(.headline)
                    TextField("Search teams", text: $teamSearch)
                        .textFieldStyle(.roundedBorder)
                    if matchingTeams.isEmpty {
                        Text(store.isLoading ? "Loading teams…" : (teamSearch.isEmpty ? "No teams available for this competition." : "No matching teams."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), alignment: .leading)], alignment: .leading) {
                        ForEach(matchingTeams) { team in
                            Button { store.toggleFavorite(team) } label: {
                                HStack(spacing: 8) {
                                    CommunitySportsTeamLogo(url: team.logoURL)
                                    Text(team.name).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Image(systemName: store.favoriteTeamIDs.contains(team.id) ? "star.fill" : "star")
                                        .foregroundStyle(store.favoriteTeamIDs.contains(team.id) ? Color.accentColor : Color.secondary)
                                }
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(store.favoriteTeamIDs.contains(team.id) ? "Unfollow" : "Follow") \(team.name)")
                        }
                    }
                }
                }
                Text("Football and Formula 1 use the latest reported provider data. Live timing refreshes about every 15 seconds; provider delays can apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onChange(of: store.favoriteTeamIDs) { _, _ in syncFavoriteTeams() }
        .onChange(of: store.selectedLeague) { _, _ in teamSearch = "" }
    }

    private func syncFavoriteTeams() {
        // Stable IDs let the same football club match across domestic and European competitions.
        settings.settings.sportsFavoriteTeams = store.favoriteTeamIDs
            .filter { $0.hasPrefix("soccer:") }.sorted()
    }
}
