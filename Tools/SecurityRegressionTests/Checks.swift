import AppKit
import Foundation
import Security

final class MemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    init() { super.init(suiteName: "SecurityFixture.\(UUID())")! }
    override func object(forKey key: String) -> Any? { values[key] }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

@MainActor final class FakeVault {
    var entries: [String: Data] = [:]
    var writeStatus = errSecSuccess
    var readStatus = errSecSuccess
    var deleteStatus = errSecSuccess
    var writes = 0
    func store(_ defaults: MemoryDefaults) -> MusicCredentialStore {
        MusicCredentialStore(defaults: defaults, read: { key in
            guard self.readStatus == errSecSuccess else { return (nil, self.readStatus) }
            return (self.entries[key], self.entries[key] == nil ? errSecItemNotFound : errSecSuccess)
        }, write: { key, data in
            self.writes += 1
            if self.writeStatus == errSecSuccess { self.entries[key] = data }
            return self.writeStatus
        }, delete: { key in
            if self.deleteStatus == errSecSuccess { self.entries.removeValue(forKey: key) }
            return self.deleteStatus
        })
    }
}

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
}

@main struct SecurityChecks {
    @MainActor static func main() async throws {
        let defaults = MemoryDefaults(), vault = FakeVault()
        for key in MusicCredentialStore.legacyKeys { defaults.set("synthetic", forKey: key) }
        defaults.set([["Name": "session", "Value": "fake-cookie", "Expires": Date(timeIntervalSince1970: 123)]], forKey: "spotAPISessionCookies")
        let store = vault.store(defaults)
        for key in MusicCredentialStore.legacyKeys {
            check(defaults.object(forKey: key) == nil && vault.entries[key] != nil, "Migration must delete plaintext only after protected storage succeeds")
        }
        check((store.array(forKey: "spotAPISessionCookies")?.first as? [String: Any])?["Value"] as? String == "fake-cookie", "Cookie properties must round trip")
        check(vault.store(defaults).string(forKey: "spotifyRefreshToken") == "synthetic", "Credentials survive restart via vault")
        store.set("refreshed", forKey: "spotifyRefreshToken")
        check(defaults.object(forKey: "spotifyRefreshToken") == nil, "Refresh never writes plaintext")
        check(vault.store(defaults).string(forKey: "spotifyRefreshToken") == "refreshed", "Refresh replaces the persisted token")

        let retryDefaults = MemoryDefaults(), retryVault = FakeVault()
        retryDefaults.set("legacy", forKey: "tidalRefreshToken")
        retryVault.writeStatus = errSecInteractionNotAllowed
        let retryStore = retryVault.store(retryDefaults)
        check(retryDefaults.object(forKey: "tidalRefreshToken") as? String == "legacy", "Failed migration must preserve the only copy")
        retryVault.writeStatus = errSecSuccess
        check(retryStore.string(forKey: "tidalRefreshToken") == "legacy", "Migration retries")
        check(retryDefaults.object(forKey: "tidalRefreshToken") == nil, "Successful retry removes plaintext")
        retryVault.readStatus = errSecInteractionNotAllowed
        let before = retryVault.writes
        check(retryStore.string(forKey: "tidalRefreshToken") == nil && retryVault.writes == before, "Locked Keychain must not be overwritten")
        retryVault.readStatus = errSecSuccess

        vault.writeStatus = errSecInteractionNotAllowed
        check(!store.set("session-only", forKey: "spotifyRefreshToken"), "Persistence failures are reported")
        check(store.string(forKey: "spotifyRefreshToken") == "session-only", "Failed write can remain in memory")
        check(vault.store(defaults).string(forKey: "spotifyRefreshToken") == nil, "Restart must not revive an older token after failed replacement")
        vault.writeStatus = errSecSuccess
        store.set("new-login", forKey: "spotifyRefreshToken")
        vault.deleteStatus = errSecInteractionNotAllowed
        store.removeObject(forKey: "spotifyRefreshToken")
        check(vault.store(defaults).string(forKey: "spotifyRefreshToken") == nil, "Failed delete must not undo logout on restart")
        print("PASS: credential migration, cookies, refresh, restart, locked vault, failed writes and logout; fake storage only")

        let now = Date(timeIntervalSince1970: 1000)
        var session = OAuthLoginSession()
        check(session.consume(URL(string: "sapphire://callback?code=fake&state=fake")!, now: now) == nil, "Unsolicited callback")
        let attempt = session.begin(clientID: "fixture", now: now)!
        func url(_ prefix: String = "sapphire://callback", _ query: String? = nil) -> URL {
            URL(string: prefix + "?" + (query ?? "code=fake&state=\(attempt.state)"))!
        }
        for bad in [url("sapphire://other"), url("https://callback"), url("sapphire://callback/path"),
                    url("sapphire://user@callback"), url("sapphire://callback:80"),
                    url("sapphire://callback", "code=a&code=b&state=\(attempt.state)"),
                    url("sapphire://callback", "code=a&state=\(attempt.state)&state=\(attempt.state)"),
                    url("sapphire://callback", "code=a&state=wrong"),
                    URL(string: url().absoluteString + "#fragment")!] {
            check(session.consume(bad, now: now) == nil, "Invalid callback accepted")
        }
        check(session.consume(url(), now: now)?.attempt.id == attempt.id, "Correct callback must work after unrelated input")
        check(session.consume(url(), now: now) == nil, "Callback is single-use")
        let older = session.generation
        session.cancel()
        check(session.generation != older, "Logout invalidates an in-flight exchange")
        let expiring = session.begin(clientID: "fixture", now: now)!
        check(session.consume(URL(string: "sapphire://callback?code=a&state=\(expiring.state)")!, now: now.addingTimeInterval(600)) == nil, "Expired login")
        let denied = session.begin(clientID: "fixture", now: now)!
        check(session.consume(URL(string: "sapphire://callback?error=access_denied&state=\(denied.state)")!, now: now) == nil, "Provider cancellation")
        check(session.consume(URL(string: "sapphire://callback?code=a&state=\(denied.state)")!, now: now) == nil, "Cancellation consumes the transaction")
        check(session.begin(clientID: "fixture", random: { _ in nil }) == nil, "Entropy failure must fail closed")
        let vector = OAuthLoginSession.Attempt(id: UUID(), clientID: "fixture", state: "fixture",
            verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", createdAt: now)
        check(vector.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 S256 vector")
        print("PASS: OAuth request binding, exact callback, duplicate fields, replay, expiry, cancellation and PKCE vector")
        await runAuthRaceChecks()

        for sample in ["normal", "\\\"\nreturn 123\n--", "email\"@example.test", "a\\b\tc\r\n中文"] {
            var error: NSDictionary?
            let result = NSAppleScript(source: "return " + AppleScriptLiteral.quoted(sample))?.executeAndReturnError(&error)
            check(error == nil && result?.stringValue == sample, "Script text must remain data")
        }
        print("PASS: AppleScript literals preserve quotes, backslashes, Unicode and line breaks; no app commands")

        for height: CGFloat in [24, 32, 38, 48] {
            let offset = ExpandedPanelLayout.toolbarOffset(menuBarHeight: height, panelTopInset: 0, isFloatingIsland: false, usesTranslucency: true)
            check(offset >= height + 6, "Toolbar must start below menu/status items")
        }
        check(ExpandedPanelLayout.toolbarOffset(menuBarHeight: 32, panelTopInset: 0, isFloatingIsland: true, usesTranslucency: true) == 0, "Floating island keeps bottom controls")
        check(ExpandedPanelLayout.toolbarOffset(menuBarHeight: 32, panelTopInset: 0, isFloatingIsland: false, usesTranslucency: false) == 0, "Opaque layout retains existing geometry")
        check(!PasswordValidationFixture().verifyEmpty(), "Empty password should fail without authentication")
        print("PASS: menu-bar clearance and compiled OpenDirectory password validation path")
    }
}
