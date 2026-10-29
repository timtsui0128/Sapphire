import Foundation
import CryptoKit
import Security

/// A short-lived, single-use authorization transaction. The generation also lets
/// callers reject a network response arriving after logout or a newer login.
struct OAuthLoginSession {
    struct Attempt {
        let id: UUID
        let clientID: String
        let state: String
        let verifier: String
        let createdAt: Date
        var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
        fileprivate static func base64URL(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
    }
    private(set) var generation = UUID()
    private var pending: Attempt?

    mutating func begin(clientID: String, now: Date = Date(),
                        random: (Int) -> Data? = OAuthLoginSession.randomBytes) -> Attempt? {
        cancel()
        guard !clientID.isEmpty, let verifier = random(48), let state = random(32) else { return nil }
        let attempt = Attempt(id: generation, clientID: clientID, state: Attempt.base64URL(state),
                              verifier: Attempt.base64URL(verifier), createdAt: now)
        pending = attempt
        return attempt
    }

    mutating func cancel() { generation = UUID(); pending = nil }

    static func isCallbackURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "sapphire" && parts.host == "callback" && parts.path.isEmpty
            && parts.user == nil && parts.password == nil && parts.port == nil && parts.fragment == nil
    }

    mutating func consume(_ url: URL, now: Date = Date()) -> (code: String, attempt: Attempt)? {
        guard let attempt = pending else { return nil }
        guard now.timeIntervalSince(attempt.createdAt) >= 0,
              now.timeIntervalSince(attempt.createdAt) < 600 else { cancel(); return nil }
        guard Self.isCallbackURL(url), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, states[0].value == attempt.state else { return nil }
        let codes = items.filter { $0.name == "code" }
        if items.contains(where: { $0.name == "error" }) { cancel(); return nil }
        guard codes.count == 1, let code = codes[0].value, !code.isEmpty else { return nil }
        pending = nil
        return (code, attempt)
    }

    private static func randomBytes(_ count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes)
    }
}
