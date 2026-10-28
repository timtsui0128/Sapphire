import AppKit
import Combine
import CoreServices
import Darwin
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let fileURL: URL
    let capturedAt: Date
    let name: String
    var expiresAt: Date? = nil
    var removeAfterSuccessfulDrag: Bool? = nil
}

enum ScreenshotShelfRetention: String, CaseIterable, Identifiable {
    case persistent
    case twentyFourHours
    case afterSuccessfulDrag

    var id: String { rawValue }
    var title: String {
        switch self {
        case .persistent: return "Keep until I remove"
        case .twentyFourHours: return "Delete after 24 hours"
        case .afterSuccessfulDrag: return "Remove after successful drop"
        }
    }
}

/// New automatic captures move into owned storage; manually imported files are copied.
@MainActor
final class ScreenshotShelfManager: ObservableObject {
    static let shared = ScreenshotShelfManager()

    @Published private(set) var items: [ScreenshotShelfItem] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var watchedFolder: URL?
    @Published private(set) var lastError: String?
    @Published private(set) var captureTimingError: String?
    @Published private(set) var pendingScreenshotOpenIDs: Set<UUID> = []
    let storageFolderURL: URL
    @Published var captureTiming: ScreenshotCaptureTiming {
        didSet {
            defaults.set(captureTiming.rawValue, forKey: Self.timingKey)
            worker.setCaptureTiming(captureTiming)
            applyCaptureTiming()
        }
    }
    @Published var retention: ScreenshotShelfRetention {
        didSet {
            defaults.set(retention.rawValue, forKey: Self.retentionKey)
            worker.setRetention(retention)
        }
    }
    @Published var captureEnabled: Bool {
        didSet {
            defaults.set(captureEnabled, forKey: Self.enabledKey)
            captureEnabled ? startMonitoring() : stopMonitoring()
        }
    }

    private static let enabledKey = "ScreenshotShelfCaptureEnabled"
    private static let folderKey = "ScreenshotShelfFolderOverride"
    private static let retentionKey = "ScreenshotShelfRetention"
    private static let timingKey = "ScreenshotShelfCaptureTiming"
    private let defaults: UserDefaults
    private let worker: ScreenshotShelfWorker
    private let thumbnailLease: ScreenshotThumbnailLease
    private(set) var isSessionSuppressed = false

    /// An isolated directory and defaults suite can be supplied by tests.
    init(storageURL: URL? = nil, defaults: UserDefaults = .standard,
         thumbnailPreferences: ScreenshotThumbnailPreferences = SystemScreenshotThumbnailPreferences()) {
        self.defaults = defaults
        thumbnailLease = ScreenshotThumbnailLease(defaults: defaults, preferences: thumbnailPreferences)
        let timing = defaults.string(forKey: Self.timingKey).flatMap(ScreenshotCaptureTiming.init(rawValue:)) ?? .floatingPreview
        captureTiming = timing
        captureEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let initialRetention = defaults.string(forKey: Self.retentionKey)
            .flatMap(ScreenshotShelfRetention.init(rawValue:)) ?? .persistent
        retention = initialRetention
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let root = storageURL ?? support
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", isDirectory: true)
            .appendingPathComponent("ScreenshotShelf", isDirectory: true)
        storageFolderURL = root.standardizedFileURL
        worker = ScreenshotShelfWorker(storageURL: storageFolderURL, retention: initialRetention, captureTiming: timing)
        worker.onItems = { [weak self] items in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.items = items
                    self.pendingScreenshotOpenIDs.formIntersection(items.map(\.id))
                }
            }
        }
        worker.onAutomaticCapture = { [weak self] id, generation in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, !self.isSessionSuppressed, self.captureEnabled,
                          self.worker.isCurrentSession(generation), self.items.contains(where: { $0.id == id }) else { return }
                    self.pendingScreenshotOpenIDs.insert(id)
                }
            }
        }
        worker.onState = { [weak self] monitoring, folder, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isMonitoring = monitoring && self.captureEnabled && !self.isSessionSuppressed
                    self.watchedFolder = folder
                    self.lastError = error
                }
            }
        }
        worker.load()
    }

    /// Session privacy is independent of the user's saved capture preference.
    func setSessionSuppressed(_ suppressed: Bool) {
        guard isSessionSuppressed != suppressed else { return }
        isSessionSuppressed = suppressed
        worker.setSessionSuppressed(suppressed)
        if suppressed {
            markScreenshotsViewed()
            stopMonitoring()
        } else {
            // A new start date excludes files created during the locked/inactive session.
            startMonitoring()
        }
    }

    func startMonitoring() {
        guard captureEnabled, !isSessionSuppressed else { return }
        applyCaptureTiming()
        let override = defaults.string(forKey: Self.folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        worker.start(override: override, since: Date())
    }

    func stopMonitoring() {
        isMonitoring = false
        worker.stop()
        thumbnailLease.restore()
    }

    private func applyCaptureTiming() {
        guard captureEnabled, !isSessionSuppressed else { thumbnailLease.restore(); return }
        guard defaults.string(forKey: Self.timingKey) != nil else { return }
        captureTimingError = thumbnailLease.apply(captureTiming) ? nil
            : L10n.string("Could not change the macOS floating preview. Use Shift-Command-5 → Options → Show Floating Thumbnail.")
    }

    func chooseFolder() {
        guard !isSessionSuppressed else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose Screenshot Folder")
        panel.message = L10n.string("Choose the folder where macOS saves your screenshots.")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = watchedFolder
        panel.prompt = L10n.string("Watch Folder")
        panel.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let self, !self.isSessionSuppressed, let url = panel.url else { return }
                self.defaults.set(url.path, forKey: Self.folderKey)
                self.worker.stop()
                self.startMonitoring()
            }
        }
    }

    func useSystemScreenshotFolder() {
        defaults.removeObject(forKey: Self.folderKey)
        worker.stop()
        startMonitoring()
    }

    func importFiles(from urls: [URL]) {
        guard !isSessionSuppressed else { return }
        worker.importFiles(urls)
    }

    func retryFailedOperations() {
        guard !isSessionSuppressed else { return }
        worker.retryFailedOperations()
        if captureEnabled { startMonitoring() }
    }

    func removeItems(ids: Set<UUID>) {
        guard !isSessionSuppressed else { return }
        worker.removeItems(ids)
    }

    func didFinishDrag(ids: Set<UUID>, accepted: Bool) {
        guard !isSessionSuppressed, accepted else { return }
        worker.removeItemsAfterSuccessfulDrag(ids)
    }

    /// A new saved system screenshot gets one explicit notch click ahead of
    /// Now Playing/remembered navigation. History and imports never set this.
    @discardableResult
    func consumeScreenshotOpenRequest() -> Bool {
        guard !isSessionSuppressed, !pendingScreenshotOpenIDs.isEmpty else { return false }
        markScreenshotsViewed()
        defaults.set("screenshots", forKey: "ScreenshotShelfSelectedTab")
        return true
    }

    func markScreenshotsViewed() {
        if !pendingScreenshotOpenIDs.isEmpty { pendingScreenshotOpenIDs.removeAll() }
    }

    @discardableResult
    func copyItems(ids: Set<UUID>) -> Bool {
        guard !isSessionSuppressed else { return false }
        let urls = items.filter { ids.contains($0.id) }.map(\.fileURL)
        guard !urls.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects(urls.map { $0 as NSURL })
    }
}

/// All directory reads, image validation, moves/copies, and manifest writes run on this queue.
private final class ScreenshotShelfWorker {
    var onItems: (([ScreenshotShelfItem]) -> Void)?
    var onState: ((Bool, URL?, String?) -> Void)?
    var onAutomaticCapture: ((UUID, UInt64) -> Void)?

    func isCurrentSession(_ generation: UInt64) -> Bool { sessionGate.allows(generation) }

    private struct FileIdentity: Hashable, Codable {
        let device: Int32
        let inode: UInt64
        let created: Date
    }

    private struct Stamp: Equatable, Codable {
        let size: Int
        let modified: Date
        let created: Date
        let identity: FileIdentity
    }

    private struct Candidate {
        let url: URL
        let firstSeen: Date
        var lastStamp: Stamp?
        var stableSince: Date
        var isConfirmedScreenshot = false
    }

    private struct Manifest: Codable {
        let version: Int
        let items: [ScreenshotShelfItem]
    }

    private struct MoveJournal: Codable {
        let itemID: UUID
        let sourceURL: URL
        let destinationURL: URL
        let originalStamp: Stamp
    }

    private let queue = DispatchQueue(label: "com.sapphire.screenshot-shelf", qos: .userInitiated)
    private let sessionGate = ScreenshotCaptureSessionGate()
    private var monitoringGeneration: UInt64?
    private let storageURL: URL
    private let manifestURL: URL
    private var items: [ScreenshotShelfItem] = []
    private var overrideFolder: URL?
    private var folder: URL?
    private var startedAt: Date?
    private var knownPaths: [String: FileIdentity] = [:]
    private var candidates: [String: Candidate] = [:]
    private var failedCandidates: [String: Candidate] = [:]
    private var failedImports: Set<URL> = []
    private var collectedIdentities: Set<FileIdentity> = []
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var retry: DispatchWorkItem?
    private var lastPreferenceCheck = Date.distantPast
    private var lastError: String?
    private var hasFolderError = false
    private var storageIsReady = false
    private var retention: ScreenshotShelfRetention
    private var captureTiming: ScreenshotCaptureTiming
    private var expiryTimer: DispatchSourceTimer?
    private static let moveJournalName = ".pending-screenshot-move.json"

    init(storageURL: URL, retention: ScreenshotShelfRetention, captureTiming: ScreenshotCaptureTiming) {
        self.storageURL = storageURL.standardizedFileURL
        self.retention = retention
        self.captureTiming = captureTiming
        manifestURL = self.storageURL.appendingPathComponent("manifest.json")
    }

    deinit {
        watcher?.cancel()
        timer?.cancel()
        expiryTimer?.cancel()
        retry?.cancel()
    }

    func load() {
        queue.async { [weak self] in self?.loadFromDisk() }
    }

    func setRetention(_ retention: ScreenshotShelfRetention) {
        queue.async { [weak self] in self?.retention = retention }
    }

    func setCaptureTiming(_ timing: ScreenshotCaptureTiming) {
        queue.async { [weak self] in self?.captureTiming = timing }
    }

    private func loadFromDisk() {
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
                guard manifest.version == 1 else {
                    throw NSError(domain: "ScreenshotShelf", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "This screenshot collection was saved by a newer version of Sapphire."
                    ])
                }
                items = manifest.items.filter {
                    owns($0.fileURL, id: $0.id) && FileManager.default.fileExists(atPath: $0.fileURL.path)
                }
                items.sort { $0.capturedAt > $1.capturedAt }
            }
            storageIsReady = true
            let recoveryError = recoverPendingMoves()
            cleanOrphanedCopies()
            onItems?(items)
            report(error: recoveryError)
            expireItemsIfNeeded()
        } catch {
            // Do not replace a history we could not read with an empty manifest.
            storageIsReady = false
            report(error: L10n.format("Could not load screenshot collection: %@", error.localizedDescription))
        }
    }

    func retryFailedOperations() {
        let generation = sessionGate.generation
        queue.async { [weak self] in
            guard let self, self.sessionGate.allows(generation) else { return }
            if !self.storageIsReady { self.loadFromDisk() }
            if self.storageIsReady, let recoveryError = self.recoverPendingMoves() {
                self.report(error: recoveryError)
            }
            let imports = self.failedImports.filter {
                guard let stamp = Self.stamp($0) else { return true }
                return !self.collectedIdentities.contains(stamp.identity)
            }
            if !imports.isEmpty { self.importNow(Array(imports), generation: generation) }
            let now = Date()
            // Only previously failed captures get another attempt. Successful captures stay
            // consumed even if the user removed them from the collection or renamed the source.
            for (path, failed) in self.failedCandidates {
                guard let stamp = Self.stamp(failed.url),
                      !self.collectedIdentities.contains(stamp.identity),
                      Self.isScreenshot(failed.url) else {
                    self.failedCandidates.removeValue(forKey: path)
                    continue
                }
                self.candidates[path] = Candidate(
                    url: failed.url, firstSeen: now, lastStamp: nil,
                    stableSince: now, isConfirmedScreenshot: true
                )
            }
            self.watcher?.cancel()
            self.watcher = nil
            self.lastPreferenceCheck = .distantPast
            self.refreshFolder()
            if self.startedAt != nil { self.processCandidates() }
        }
    }

    func setSessionSuppressed(_ suppressed: Bool) {
        // Invalidate queued work synchronously, without waiting for filesystem I/O.
        sessionGate.setSuppressed(suppressed)
        if suppressed {
            queue.async { [weak self] in
                self?.failedCandidates.removeAll()
                self?.failedImports.removeAll()
            }
        }
    }

    func start(override: URL?, since: Date) {
        let generation = sessionGate.generation
        queue.async { [weak self] in
            guard let self, self.sessionGate.allows(generation) else { return }
            guard self.startedAt == nil else { return }
            self.monitoringGeneration = generation
            self.startedAt = since
            self.overrideFolder = override?.standardizedFileURL
            self.lastPreferenceCheck = .distantPast
            self.refreshFolder()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(300))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.refreshFolder()
                self.scan()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.startedAt = nil
            self.monitoringGeneration = nil
            self.watcher?.cancel()
            self.watcher = nil
            self.timer?.cancel()
            self.timer = nil
            self.retry?.cancel()
            self.retry = nil
            self.candidates.removeAll()
            self.knownPaths.removeAll()
            self.onState?(false, self.folder, self.lastError)
        }
    }

    func importFiles(_ urls: [URL]) {
        let generation = sessionGate.generation
        queue.async { [weak self] in
            guard let self, self.sessionGate.allows(generation) else { return }
            self.importNow(urls, generation: generation)
        }
    }

    private func importNow(_ urls: [URL], generation: UInt64) {
        guard sessionGate.allows(generation) else { return }
        var seen: Set<URL> = []
        var failures = 0
        for url in urls where url.isFileURL && seen.insert(url.standardizedFileURL).inserted {
            guard sessionGate.allows(generation) else { return }
            do {
                try collect(url, capturedAt: Date(), moveSource: false, generation: generation)
                failedImports.remove(url)
            } catch {
                failures += 1
                failedImports.insert(url)
                report(error: L10n.format("Could not add %@: %@", url.lastPathComponent, error.localizedDescription))
            }
        }
        if failures == 0 { report(error: nil) }
    }

    func removeItems(_ ids: Set<UUID>) {
        queue.async { [weak self] in self?.removeItemsNow(ids) }
    }

    func removeItemsAfterSuccessfulDrag(_ ids: Set<UUID>) {
        queue.async { [weak self] in
            guard let self else { return }
            let removable = Set(self.items.filter {
                ids.contains($0.id) && $0.removeAfterSuccessfulDrag == true
            }.map(\.id))
            self.removeItemsNow(removable)
        }
    }

    @discardableResult
    private func removeItemsNow(_ ids: Set<UUID>) -> Bool {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return true }
        let remaining = items.filter { !ids.contains($0.id) }
        do {
            // Preserve the same drag grace period if Sapphire exits before delayed deletion.
            for item in removed where owns(item.fileURL, id: item.id) {
                let journal = item.fileURL.deletingLastPathComponent().appendingPathComponent(Self.moveJournalName)
                if FileManager.default.fileExists(atPath: journal.path) {
                    try FileManager.default.removeItem(at: journal)
                }
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date()], ofItemAtPath: item.fileURL.deletingLastPathComponent().path
                )
            }
            try persist(remaining)
            items = remaining
            onItems?(remaining)
            scheduleExpiry()
            // Give an in-flight Finder/browser drag time to finish reading its files.
            queue.asyncAfter(deadline: .now() + 120) { [weak self] in
                guard let self else { return }
                for item in removed where self.owns(item.fileURL, id: item.id)
                    && !self.items.contains(where: { $0.id == item.id }) {
                    try? FileManager.default.removeItem(at: item.fileURL.deletingLastPathComponent())
                }
            }
            return true
        } catch {
            report(error: L10n.format("Could not remove screenshots: %@", error.localizedDescription))
            return false
        }
    }

    private func expireItemsIfNeeded() {
        let now = Date()
        let expired = Set(items.filter { $0.expiresAt.map { $0 <= now } ?? false }.map(\.id))
        let succeeded = removeItemsNow(expired)
        scheduleExpiry(minimumDelay: succeeded ? 0.05 : 60)
    }

    private func scheduleExpiry(minimumDelay: TimeInterval = 0.05) {
        expiryTimer?.cancel()
        expiryTimer = nil
        guard let earliest = items.compactMap(\.expiresAt).min() else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + max(minimumDelay, earliest.timeIntervalSinceNow), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.expireItemsIfNeeded() }
        expiryTimer = timer
        timer.resume()
    }

    private func refreshFolder() {
        guard startedAt != nil, sessionGate.allows(monitoringGeneration) else { return }
        // CFPreferences is refreshed so changing Screenshot.app's destination takes effect.
        let now = Date()
        guard folder == nil || watcher == nil || now.timeIntervalSince(lastPreferenceCheck) >= 4 else { return }
        lastPreferenceCheck = now
        let desired = (overrideFolder ?? Self.systemScreenshotFolder()).standardizedFileURL
        guard desired != folder || watcher == nil else { return }
        let changed = desired != folder
        watcher?.cancel()
        watcher = nil
        folder = desired
        if changed {
            knownPaths.removeAll()
            candidates.removeAll()
        }
        let descriptor = open(desired.path, O_EVTONLY)
        if descriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .attrib, .extend],
                queue: queue
            )
            source.setEventHandler { [weak self, weak source] in
                guard let self, let source else { return }
                if !source.data.intersection([.rename, .delete]).isEmpty {
                    source.cancel()
                    self.watcher = nil
                }
                self.scan()
            }
            source.setCancelHandler { close(descriptor) }
            watcher = source
            source.resume()
        }
        scan()
    }

    private func scan() {
        guard let startedAt, let folder, sessionGate.allows(monitoringGeneration) else { return }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey,
                                             .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            let now = Date()
            let presentPaths = Set(urls.map(\.path))
            knownPaths = knownPaths.filter { presentPaths.contains($0.key) }
            candidates = candidates.filter { presentPaths.contains($0.key) }
            for url in urls {
                let path = url.path
                guard let stamp = Self.stamp(url), knownPaths[path] != stamp.identity else { continue }
                knownPaths[path] = stamp.identity
                guard !isInsideStorage(url), stamp.created >= startedAt,
                      !collectedIdentities.contains(stamp.identity), Self.isImageFileName(url) else { continue }
                candidates[path] = Candidate(url: url, firstSeen: now, lastStamp: nil, stableSince: now)
            }
            processCandidates()
            if hasFolderError { report(error: nil) }
            else { onState?(true, folder, lastError) }
        } catch {
            report(error: L10n.format("Cannot watch %@: %@. Choose the screenshot folder to grant access.", folder.lastPathComponent, error.localizedDescription), isFolderError: true)
        }
    }

    private func processCandidates() {
        guard let generation = monitoringGeneration, sessionGate.allows(generation) else { return }
        let now = Date()
        for (path, var candidate) in candidates {
            guard sessionGate.allows(generation) else { return }
            // macOS can write metadata and image data after the directory creation event.
            guard let stamp = Self.stamp(candidate.url), !collectedIdentities.contains(stamp.identity) else {
                candidates.removeValue(forKey: path)
                failedCandidates.removeValue(forKey: path)
                continue
            }
            guard now.timeIntervalSince(candidate.firstSeen) < 60 else {
                if candidate.isConfirmedScreenshot { failedCandidates[path] = candidate }
                candidates.removeValue(forKey: path)
                continue
            }
            guard stamp.size > 0 else { continue }
            if candidate.lastStamp != stamp {
                candidate.lastStamp = stamp
                candidate.stableSince = now
                candidates[path] = candidate
                continue
            }
            guard now.timeIntervalSince(candidate.stableSince) >= captureTiming.settlingTime,
                  Self.isScreenshot(candidate.url) else { continue }
            candidate.isConfirmedScreenshot = true
            candidates[path] = candidate
            do {
                try collect(candidate.url, capturedAt: stamp.created, moveSource: true, generation: generation)
                candidates.removeValue(forKey: path)
                failedCandidates.removeValue(forKey: path)
                report(error: nil)
            } catch {
                failedCandidates[path] = candidate
                if (error as NSError).domain == "ScreenshotShelfMove" {
                    // Failed transactions have already been rolled back (or safely journaled).
                    // Avoid repeatedly moving a source while its destination needs user attention.
                    candidates.removeValue(forKey: path)
                    report(error: error.localizedDescription)
                    continue
                }
                // Retry incomplete writes; surface an error if a confirmed screenshot stays unreadable.
                if now.timeIntervalSince(candidate.firstSeen) > 10 {
                    report(error: L10n.format("Could not save %@: %@", candidate.url.lastPathComponent, error.localizedDescription))
                }
            }
        }
        scheduleRetryIfNeeded()
    }

    private func scheduleRetryIfNeeded() {
        guard !candidates.isEmpty, retry == nil, startedAt != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retry = nil
            guard self.startedAt != nil else { return }
            self.processCandidates()
        }
        retry = work
        queue.asyncAfter(deadline: .now() + captureTiming.retryDelay, execute: work)
    }

    private func collect(_ source: URL, capturedAt: Date, moveSource: Bool, generation: UInt64) throws {
        try requireActiveSession(generation)
        guard storageIsReady else {
            throw NSError(domain: "ScreenshotShelf", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The screenshot collection is unavailable."
            ])
        }
        guard let before = Self.stamp(source), before.size > 0, Self.isCompleteImage(source) else {
            throw NSError(domain: "ScreenshotShelf", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "The file is not a complete image or PDF."
            ])
        }
        let id = UUID()
        let directory = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        let journal = MoveJournal(itemID: id, sourceURL: source, destinationURL: destination, originalStamp: before)
        let journalURL = directory.appendingPathComponent(Self.moveJournalName)
        var sourceWasMoved = false
        do {
            try requireActiveSession(generation)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if moveSource {
                var destinationAttributes = stat()
                guard stat(directory.path, &destinationAttributes) == 0,
                      destinationAttributes.st_dev == before.identity.device else {
                    throw Self.moveError(
                        "This screenshot is on another disk and cannot be moved automatically. The original was left in \(source.deletingLastPathComponent().path). Use Add screenshots to copy it."
                    )
                }
                // The journal is committed before removing the source name. Startup recovery
                // can restore an interrupted move instead of treating its only copy as an orphan.
                try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
                guard Self.stamp(source) == before else {
                    throw Self.moveError("The screenshot changed before it could be moved. The original was left in its folder; try again.")
                }
                try requireActiveSession(generation)
                try Self.renameWithoutReplacing(source, to: destination)
                sourceWasMoved = true
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            let checkedURL = moveSource ? destination : source
            guard Self.stamp(checkedURL) == before, Self.isCompleteImage(destination) else {
                throw NSError(domain: "ScreenshotShelf", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "The screenshot is still being written."
                ])
            }
            let item = ScreenshotShelfItem(
                id: id, fileURL: destination, capturedAt: capturedAt, name: source.lastPathComponent,
                expiresAt: retention == .twentyFourHours ? capturedAt.addingTimeInterval(24 * 60 * 60) : nil,
                removeAfterSuccessfulDrag: retention == .afterSuccessfulDrag ? true : nil
            )
            let updated = (items + [item]).sorted { $0.capturedAt > $1.capturedAt }
            try requireActiveSession(generation)
            try persist(updated)
            items = updated
            collectedIdentities.insert(before.identity)
            if moveSource { try? FileManager.default.removeItem(at: journalURL) }
            onItems?(updated)
            if moveSource { onAutomaticCapture?(id, generation) }
            scheduleExpiry()
        } catch {
            if sourceWasMoved {
                let originalError = error
                let restored: URL
                do {
                    restored = try restoreMovedFile(journal)
                } catch {
                    // Never delete the only remaining file when rollback cannot finish.
                    throw Self.moveError(
                        "The screenshot is safe in \(destination.path), but its move could not be completed or restored. Retry after fixing folder access. \(error.localizedDescription)"
                    )
                }
                try? FileManager.default.removeItem(at: directory)
                let recoveryNote = restored == source ? "" : " It was recovered as \(restored.path)."
                throw Self.moveError("Could not save the screenshot; its file was restored.\(recoveryNote) \(originalError.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: directory)
            if moveSource { throw Self.moveError(error.localizedDescription) }
            else { throw error }
        }
    }

    private func requireActiveSession(_ generation: UInt64) throws {
        guard sessionGate.allows(generation) else {
            throw NSError(domain: "ScreenshotShelfSession", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Screenshot collection paused while the Mac is locked or inactive."
            ])
        }
    }

    private static func moveError(_ description: String) -> NSError {
        NSError(domain: "ScreenshotShelfMove", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private static func renameWithoutReplacing(_ source: URL, to destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSFilePathErrorKey: source.path
            ])
        }
    }

    /// Returns the original path, or a distinct recovery name if somebody reused that path.
    private func restoreMovedFile(_ journal: MoveJournal) throws -> URL {
        do {
            try Self.renameWithoutReplacing(journal.destinationURL, to: journal.sourceURL)
            return journal.sourceURL
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST) {
            let source = journal.sourceURL
            let recoveredName = "\(source.deletingPathExtension().lastPathComponent) (Recovered \(journal.itemID.uuidString))"
            var recovered = source.deletingLastPathComponent().appendingPathComponent(recoveredName)
            if !source.pathExtension.isEmpty { recovered.appendPathExtension(source.pathExtension) }
            try Self.renameWithoutReplacing(journal.destinationURL, to: recovered)
            return recovered
        }
    }

    private func recoverPendingMoves() -> String? {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: storageURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        var recoveryError: String?
        for directory in directories {
            guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            let journalURL = directory.appendingPathComponent(Self.moveJournalName)
            guard FileManager.default.fileExists(atPath: journalURL.path) else { continue }
            do {
                let journal = try JSONDecoder().decode(MoveJournal.self, from: Data(contentsOf: journalURL))
                guard journal.itemID == id, journal.sourceURL.isFileURL,
                      owns(journal.destinationURL, id: id) else {
                    throw Self.moveError("An interrupted screenshot move has an invalid recovery record.")
                }
                if items.contains(where: { $0.id == id && $0.fileURL == journal.destinationURL }) {
                    try FileManager.default.removeItem(at: journalURL)
                    continue
                }
                if let movedStamp = Self.stamp(journal.destinationURL) {
                    guard movedStamp.identity == journal.originalStamp.identity else {
                        throw Self.moveError("An interrupted screenshot changed; its file was preserved in \(directory.path).")
                    }
                    let restored = try restoreMovedFile(journal)
                    if restored != journal.sourceURL {
                        recoveryError = "An interrupted screenshot was recovered as \(restored.path), leaving the newer file untouched."
                    }
                } else if FileManager.default.fileExists(atPath: journal.destinationURL.path) {
                    throw Self.moveError("An interrupted screenshot could not be verified; its file was preserved in \(directory.path).")
                }
                try FileManager.default.removeItem(at: journalURL)
                if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                    try? FileManager.default.removeItem(at: directory)
                }
            } catch {
                recoveryError = "Could not recover an interrupted screenshot move. Its files were preserved in \(directory.path). \(error.localizedDescription)"
            }
        }
        return recoveryError
    }

    private func persist(_ items: [ScreenshotShelfItem]) throws {
        guard storageIsReady else {
            throw NSError(domain: "ScreenshotShelf", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The screenshot collection is unavailable."
            ])
        }
        let data = try JSONEncoder().encode(Manifest(version: 1, items: items))
        try data.write(to: manifestURL, options: .atomic)
    }

    private func report(error: String?, isFolderError: Bool = false) {
        lastError = error
        hasFolderError = error != nil && isFolderError
        onState?(startedAt != nil && !hasFolderError, folder, error)
    }

    private func isInsideStorage(_ url: URL) -> Bool {
        let root = storageURL.resolvingSymlinksInPath().path + "/"
        return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root)
    }

    private func owns(_ url: URL, id: UUID) -> Bool {
        let expected = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
        return url.deletingLastPathComponent().standardizedFileURL == expected
            && isInsideStorage(url)
    }

    private func cleanOrphanedCopies() {
        let activeIDs = Set(items.map(\.id))
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: storageURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-120)
        for directory in directories {
            guard let id = UUID(uuidString: directory.lastPathComponent), !activeIDs.contains(id),
                  !FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.moveJournalName).path),
                  let values = try? directory.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey
                  ]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified < cutoff,
                  isInsideStorage(directory) else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func stamp(_ url: URL) -> Stamp? {
        // lstat avoids both following symlinks and Foundation URL resource-value caching.
        var attributes = stat()
        guard lstat(url.path, &attributes) == 0, (attributes.st_mode & S_IFMT) == S_IFREG else { return nil }
        let created = Date(timeIntervalSince1970:
            TimeInterval(attributes.st_birthtimespec.tv_sec) + TimeInterval(attributes.st_birthtimespec.tv_nsec) / 1_000_000_000)
        let modified = Date(timeIntervalSince1970:
            TimeInterval(attributes.st_mtimespec.tv_sec) + TimeInterval(attributes.st_mtimespec.tv_nsec) / 1_000_000_000)
        let identity = FileIdentity(device: attributes.st_dev, inode: attributes.st_ino, created: created)
        return Stamp(size: Int(attributes.st_size), modified: modified, created: created, identity: identity)
    }

    private static func isImageFileName(_ url: URL) -> Bool {
        // Native formats remain recognizable when LaunchServices is not available yet.
        if ["png", "jpg", "jpeg", "tif", "tiff", "heic", "heif", "pdf"].contains(url.pathExtension.lowercased()) {
            return true
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    private static func isCompleteImage(_ url: URL) -> Bool {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            return CGImageSourceGetCount(source) > 0 && CGImageSourceGetStatus(source) == .statusComplete
                && CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        }
        return CGPDFDocument(url as CFURL).map { $0.numberOfPages > 0 } ?? false
    }

    private static func isScreenshot(_ url: URL) -> Bool {
        // This survives localized/renamed screenshots and does not mistake ordinary PNGs for captures.
        let attribute = "com.apple.metadata:kMDItemIsScreenCapture"
        let length = getxattr(url.path, attribute, nil, 0, 0, 0)
        if length > 0, length < 4096 {
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes {
                getxattr(url.path, attribute, $0.baseAddress, length, 0, 0)
            }
            if read == length,
               let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
               screenshotFlag(value) {
                return true
            }
        }
        guard let metadata = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let value = MDItemCopyAttribute(metadata, "kMDItemIsScreenCapture" as CFString) else { return false }
        return screenshotFlag(value)
    }

    private static func screenshotFlag(_ value: Any) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            return ["1", "true", "yes"].contains(string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        return false
    }

    private static func systemScreenshotFolder() -> URL {
        let domain = "com.apple.screencapture" as CFString
        CFPreferencesAppSynchronize(domain)
        if let location = CFPreferencesCopyAppValue("location" as CFString, domain) as? String,
           !location.isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
}

/// A generation prevents pre-lock work from becoming valid again immediately after unlock.
private final class ScreenshotCaptureSessionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var suppressed = false
    private var value: UInt64 = 0

    var generation: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func setSuppressed(_ newValue: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard suppressed != newValue else { return }
        suppressed = newValue
        value &+= 1
    }

    func allows(_ generation: UInt64?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !suppressed && generation == value
    }
}
