// Personal fork update channel. Installation and signature verification are owned by Sparkle.
#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import Sparkle
@preconcurrency import UserNotifications

enum PersonalUpdateChannel {
    static let repository = "timtsui0128/Sapphire"
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
    static let feedURL = URL(string: "https://github.com/\(repository)/releases/latest/download/appcast.xml")!

    static func allowsArchive(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
            && url.user == nil && url.password == nil && url.port == nil
            && url.path.hasPrefix("/\(repository)/releases/download/personal-v")
            && (url.path.hasSuffix(".zip") || url.path.hasSuffix(".delta"))
    }
}

/// A custom user driver keeps the existing localized SwiftUI controls. Sparkle alone
/// downloads, verifies the signed feed/archive, stages, replaces, and relaunches.
@MainActor
final class UpdateChecker: NSObject, ObservableObject, SPUUserDriver, SPUUpdaterDelegate {
    static let shared = UpdateChecker()
    @Published private(set) var status: UpdateStatus = .upToDate
    @Published private(set) var releaseNotes: String?
    @Published private(set) var releaseNotesVersion: String?
    @Published private(set) var releaseNotesURL: URL? = PersonalUpdateChannel.releasesURL
    @Published private(set) var lastCheckAttemptAt: Date?
    @Published private(set) var lastSuccessfulCheckAt: Date?
    @Published private(set) var nextScheduledCheckAt: Date?
    @Published private(set) var lastCheckError: String?
    @Published private(set) var isExtracting = false
    @Published private(set) var automaticallyDownloadsUpdates: Bool
    let isUsingCachedReleaseData = false

    private lazy var engine = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: self, delegate: self)
    private let hostBundle: Bundle
    private let feedURL: URL
    private let archivePolicy: (URL) -> Bool
    private var started = false
    private var cancellation: (() -> Void)?
    private var choice: ((SPUUserUpdateChoice) -> Void)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0
    private var downloadStartedAt: TimeInterval?
    private var lastProgressPublishedAt: TimeInterval = 0
    private var offeredAsset: GitHubReleaseAsset?
    private var privacyObservation: AnyCancellable?
    private let autoDownloadKey = "SapphirePersonalUpdaterAutomaticDownloads"
    private let migratedKey = "SapphirePersonalUpdaterPreferencesMigrated"

    var downloadDetail: String? {
        guard case .downloading = status, !isExtracting else { return nil }
        func size(_ bytes: UInt64) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
        }
        let amount = expectedBytes > 0
            ? L10n.format("%@ of %@", size(receivedBytes), size(expectedBytes))
            : L10n.format("%@ downloaded", size(receivedBytes))
        guard let downloadStartedAt else { return amount }
        let elapsed = ProcessInfo.processInfo.systemUptime - downloadStartedAt
        guard elapsed >= 0.5, receivedBytes > 0 else { return amount }
        let speed = UInt64(min(Double(UInt64.max / 2), Double(receivedBytes) / elapsed))
        return L10n.format("%@ · %@/s", amount, size(speed))
    }

    init(bundle: Bundle = .main, feedURL: URL = PersonalUpdateChannel.feedURL,
         archivePolicy: @escaping (URL) -> Bool = PersonalUpdateChannel.allowsArchive) {
        self.hostBundle = bundle
        self.feedURL = feedURL
        self.archivePolicy = archivePolicy
        // Opt in separately: the old preference meant download-only, whereas Sparkle
        // prepares installation on quit. Never silently broaden that old consent.
        automaticallyDownloadsUpdates = UserDefaults.standard.bool(forKey: "SapphirePersonalUpdaterAutomaticDownloads")
        super.init()
        privacyObservation = SessionPrivacyState.shared.$isSuppressed.sink { [weak self] suppressed in
            guard suppressed else { return }
            self?.cancelDownload()
        }
    }

    private func startIfNeeded() -> Bool {
        guard !started else { return true }
        do {
            try engine.start()
            started = true
            if !UserDefaults.standard.bool(forKey: migratedKey) {
                engine.automaticallyChecksForUpdates = SettingsModel.shared.current.automaticUpdateChecksEnabled
                UserDefaults.standard.set(true, forKey: migratedKey)
            }
            return true
        } catch {
            fail(error)
            return false
        }
    }

    func startPeriodicChecks(interval: TimeInterval) {
        // Sparkle owns the scheduler, retry timing, and persisted check dates.
        _ = startIfNeeded()
    }

    func stopPeriodicChecks() {
        // Sparkle owns scheduling for the process lifetime. This is called while
        // quitting too: cancelling here would discard an update chosen by the user.
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        guard startIfNeeded() else { return }
        engine.automaticallyChecksForUpdates = enabled
        if !enabled { cancelDownload() }
    }

    func setAutomaticDownloadsEnabled(_ enabled: Bool) {
        automaticallyDownloadsUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: autoDownloadKey)
        if enabled, case .available(_, let asset) = status { downloadUpdate(asset: asset) }
    }

    func checkForUpdates() { checkForUpdatesMatchingCurrentChannel() }
    func checkForBetaUpdates() { checkForUpdatesMatchingCurrentChannel() }
    func checkForUpdatesMatchingCurrentChannel() {
        guard !SessionPrivacyState.shouldSuppressUI(), startIfNeeded(), engine.canCheckForUpdates else { return }
        // An offer remains active while its reply is pending; do not strand that reply.
        if choice != nil || readyReply != nil { return }
        engine.checkForUpdates()
    }

    func downloadUpdate(asset: GitHubReleaseAsset) {
        guard !SessionPrivacyState.shouldSuppressUI(), asset == offeredAsset, let reply = choice else { return }
        choice = nil
        reply(.install)
    }

    func installAndRelaunch() {
        guard !SessionPrivacyState.shouldSuppressUI(), let reply = readyReply else { return }
        readyReply = nil
        reply(.install)
    }

    func installAndRelaunchWithoutPassword() { installAndRelaunch() }

    func cancelDownload() {
        let cancel = cancellation
        cancellation = nil
        let pendingChoice = choice
        choice = nil
        let pendingReady = readyReply
        readyReply = nil
        cancel?()
        pendingChoice?(.dismiss)
        // Skip at the ready stage cancels a staged install without skipping its version.
        pendingReady?(.skip)
    }

    private func fail(_ error: Error) {
        lastCheckError = error.localizedDescription
        status = .error(error.localizedDescription)
        isExtracting = false
    }

    private func announce(version: String) {
        guard !SessionPrivacyState.shouldSuppressUI() else { return }
        let key = "SapphirePersonalUpdaterLastNotifiedBuild"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        UserDefaults.standard.set(version, forKey: key)
        NotificationCenter.default.post(name: .sapphireUpdateAvailable, object: releaseNotesVersion)
        guard SettingsModel.shared.current.updateAvailableNotificationsEnabled,
              SettingsModel.shared.current.automaticUpdateChecksEnabled, !NSApp.isActive else { return }
        let title = L10n.format("TopLet %@ is available", releaseNotesVersion ?? version)
        let body = L10n.string("Open Settings → About → Updates to install the new version.")
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            // A quiet notification fits the personal fork's silent-alert preference.
            center.add(UNNotificationRequest(identifier: "sapphire-personal-update-\(version)", content: content, trigger: nil))
        }
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    // MARK: Sparkle delegate
    func feedURLString(for updater: SPUUpdater) -> String? { feedURL.absoluteString }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { [] } // Stable personal releases only.

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !SessionPrivacyState.shouldSuppressUI() else { throw CocoaError(.userCancelled) }
        lastCheckAttemptAt = Date()
        lastCheckError = nil
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard !item.isInformationOnlyUpdate, let url = item.fileURL, archivePolicy(url) else {
            throw NSError(domain: "SapphirePersonalUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.string("The update is not from this personal fork's release channel.")])
        }
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        lastSuccessfulCheckAt = Date()
        lastCheckError = nil
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        nextScheduledCheckAt = Date().addingTimeInterval(delay)
    }

    func updaterWillNotScheduleUpdateCheck(_ updater: SPUUpdater) { nextScheduledCheckAt = nil }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let ns = error as NSError
        if ns.domain == SUSparkleErrorDomain && ns.code == SUError.noUpdateError.rawValue { return }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return }
        fail(error)
    }

    // MARK: Custom user driver (main thread by Sparkle contract)
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: SettingsModel.shared.current.automaticUpdateChecksEnabled, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        status = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard !SessionPrivacyState.shouldSuppressUI(), let url = appcastItem.fileURL else { reply(.dismiss); return }
        cancellation = nil
        choice = reply
        releaseNotesVersion = appcastItem.displayVersionString
        releaseNotes = appcastItem.itemDescription
        releaseNotesURL = PersonalUpdateChannel.releasesURL
        let asset = GitHubReleaseAsset(name: url.lastPathComponent, browserDownloadUrl: url, size: Int64(clamping: appcastItem.contentLength), digest: nil, contentType: "application/zip")
        offeredAsset = asset
        status = .available(version: appcastItem.displayVersionString, asset: asset)
        announce(version: appcastItem.versionString)
        if automaticallyDownloadsUpdates { downloadUpdate(asset: asset) }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        releaseNotes = String(data: downloadData.data, encoding: .utf8)
    }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { /* The signed inline notes remain available. */ }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        status = .upToDate
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        fail(error)
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        receivedBytes = 0
        expectedBytes = 0
        downloadStartedAt = ProcessInfo.processInfo.systemUptime
        lastProgressPublishedAt = 0
        isExtracting = false
        status = .downloading(progress: 0)
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expectedBytes = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let (total, overflow) = receivedBytes.addingReportingOverflow(length)
        receivedBytes = overflow ? .max : total
        let now = ProcessInfo.processInfo.systemUptime
        // Keep byte accounting exact while avoiding a full Settings redraw for
        // every network chunk. Always publish completion, including tiny files.
        guard now - lastProgressPublishedAt >= 0.1 || (expectedBytes > 0 && receivedBytes >= expectedBytes) else { return }
        lastProgressPublishedAt = now
        status = .downloading(progress: expectedBytes > 0 ? min(1, Double(receivedBytes) / Double(expectedBytes)) : 0)
    }
    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil // Sparkle no longer permits cancellation after extraction begins.
        isExtracting = true
        status = .downloading(progress: 1)
    }
    func showExtractionReceivedProgress(_ progress: Double) { /* Keep the preparation indicator indeterminate. */ }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        isExtracting = false
        guard !SessionPrivacyState.shouldSuppressUI() else { reply(.skip); return }
        readyReply = reply
        status = .readyToInstall
        NotificationCenter.default.post(name: .sapphireUpdateAvailable, object: releaseNotesVersion)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        status = .installing
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {
        cancellation = nil
        choice = nil
        readyReply = nil
        isExtracting = false
        offeredAsset = nil
        if case .error = status { return }
        if let version = releaseNotesVersion {
            status = .deferred(version: version)
        } else {
            status = .upToDate
        }
    }
}
#endif
