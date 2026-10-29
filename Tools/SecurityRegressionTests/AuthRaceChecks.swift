import Foundation

/// The production token-exchange and refresh methods are compiled unchanged,
/// apart from injected transport/storage and removal of private access control.
@MainActor final class SuspendedAuthTransport {
    var request: URLRequest?
    var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitForRequest() async {
        for _ in 0..<1000 {
            if continuation != nil { return }
            await Task.yield()
        }
        preconditionFailure("Token request did not reach the test transport")
    }
    func succeed() {
        let reply = Data(#"{"access_token":"synthetic-access","refresh_token":"synthetic-refresh","expires_in":3600}"#.utf8)
        let response = HTTPURLResponse(url: request!.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let pending = continuation!
        continuation = nil
        pending.resume(returning: (reply, response))
    }
}

@MainActor protocol AuthRaceSubject: AnyObject {
    var loginSession: OAuthLoginSession { get set }
    var transport: SuspendedAuthTransport { get }
    var vault: MusicCredentialStore { get }
    var defaults: MemoryDefaults { get }
    var accessToken: String? { get }
    var refreshToken: String? { get set }
    var isAuthenticated: Bool { get }
    func exchangeCodeForToken(code: String, attempt: OAuthLoginSession.Attempt) async
    func refreshTokenIfNeeded(force: Bool) async -> Bool
    func logout()
}

@MainActor func checkAuthRaces<T: AuthRaceSubject>(_ make: () -> T, tokenKey: String) async {
    for action in ["logout", "new-login", "success"] {
        let subject = make()
        let attempt = subject.loginSession.begin(clientID: "fixture-client")!
        let task = Task { await subject.exchangeCodeForToken(code: "a+b&c=d", attempt: attempt) }
        await subject.transport.waitForRequest()
        let request = subject.transport.request!
        check(request.value(forHTTPHeaderField: "Authorization") == nil, "PKCE exchange must not send a client secret")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        let items = URLComponents(string: "https://fixture.invalid/?" + body)!.queryItems!
        check(items.first { $0.name == "code" }?.value == "a+b&c=d", "Authorization codes must be correctly form encoded")
        check(body.contains("%2B") && items.first { $0.name == "code_verifier" }?.value == attempt.verifier, "PKCE verifier and plus encoding")
        if action == "logout" { subject.logout() }
        if action == "new-login" { _ = subject.loginSession.begin(clientID: "fixture-client") }
        subject.transport.succeed()
        await task.value
        if action == "success" {
            check(subject.isAuthenticated && subject.vault.string(forKey: tokenKey) == "synthetic-access", "Current exchange must save protected credentials")
            check(subject.defaults.object(forKey: tokenKey) == nil, "Exchange must not save a plaintext token")
        } else {
            check(!subject.isAuthenticated && subject.accessToken == nil && subject.vault.string(forKey: tokenKey) == nil, "Late exchange must not restore an account")
        }
    }
    let subject = make()
    subject.refreshToken = "old-refresh"
    let refresh = Task { await subject.refreshTokenIfNeeded(force: true) }
    await subject.transport.waitForRequest()
    subject.logout()
    subject.transport.succeed()
    let refreshed = await refresh.value
    check(!refreshed && !subject.isAuthenticated && subject.vault.string(forKey: tokenKey) == nil, "Late refresh must not undo logout")
}

@MainActor func runAuthRaceChecks() async {
    await checkAuthRaces({ SpotifyAuthFixture() }, tokenKey: "spotifyAccessToken")
    await checkAuthRaces({ TidalAuthFixture() }, tokenKey: "tidalAccessToken")
    print("PASS: actual Spotify/TIDAL token methods reject late login/refresh after logout or a newer login; PKCE encoding and successful Keychain writes")
}
