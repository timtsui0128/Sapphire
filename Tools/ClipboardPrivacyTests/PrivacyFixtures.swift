import AppKit
import Combine

// No secure store, settings, event tap, or live general-pasteboard writes are used by these checks.
enum PrivacyFixture {
    static let pasteboard = NSPasteboard.withUniqueName()
}

struct FixtureClipboardSettings {
    var clipboardMonitoringEnabled = true
    var clipboardHistoryUnlimited = true
    var clipboardHistoryLimit = 200
    var clipboardHistoryStorageLimitMB = 512
    var clipboardIgnoreConcealedItems = true
    var clipboardIgnoredAppBundleIDs: [String] = []
}

@MainActor final class SettingsModel {
    static let shared = SettingsModel()
    var settings = FixtureClipboardSettings()
    var current: FixtureClipboardSettings { settings }
    func changes<T: Equatable>(of pick: (FixtureClipboardSettings) -> T) -> AnyPublisher<T, Never> {
        Just(pick(settings)).eraseToAnyPublisher()
    }
}
@MainActor final class NotchRuntimeState {
    static let shared = NotchRuntimeState()
    var shouldReduceBackgroundWork = false
    var reductionChanges: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
}
@MainActor final class ActiveAppMonitor {
    static let shared = ActiveAppMonitor()
    var activeAppBundleID: String? = nil
}
@MainActor final class EventMonitorHub {
    static let shared = EventMonitorHub()
    func register(for events: [NSEvent.EventType], handler: @escaping (NSEvent) -> Void) -> [NSEvent.EventType: UUID] {
        Dictionary(uniqueKeysWithValues: events.map { ($0, UUID()) })
    }
    func unregister(tokens: [NSEvent.EventType: UUID]) {}
}
final class ClipboardSecureStore: @unchecked Sendable {
    init(appDirectory: URL, legacyFileURL: URL) {}
    func load() -> ([ClipboardItem], Bool) { ([], false) }
    func persist(_ snapshot: [ClipboardItem], rewriting: Set<String>) {}
    func persistedIDSnapshot() -> Set<String> { [] }
}
enum ClipboardImageLoader {
    static var store: ClipboardSecureStore?
    static func load(id: String) -> Data? { nil }
}
extension Notification.Name {
    static let continuityClipboardReceived = Notification.Name("PrivacyFixture.continuityClipboardReceived")
}
extension NSPasteboard.PasteboardType {
    static let sapphireSource = NSPasteboard.PasteboardType("org.nspasteboard.source")
}

/// Deterministically holds asynchronous jobs so checks can lock before a read/write starts.
@MainActor final class PasteboardLane {
    static let shared = PasteboardLane()
    private var jobs: [() -> Void] = []
    var queuedCount: Int { jobs.count }
    func run<T>(timeout: TimeInterval = 2, _ work: @escaping (NSPasteboard) -> T?,
                completion: @escaping @MainActor (T?) -> Void,
                didFinish: (@MainActor () -> Void)? = nil) {
        jobs.append {
            completion(work(PrivacyFixture.pasteboard))
            didFinish?()
        }
    }
    func write(_ work: @escaping (NSPasteboard) -> Bool,
               completion: (@MainActor (Int?) -> Void)? = nil) {
        run { pasteboard -> Int? in
            work(pasteboard) ? pasteboard.changeCount : nil
        } completion: { completion?($0) }
    }
    func flush() {
        let pending = jobs
        jobs.removeAll()
        pending.forEach { $0() }
    }
}
