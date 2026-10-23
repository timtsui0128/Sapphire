//
//  SportsAPIService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

import Foundation
import SwiftUI

@MainActor
final class SportsAPIService {
    static let shared = SportsAPIService(client: .shared)
    private let client: CommunitySportsClient
    private var scoreboards: [CommunitySportsLeague: [CommunitySportsEvent]] = [:]
    private var fetchedAt: [CommunitySportsLeague: Date] = [:]
    private var attemptedAt: [CommunitySportsLeague: Date] = [:]
    init(client: CommunitySportsClient) { self.client = client }

    func bootstrapIfNeeded() {}

    func cachedLiveEvent(for teamOrLeague: String) -> LiveSportsEvent? {
        let token = teamOrLeague.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = scoreboards.flatMap { league, events -> [(CommunitySportsLeague, CommunitySportsEvent)] in
            // Never keep advertising a live score after the feed has gone stale.
            guard let fetched = fetchedAt[league], Date().timeIntervalSince(fetched) < 120 else { return [] }
            let isLeague = [league.rawValue, league.title, league.route ?? ""].map { $0.lowercased() }.contains(token)
            return events.filter { event in
                isLeague || [event.homeTeam, event.awayTeam].compactMap { $0 }.contains { team in
                    [team.id, team.name, team.shortName].map { $0.lowercased() }.contains(token)
                }
            }.map { (league, $0) }
        }.sorted { lhs, rhs in
            if lhs.1.isLive != rhs.1.isLive { return lhs.1.isLive }
            if lhs.1.isComplete != rhs.1.isComplete { return !lhs.1.isComplete }
            return (lhs.1.startDate ?? .distantFuture) < (rhs.1.startDate ?? .distantFuture)
        }
        guard let (league, event) = matches.first, let home = event.homeTeam, let away = event.awayTeam else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let clock = event.isLive ? (event.detail ?? "") : event.startDate.map(formatter.string) ?? ""
        return LiveSportsEvent(
            eventId: event.id, homeTeam: home.shortName, awayTeam: away.shortName,
            homeScore: Int(event.homeScore ?? "") ?? 0, awayScore: Int(event.awayScore ?? "") ?? 0,
            homeScoreDisplay: event.homeScore ?? "—", awayScoreDisplay: event.awayScore ?? "—",
            status: event.isLive ? "Live" : (event.isComplete ? "Final" : event.status), clock: clock,
            homeLogoURL: home.logoURL, awayLogoURL: away.logoURL,
            leagueRoute: ESPNLeagueRoute(sport: "soccer", league: league.route ?? "", displayName: league.title),
            isLive: event.isLive
        )
    }

    // The scoreboard feed does not supply commentary; absence is explicit.
    func peekLatestCommentary(for event: LiveSportsEvent) -> SportsComment? { nil }

    func prefetchLiveScoreboards(for teams: [String]) async {
        guard !teams.isEmpty else { return }
        let football = CommunitySportsLeague.allCases.filter { !$0.isRacing }
        let selectedLeagues = football.filter { league in
            teams.contains { token in
                [league.rawValue, league.title, league.route ?? ""].contains { $0.caseInsensitiveCompare(token) == .orderedSame }
            }
        }
        // A club can play in several competitions; stable soccer IDs work in each.
        let leagues = selectedLeagues.count == teams.count ? selectedLeagues : football
        await withTaskGroup(of: (CommunitySportsLeague, [CommunitySportsEvent]?).self) { group in
            for league in leagues {
                if let attempted = attemptedAt[league], Date().timeIntervalSince(attempted) < 30 { continue }
                attemptedAt[league] = Date()
                group.addTask { @MainActor [client] in
                    (league, try? await client.football(league: league, date: Date()))
                }
            }
            for await (league, events) in group {
                if let events {
                    scoreboards[league] = events
                    fetchedAt[league] = Date()
                }
            }
        }
    }

    func fetchLiveEvent(for team: String, forceRefresh: Bool = false) async -> LiveSportsEvent? {
        // The shared 30-second scoreboard cache also applies to ticker refreshes.
        await prefetchLiveScoreboards(for: [team])
        return cachedLiveEvent(for: team)
    }
}

@MainActor
enum SportsLiveActivityView {
    @ViewBuilder static func left(for payload: SportsPayload, preferLogo: Bool) -> some View {
        if let timing = payload.f1 {
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                Text(timing.lapText).font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .help(timing.title)
        } else {
          HStack(spacing: 5) {
            badge(payload.awayLogoURL, preferLogo: preferLogo)
            Text(payload.awayTeam).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            if showsScore(payload) { Text("\(payload.awayScore)").monospacedDigit().font(.system(size: 13, weight: .bold)) }
          }
        }
    }

    @ViewBuilder static func right(for payload: SportsPayload, preferLogo: Bool) -> some View {
        if let timing = payload.f1 {
            HStack(spacing: 5) {
                Text(timing.position.map { "P\($0)" } ?? "P—").monospacedDigit()
                Text(timing.driver).lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
        } else {
          HStack(spacing: 5) {
            if showsScore(payload) { Text("\(payload.homeScore)").monospacedDigit().font(.system(size: 13, weight: .bold)) }
            Text(payload.homeTeam).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            badge(payload.homeLogoURL, preferLogo: preferLogo)
          }
        }
    }

    private static func showsScore(_ payload: SportsPayload) -> Bool {
        payload.status == "Live" || payload.status == "Final"
    }

    @ViewBuilder private static func badge(_ url: URL?, preferLogo: Bool) -> some View {
        if preferLogo, let url {
            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: {
                Image(systemName: "soccerball").resizable().scaledToFit()
            }.frame(width: 18, height: 18)
        }
    }
}
