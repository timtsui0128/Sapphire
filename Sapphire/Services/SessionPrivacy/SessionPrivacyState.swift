import AppKit
import Combine
import CoreGraphics
import Foundation

struct SessionPrivacySnapshot: Equatable, Sendable {
    let screenIsLocked: Bool?
    let sessionIsActive: Bool?

    static let unknown = SessionPrivacySnapshot(screenIsLocked: nil, sessionIsActive: nil)
    var requiresSuppression: Bool { screenIsLocked != false || sessionIsActive != true }

    static func decode(_ dictionary: [String: Any]?) -> SessionPrivacySnapshot {
        guard let dictionary else { return .unknown }
        // The lock key is absent for an unlocked Quartz session. The two
        // console/login keys are public CGSession keys and must both be true.
        let locked = dictionary["CGSSessionScreenIsLocked"] as? Bool ?? false
        let console = dictionary["kCGSSessionOnConsoleKey"] as? Bool
        let loggedIn = dictionary["kCGSessionLoginDoneKey"] as? Bool
        let active: Bool?
        if console == false || loggedIn == false { active = false }
        else if console == true && loggedIn == true { active = true }
        else { active = nil }
        return SessionPrivacySnapshot(screenIsLocked: locked, sessionIsActive: active)
    }
}

/// Notification latches are independent of a potentially lagging CG snapshot.
/// Waking a screen or becoming the active session never clears a lock event.
struct SessionPrivacyReducer: Equatable, Sendable {
    private(set) var system: SessionPrivacySnapshot
    private(set) var lockNotificationIsActive = false
    private(set) var inactiveNotificationIsActive = false

    init(snapshot: SessionPrivacySnapshot) { system = snapshot }
    var isSuppressed: Bool {
        lockNotificationIsActive || inactiveNotificationIsActive || system.requiresSuppression
    }

    mutating func refresh(_ snapshot: SessionPrivacySnapshot) { system = snapshot }

    mutating func setLocked(_ locked: Bool, snapshot: SessionPrivacySnapshot) {
        lockNotificationIsActive = locked
        system = snapshot
    }

    mutating func setSessionActive(_ active: Bool, snapshot: SessionPrivacySnapshot) {
        inactiveNotificationIsActive = !active
        system = snapshot
    }
}

private final class SessionPrivacyAccessGate: @unchecked Sendable {
    private let lock = NSLock()
    private var suppressed = true
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return suppressed }
        set { lock.lock(); suppressed = newValue; lock.unlock() }
    }
}

@MainActor
final class SessionPrivacyState: ObservableObject {
    private nonisolated static let processGate = SessionPrivacyAccessGate()
    static let shared = SessionPrivacyState(publishesProcessState: true)

    /// Cheap, thread-safe check for event taps and input dispatch. It starts
    /// suppressed before the main-actor service has read the initial session.
    nonisolated static var isSuppressedSnapshot: Bool { processGate.value }

    /// Display boundaries also probe the system, closing the gap before a lock
    /// notification reaches the main actor. No singleton is created off-thread.
    nonisolated static func shouldSuppressUI() -> Bool {
        isSuppressedSnapshot || systemSnapshot().requiresSuppression
    }

    nonisolated static func systemSnapshot() -> SessionPrivacySnapshot {
        SessionPrivacySnapshot.decode(CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    @Published private(set) var isSuppressed: Bool
    private var state: SessionPrivacyReducer
    private let snapshotProvider: () -> SessionPrivacySnapshot
    private let publishesProcessState: Bool
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var settlingTask: Task<Void, Never>?
    private var transitionGeneration = UUID()

    /// Injected instances are isolated from the process gate and can use local
    /// notification centers, so tests never post real lock/unlock notifications.
    init(
        snapshotProvider: @escaping () -> SessionPrivacySnapshot = SessionPrivacyState.systemSnapshot,
        distributedCenter: NotificationCenter? = nil,
        workspaceCenter: NotificationCenter? = nil,
        observesNotifications: Bool = true,
        publishesProcessState: Bool = false
    ) {
        self.snapshotProvider = snapshotProvider
        self.publishesProcessState = publishesProcessState
        state = SessionPrivacyReducer(snapshot: snapshotProvider())
        isSuppressed = state.isSuppressed
        if publishesProcessState { Self.processGate.value = isSuppressed }
        if observesNotifications {
            installObservers(
                distributed: distributedCenter ?? DistributedNotificationCenter.default(),
                workspace: workspaceCenter ?? NSWorkspace.shared.notificationCenter
            )
            // Close the initial read/observer-install race.
            refreshFromSystem()
            if isSuppressed { scheduleSettlingRefreshes() }
        }
    }

    deinit {
        settlingTask?.cancel()
        for (center, token) in observers { center.removeObserver(token) }
    }

    func refreshFromSystem() {
        state.refresh(snapshotProvider())
        publish()
    }

    func setLocked(_ locked: Bool) {
        cancelSettlingRefreshes()
        state.setLocked(locked, snapshot: snapshotProvider())
        publish()
        if !locked { scheduleSettlingRefreshes() }
    }

    private func setSessionActive(_ active: Bool) {
        cancelSettlingRefreshes()
        state.setSessionActive(active, snapshot: snapshotProvider())
        publish()
        if active { scheduleSettlingRefreshes() }
    }

    private func publish() {
        let suppressed = state.isSuppressed
        // Synchronous guards must see the new state inside @Published sinks.
        if publishesProcessState { Self.processGate.value = suppressed }
        if isSuppressed != suppressed { isSuppressed = suppressed }
    }

    private func installObservers(distributed: NotificationCenter, workspace: NotificationCenter) {
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.setLocked(true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.setLocked(false) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.setSessionActive(false) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.setSessionActive(true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.refreshFromSystem() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.refreshFromSystem() }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        action: @escaping @MainActor (SessionPrivacyState) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func cancelSettlingRefreshes() {
        transitionGeneration = UUID()
        settlingTask?.cancel()
        settlingTask = nil
    }

    private func scheduleSettlingRefreshes() {
        guard isSuppressed else { return }
        let generation = transitionGeneration
        settlingTask = Task { [weak self] in
            // Unlock/active notifications can arrive just before CGSession is
            // updated. Only reread; these retries never clear notification latches.
            for delay in [0.05, 0.2, 0.75, 1.5] {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard let self, self.transitionGeneration == generation else { return }
                self.refreshFromSystem()
                if !self.isSuppressed { return }
            }
        }
    }
}
