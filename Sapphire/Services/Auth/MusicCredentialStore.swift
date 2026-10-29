import Foundation
import Security

/// Secrets never fall back to writing preferences. Legacy values are removed only
/// after a successful Keychain migration; a failed write remains session-only.
@MainActor
final class MusicCredentialStore {
    static let shared = MusicCredentialStore()
    static let legacyKeys = [
        "spotifyAccessToken", "spotifyRefreshToken", "tidalAccessToken", "tidalRefreshToken",
        "spotAPISessionCookies", "spotAPIExternalRefreshToken", "spotAPIExternalClientSecret"
    ]
    private let defaults: UserDefaults
    private let read: (String) -> (Data?, OSStatus)
    private let write: (String, Data) -> OSStatus
    private let delete: (String) -> OSStatus
    private var volatileValues: [String: Any] = [:]
    nonisolated private static let service = "com.cshariq.sapphire.music-credentials"

    init(defaults: UserDefaults = .standard,
         read: @escaping (String) -> (Data?, OSStatus) = {
             KeychainStore.copyData(service: MusicCredentialStore.service, account: $0, synchronizable: false)
         },
         write: @escaping (String, Data) -> OSStatus = {
             KeychainStore.setItem(service: MusicCredentialStore.service, account: $0, data: $1,
                                   accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly, synchronizable: false)
         },
         delete: @escaping (String) -> OSStatus = {
             KeychainStore.deleteItem(service: MusicCredentialStore.service, account: $0, synchronizable: false)
         }) {
        self.defaults = defaults
        self.read = read
        self.write = write
        self.delete = delete
        // Includes old, no-longer-used external-token fields.
        for key in Self.legacyKeys { _ = object(forKey: key) }
    }

    private func deletionKey(_ key: String) -> String { "MusicCredentialDeleted.\(key)" }

    func object(forKey key: String) -> Any? {
        if let value = volatileValues[key] { return value }
        if defaults.bool(forKey: deletionKey(key)) {
            // A failed Keychain delete must never revive a logged-out session.
            _ = delete(key)
            return nil
        }
        let (data, status) = read(key)
        if status == errSecSuccess, let data,
           let dictionary = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
           let value = dictionary["value"] {
            defaults.removeObject(forKey: key)
            return value
        }
        // Do not overwrite an inaccessible or invalid existing Keychain item.
        guard status == errSecItemNotFound, let legacy = defaults.object(forKey: key) else { return nil }
        if let encoded = encode(legacy), write(key, encoded) == errSecSuccess {
            defaults.removeObject(forKey: key)
        }
        return legacy
    }

    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }

    @discardableResult
    func set(_ value: Any?, forKey key: String) -> Bool {
        guard let value else { removeObject(forKey: key); return true }
        guard let data = encode(value) else { return false }
        volatileValues[key] = value
        guard write(key, data) == errSecSuccess else {
            // Prevent an older saved credential from coming back on the next launch.
            defaults.set(true, forKey: deletionKey(key))
            defaults.removeObject(forKey: key)
            print("[MusicCredentialStore] Keychain write unavailable; credential retained for this session only.")
            return false
        }
        volatileValues.removeValue(forKey: key)
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: deletionKey(key))
        return true
    }

    func removeObject(forKey key: String) {
        volatileValues.removeValue(forKey: key)
        defaults.set(true, forKey: deletionKey(key))
        defaults.removeObject(forKey: key)
        _ = delete(key)
    }

    private func encode(_ value: Any) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
    }
}
