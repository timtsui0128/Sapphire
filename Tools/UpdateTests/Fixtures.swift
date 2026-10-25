// Test-only app and privacy dependencies; never linked into Sapphire.
import AppKit
import Combine
@MainActor final class SessionPrivacyState: ObservableObject {
    static let shared = SessionPrivacyState()
    @Published var isSuppressed = false
    static func shouldSuppressUI() -> Bool { shared.isSuppressed }
}
struct Settings { var automaticUpdateChecksEnabled = false; var updateAvailableNotificationsEnabled = false }
@MainActor final class SettingsModel { static let shared = SettingsModel(); var current = Settings() }
enum L10n {
    static func string(_ value: String) -> String { value }
    static func format(_ value: String, _ arguments: CVarArg...) -> String { String(format: value, arguments: arguments) }
}
extension Notification.Name { static let sapphireUpdateAvailable = Notification.Name("sapphireUpdateAvailable") }
