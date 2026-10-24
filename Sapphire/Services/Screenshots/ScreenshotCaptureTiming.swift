import Foundation

enum ScreenshotCaptureTiming: String, CaseIterable, Identifiable {
    case floatingPreview, immediate
    var id: String { rawValue }
    var title: String { self == .immediate ? "Collect immediately" : "Keep floating preview" }
    var showsThumbnail: Bool { self == .floatingPreview }
    var settlingTime: TimeInterval { self == .immediate ? 0.05 : 0.25 }
    var retryDelay: TimeInterval { self == .immediate ? 0.08 : 0.4 }
}

protocol ScreenshotThumbnailPreferences: AnyObject {
    var showThumbnail: Bool? { get set }
    func synchronize() -> Bool
}

final class SystemScreenshotThumbnailPreferences: ScreenshotThumbnailPreferences {
    private let domain = "com.apple.screencapture" as CFString
    var showThumbnail: Bool? {
        get {
            CFPreferencesAppSynchronize(domain)
            return CFPreferencesCopyAppValue("show-thumbnail" as CFString, domain) as? Bool
        }
        set { CFPreferencesSetAppValue("show-thumbnail" as CFString, newValue.map { NSNumber(value: $0) }, domain) }
    }
    func synchronize() -> Bool { CFPreferencesAppSynchronize(domain) }
}

/// Own only the thumbnail preference, and restore it when collection stops.
/// A durable journal lets the next launch recover after an interrupted run.
@MainActor
final class ScreenshotThumbnailLease {
    private struct Journal: Codable {
        let original: Bool?
        let applied: Bool
    }
    private static let journalKey = "ScreenshotShelfThumbnailLease"
    private let defaults: UserDefaults
    private let preferences: ScreenshotThumbnailPreferences

    init(defaults: UserDefaults, preferences: ScreenshotThumbnailPreferences) {
        self.defaults = defaults
        self.preferences = preferences
        restore()
    }

    @discardableResult
    func apply(_ timing: ScreenshotCaptureTiming) -> Bool {
        let saved = journal
        let original: Bool? = saved != nil ? saved!.original : preferences.showThumbnail
        let entry = Journal(original: original, applied: timing.showsThumbnail)
        guard let encoded = try? JSONEncoder().encode(entry) else { return false }
        defaults.set(encoded, forKey: Self.journalKey)
        guard defaults.synchronize() else { return false }
        preferences.showThumbnail = timing.showsThumbnail
        return preferences.synchronize() && preferences.showThumbnail == timing.showsThumbnail
    }

    func restore() {
        guard let entry = journal else { return }
        if preferences.showThumbnail == entry.applied {
            preferences.showThumbnail = entry.original
            guard preferences.synchronize() else { return }
        }
        defaults.removeObject(forKey: Self.journalKey)
    }

    private var journal: Journal? {
        defaults.data(forKey: Self.journalKey).flatMap { try? JSONDecoder().decode(Journal.self, from: $0) }
    }
}
