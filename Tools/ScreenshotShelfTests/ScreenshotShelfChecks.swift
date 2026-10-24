import AppKit
import Darwin
import Foundation

private final class ThumbnailPreferencesFixture: ScreenshotThumbnailPreferences {
    var showThumbnail: Bool?
    var writes = 0
    init(_ value: Bool?) { showThumbnail = value }
    func synchronize() -> Bool { writes += 1; return true }
}

private enum CheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

/// Exercises the real capture worker and AppKit drag payload without starting Sapphire.
@main
struct ScreenshotShelfChecks {
    @MainActor
    static func main() async {
        do {
            try await checkCaptureAndPersistence()
            try await checkSessionPrivacy()
            try await checkStorageRetry()
            try await checkRetentionAndManualImports()
            try await checkMoveRollbackAndRecovery()
            try await checkCaptureTiming()
            try checkScreenshotActivitySuppression()
            try checkNativeDragPayload()
            print("PASS: all screenshot shelf checks")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func checkCaptureAndPersistence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapphire-screenshot-checks-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let storage = root.appendingPathComponent("shelf", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A volatile suite overrides only this instance; live screenshot settings stay untouched.
        let defaults = UserDefaults(suiteName: "ScreenshotShelfChecks.\(UUID().uuidString)")!
        defaults.setVolatileDomain(
            ["ScreenshotShelfFolderOverride": source.path, "ScreenshotShelfCaptureEnabled": true],
            forName: UserDefaults.argumentDomain
        )

        let oldScreenshot = source.appendingPathComponent("Older screenshot.png")
        try writeImage(to: oldScreenshot, screenshotMetadata: true)
        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSinceNow: -60)],
            ofItemAtPath: oldScreenshot.path
        )
        let manager = ScreenshotShelfManager(storageURL: storage, defaults: defaults)
        manager.startMonitoring()
        defer { manager.stopMonitoring() }
        try await eventually("screenshot folder monitor starts") { manager.isMonitoring }
        try await pause(0.7)
        try check(manager.items.isEmpty, "Starting monitoring imported old screenshots")
        print("PASS: startup baseline excludes pre-existing screenshots")

        // Names deliberately do not say 'Screenshot': metadata, not filename, drives capture.
        var originals: [URL] = []
        var originalBytes: [String: Data] = [:]
        for number in 1...5 {
            let url = source.appendingPathComponent("测试 Capture \(number).png")
            try writeImage(to: url, screenshotMetadata: true)
            originalBytes[url.lastPathComponent] = try Data(contentsOf: url)
            originals.append(url)
            try await pause(0.03)
        }
        let ordinaryImage = source.appendingPathComponent("Screenshot ordinary image.png")
        try writeImage(to: ordinaryImage, screenshotMetadata: false)
        do {
            try await eventually("five new screenshots are collected", timeout: 12) { manager.items.count == 5 }
        } catch {
            throw CheckError.failed(
                "\(error); count=\(manager.items.count), folder=\(manager.watchedFolder?.path ?? "nil"), error=\(manager.lastError ?? "nil")"
            )
        }
        let captured = manager.items
        try check(
            captured.map(\.capturedAt) == captured.map(\.capturedAt).sorted(by: >),
            "Collected screenshots are not ordered by capture date"
        )
        for item in captured {
            let original = source.appendingPathComponent(item.name)
            try check(item.fileURL != original, "Shelf still references the original screenshot path")
            try check(
                try Data(contentsOf: item.fileURL) == originalBytes[item.name],
                "Stored screenshot bytes differ from the original"
            )
            try check(!FileManager.default.fileExists(atPath: original.path),
                      "An automatically captured screenshot was copied instead of moved")
        }
        try check(!captured.contains(where: { $0.name == ordinaryImage.lastPathComponent }),
                  "Ordinary PNG without screenshot metadata was collected")
        try check(FileManager.default.fileExists(atPath: oldScreenshot.path), "Startup moved a pre-existing screenshot")
        try check(FileManager.default.fileExists(atPath: ordinaryImage.path), "Collector moved an ordinary image")
        print("PASS: five new screenshots move into ordered owned storage; old and unrelated files stay")

        // Repeated write/attribute notifications must not add the same capture again.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: ordinaryImage.path)
        try await pause(2.6)
        try check(manager.items.map(\.id) == captured.map(\.id), "Repeated events duplicated screenshots")
        print("PASS: repeated directory notifications do not duplicate captures")

        let alias = source.appendingPathComponent("Capture alias.png")
        try FileManager.default.linkItem(at: captured[1].fileURL, to: alias)
        let renamed = source.appendingPathComponent("Renamed capture.png")
        try FileManager.default.moveItem(at: alias, to: renamed)
        try await pause(2.6)
        try check(manager.items.map(\.id) == captured.map(\.id), "Renaming a captured screenshot duplicated it")
        print("PASS: renaming a captured screenshot does not create a second attachment")

        manager.stopMonitoring()
        let reloaded = ScreenshotShelfManager(storageURL: storage, defaults: defaults)
        try await eventually("persisted screenshot collection reloads") { reloaded.items.count == 5 }
        try check(reloaded.items == captured, "Reload changed screenshot IDs, paths, or order")
        print("PASS: all five captures and their order survive manager reload")

        let removed = captured[0]
        reloaded.removeItems(ids: [removed.id])
        try await eventually("selected screenshot is removed") { reloaded.items.count == 4 }
        try check(FileManager.default.fileExists(atPath: oldScreenshot.path), "Shelf removal deleted an old unrelated screenshot")
        try check(FileManager.default.fileExists(atPath: ordinaryImage.path), "Shelf removal deleted an ordinary image")
        try check(
            FileManager.default.fileExists(atPath: removed.fileURL.path),
            "Removal deleted its copy immediately while an in-flight drag may still read it"
        )
        let afterRemoval = ScreenshotShelfManager(storageURL: storage, defaults: defaults)
        try await eventually("removal is persisted") { afterRemoval.items.count == 4 }
        try check(!afterRemoval.items.contains(where: { $0.id == removed.id }), "Removed item reappeared on reload")
        print("PASS: removal persists, leaves unrelated files, and preserves in-flight drag grace")

        // Invalid imported data should report an error without inserting a broken attachment.
        let invalidImage = source.appendingPathComponent("incomplete.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: invalidImage)
        afterRemoval.importFiles(from: [invalidImage])
        try await eventually("invalid image reports an error") { afterRemoval.lastError != nil }
        try check(afterRemoval.items.count == 4, "Invalid image was inserted into the shelf")
        print("PASS: incomplete image imports cannot create broken attachments")

        // Screenshot tools can reuse a filename; a new file identity must still be detected.
        afterRemoval.startMonitoring()
        defer { afterRemoval.stopMonitoring() }
        try await eventually("reloaded folder monitor starts") { afterRemoval.isMonitoring }
        let replaced = originals[0]
        try writeImage(to: replaced, screenshotMetadata: true, metadataValue: "1")
        try await eventually("replacement screenshot at the same path is collected", timeout: 10) {
            afterRemoval.items.count == 5
        }
        try check(
            afterRemoval.items.filter { $0.name == replaced.lastPathComponent }.count == 2,
            "A new screenshot reusing a filename replaced its earlier retained copy"
        )
        try await eventually("successful capture clears a previous transient error") {
            afterRemoval.lastError == nil
        }
        print("PASS: filename reuse and string screenshot metadata retain a distinct new capture")
    }

    @MainActor
    private static func checkSessionPrivacy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapphire-screenshot-privacy-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let storage = root.appendingPathComponent("shelf", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "ScreenshotShelfPrivacy.\(UUID().uuidString)")!
        defaults.setVolatileDomain(
            ["ScreenshotShelfFolderOverride": source.path, "ScreenshotShelfCaptureEnabled": true],
            forName: UserDefaults.argumentDomain
        )
        let manager = ScreenshotShelfManager(storageURL: storage, defaults: defaults)
        manager.startMonitoring()
        defer { manager.stopMonitoring() }
        try await eventually("privacy fixture starts") { manager.isMonitoring }
        let retained = source.appendingPathComponent("Retained before lock.png")
        try writeImage(to: retained, screenshotMetadata: true)
        try await eventually("pre-lock capture is retained") { manager.items.count == 1 }
        let originalItems = manager.items
        let queued = source.appendingPathComponent("Pending when locked.png")
        try writeImage(to: queued, screenshotMetadata: true)
        manager.setSessionSuppressed(true)
        manager.startMonitoring()
        manager.retryFailedOperations()
        try await pause(0.7)
        let locked = source.appendingPathComponent("Created while locked.png")
        try writeImage(to: locked, screenshotMetadata: true)
        manager.importFiles(from: [locked])
        try await pause(1)
        try check(!manager.isMonitoring && manager.captureEnabled, "Privacy pause changed the saved capture setting or restarted")
        try check(manager.items == originalItems, "Locked session captured or removed items")
        try check(!manager.copyItems(ids: Set(originalItems.map(\.id))), "Locked shelf wrote to the clipboard")
        try check(FileManager.default.fileExists(atPath: locked.path), "Locked capture was moved")
        manager.setSessionSuppressed(false)
        try await eventually("unlock restarts screenshot monitoring") { manager.isMonitoring }
        manager.retryFailedOperations()
        try await pause(2.6)
        try check(manager.items == originalItems, "Unlock replayed a locked or queued screenshot")
        try check(FileManager.default.fileExists(atPath: queued.path), "A pending capture moved after unlock")
        let resumed = source.appendingPathComponent("Created after unlock.png")
        try writeImage(to: resumed, screenshotMetadata: true)
        try await eventually("new unlocked capture is collected") { manager.items.count == 2 }
        try check(manager.items.contains(where: { $0.id == originalItems[0].id }), "Privacy transition discarded history")
        manager.captureEnabled = false
        manager.setSessionSuppressed(true)
        manager.setSessionSuppressed(false)
        try await pause(0.5)
        try check(!manager.captureEnabled && !manager.isMonitoring, "Unlock enabled a disabled screenshot preference")
        print("PASS: session privacy pauses capture, rejects queued/locked images on unlock, and preserves history/preferences")
    }

    @MainActor
    private static func checkStorageRetry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapphire-screenshot-retry-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let storage = root.appendingPathComponent("shelf", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A regular file at the storage-directory path simulates an unavailable destination.
        try Data("temporarily blocked".utf8).write(to: storage)
        let defaults = UserDefaults(suiteName: "ScreenshotShelfRetry.\(UUID().uuidString)")!
        defaults.setVolatileDomain(
            ["ScreenshotShelfFolderOverride": source.path, "ScreenshotShelfCaptureEnabled": true],
            forName: UserDefaults.argumentDomain
        )
        let manager = ScreenshotShelfManager(storageURL: storage, defaults: defaults)
        manager.startMonitoring()
        defer { manager.stopMonitoring() }
        try await eventually("unavailable storage is reported") { manager.lastError != nil }
        try await eventually("source folder is monitored while storage is unavailable") {
            manager.watchedFolder != nil
        }
        let screenshot = source.appendingPathComponent("Capture while storage unavailable.png")
        try writeImage(to: screenshot, screenshotMetadata: true)
        try await pause(1)
        try check(manager.items.isEmpty, "Blocked storage unexpectedly retained a screenshot")
        try check(FileManager.default.fileExists(atPath: screenshot.path), "Unavailable storage moved a screenshot")

        try FileManager.default.removeItem(at: storage)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        manager.retryFailedOperations()
        try await eventually("Retry recovers storage and the pending screenshot", timeout: 10) {
            manager.items.count == 1 && manager.lastError == nil
        }
        let id = manager.items[0].id
        manager.removeItems(ids: [id])
        try await eventually("recovered screenshot is removed") { manager.items.isEmpty }
        manager.retryFailedOperations()
        try await pause(2.6)
        try check(manager.items.isEmpty, "Retry resurrected a successfully captured and removed item")
        try check(!FileManager.default.fileExists(atPath: screenshot.path),
                  "A recovered automatic capture did not move out of the source folder")
        print("PASS: Retry repairs unavailable storage without resurrecting removed captures")
    }

    @MainActor
    private static func checkRetentionAndManualImports() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapphire-screenshot-retention-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let storage = root.appendingPathComponent("shelf", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "ScreenshotShelfRetentionChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.setVolatileDomain(
            ["ScreenshotShelfCaptureEnabled": false], forName: UserDefaults.argumentDomain
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ScreenshotShelfManager(storageURL: storage, defaults: defaults)
        try check(manager.retention == .persistent, "Default retention is not persistent")
        try check(manager.storageFolderURL == storage.standardizedFileURL, "Storage folder URL is incorrect")

        let permanentSource = source.appendingPathComponent("Keep.png")
        try writeImage(to: permanentSource, screenshotMetadata: false)
        manager.importFiles(from: [permanentSource])
        try await eventually("permanent manual import") { manager.items.count == 1 }
        let permanent = manager.items[0]
        try check(permanent.expiresAt == nil && permanent.removeAfterSuccessfulDrag != true,
                  "Persistent import has an automatic removal policy")

        manager.retention = .twentyFourHours
        let expiringSource = source.appendingPathComponent("One day.png")
        try writeImage(to: expiringSource, screenshotMetadata: false)
        manager.importFiles(from: [expiringSource])
        try await eventually("24-hour manual import") { manager.items.count == 2 }
        let oneDay = manager.items.first { $0.name == expiringSource.lastPathComponent }!
        try check(abs((oneDay.expiresAt?.timeIntervalSince(oneDay.capturedAt) ?? 0) - 86_400) < 0.01,
                  "24-hour retention does not expire one day after intake")
        try check(oneDay.removeAfterSuccessfulDrag != true, "24-hour item would also clear after a drop")

        manager.retention = .afterSuccessfulDrag
        let dropSource = source.appendingPathComponent("After drop.png")
        try writeImage(to: dropSource, screenshotMetadata: false)
        manager.importFiles(from: [dropSource])
        try await eventually("drop-removal manual import") { manager.items.count == 3 }
        let afterDrop = manager.items.first { $0.name == dropSource.lastPathComponent }!
        try check(afterDrop.removeAfterSuccessfulDrag == true && afterDrop.expiresAt == nil,
                  "Drop-removal import has the wrong snapshot policy")
        manager.retention = .persistent
        try check(manager.items.first { $0.id == permanent.id } == permanent,
                  "Changing retention rewrote a previously retained screenshot")
        try check(manager.items.first { $0.id == oneDay.id } == oneDay,
                  "Changing retention rewrote a previously scheduled expiry")

        let allIDs = Set(manager.items.map(\.id))
        manager.didFinishDrag(ids: allIDs, accepted: false)
        try await pause(0.2)
        try check(manager.items.count == 3, "Canceled drag removed attachments")
        manager.didFinishDrag(ids: allIDs, accepted: true)
        try await eventually("accepted drop removes only opted-in items") { manager.items.count == 2 }
        try check(Set(manager.items.map(\.id)) == [permanent.id, oneDay.id],
                  "Accepted drop removed a persistent or 24-hour screenshot")
        try check(FileManager.default.fileExists(atPath: afterDrop.fileURL.path),
                  "Accepted drop deleted the file before the recipient could finish reading it")
        for url in [permanentSource, expiringSource, dropSource] {
            try check(FileManager.default.fileExists(atPath: url.path), "Manual import moved or deleted its original")
        }
        print("PASS: retention is captured per item; manual imports copy; canceled drops retain all files")
        print("PASS: accepted drops remove only opted-in items and preserve the file-reading grace period")

        // Use an imminent expiry in the persisted fixture instead of waiting a whole day.
        // The permanent record deliberately omits optional fields, as older manifests do.
        var imminent = oneDay
        imminent.expiresAt = Date(timeIntervalSinceNow: 0.5)
        let manifest = TestManifest(version: 1, items: [permanent, imminent])
        try JSONEncoder().encode(manifest).write(
            to: storage.appendingPathComponent("manifest.json"), options: .atomic
        )
        defaults.set(ScreenshotShelfRetention.twentyFourHours.rawValue, forKey: "ScreenshotShelfRetention")
        let reloaded = ScreenshotShelfManager(storageURL: storage, defaults: defaults)
        try await eventually("paused collection loads old and timed records") { reloaded.items.count == 2 }
        try await eventually("expiry runs while screenshot capture is disabled") {
            reloaded.items.map(\.id) == [permanent.id]
        }
        try check(reloaded.items[0].expiresAt == nil, "New default retroactively expired an old manifest record")
        try check(FileManager.default.fileExists(atPath: imminent.fileURL.path),
                  "Expiry ignored the in-flight file-reading grace period")
        try check(FileManager.default.fileExists(atPath: expiringSource.path), "Expiry deleted an imported original")
        print("PASS: old manifests stay permanent; timed expiry works while capture is paused")
    }

    @MainActor
    private static func checkMoveRollbackAndRecovery() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapphire-screenshot-transactions-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let storage = root.appendingPathComponent("shelf", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: "ScreenshotShelfTransactions.\(UUID().uuidString)")!
        defaults.setVolatileDomain(
            ["ScreenshotShelfFolderOverride": source.path, "ScreenshotShelfCaptureEnabled": true],
            forName: UserDefaults.argumentDomain
        )
        let manager = ScreenshotShelfManager(storageURL: storage, defaults: defaults)
        manager.startMonitoring()
        defer { manager.stopMonitoring() }
        try await eventually("transaction fixture monitor starts") { manager.isMonitoring }
        let manifestURL = storage.appendingPathComponent("manifest.json")
        // Force only the manifest commit to fail after the image itself has moved successfully.
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)
        let screenshot = source.appendingPathComponent("Rollback.png")
        try writeImage(to: screenshot, screenshotMetadata: true)
        let originalBytes = try Data(contentsOf: screenshot)
        try await eventually("failed manifest commit restores screenshot", timeout: 10) {
            manager.lastError?.contains("restored") == true
        }
        try check(manager.items.isEmpty, "A failed manifest commit published a screenshot")
        try check(try Data(contentsOf: screenshot) == originalBytes,
                  "Failed manifest commit did not restore the original screenshot")
        try FileManager.default.removeItem(at: manifestURL)
        manager.retryFailedOperations()
        try await eventually("transaction retry commits once storage is repaired") {
            manager.items.count == 1 && manager.lastError == nil
        }
        try check(!FileManager.default.fileExists(atPath: screenshot.path),
                  "Successful transaction retry left an automatic screenshot at the source")
        try check(try Data(contentsOf: manager.items[0].fileURL) == originalBytes,
                  "Successful transaction retry changed screenshot bytes")
        manager.stopMonitoring()
        print("PASS: failed manifest commit rolls back the move, and Retry safely completes it")

        let recoveryStorage = root.appendingPathComponent("recovery-shelf", isDirectory: true)
        let recoverySource = source.appendingPathComponent("Interrupted.png")
        try writeImage(to: recoverySource, screenshotMetadata: true)
        let recoveryBytes = try Data(contentsOf: recoverySource)
        let journal = try prepareInterruptedMove(source: recoverySource, storage: recoveryStorage)
        let replacement = Data("newer file must not be overwritten".utf8)
        try replacement.write(to: recoverySource)
        let recovered = source.appendingPathComponent("Interrupted (Recovered \(journal.itemID.uuidString)).png")
        let recoveryManager = ScreenshotShelfManager(storageURL: recoveryStorage, defaults: defaults)
        try await eventually("interrupted move recovers without overwriting a newer file") {
            recoveryManager.lastError?.contains("recovered as") == true
        }
        try check(try Data(contentsOf: recoverySource) == replacement,
                  "Recovery overwrote a newer file using the original name")
        try check(try Data(contentsOf: recovered) == recoveryBytes,
                  "Recovery did not preserve the interrupted screenshot")
        try check(!FileManager.default.fileExists(atPath: journal.destinationURL.path),
                  "Recovery left an extra uncommitted destination file")
        try check(recoveryManager.items.isEmpty, "Recovery published an uncommitted manifest item")
        print("PASS: interrupted moves recover with a distinct name when the original path was reused")

        let blockedSourceFolder = root.appendingPathComponent("removed-source", isDirectory: true)
        try FileManager.default.createDirectory(at: blockedSourceFolder, withIntermediateDirectories: true)
        let blockedSource = blockedSourceFolder.appendingPathComponent("Preserve.png")
        try writeImage(to: blockedSource, screenshotMetadata: true)
        let blockedStorage = root.appendingPathComponent("blocked-recovery-shelf", isDirectory: true)
        let blockedJournal = try prepareInterruptedMove(source: blockedSource, storage: blockedStorage)
        try FileManager.default.removeItem(at: blockedSourceFolder)
        let ownedDirectory = blockedJournal.destinationURL.deletingLastPathComponent()
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -600)], ofItemAtPath: ownedDirectory.path
        )
        let blockedManager = ScreenshotShelfManager(storageURL: blockedStorage, defaults: defaults)
        try await eventually("unavailable recovery destination reports a safe retained file") {
            blockedManager.lastError?.contains("files were preserved") == true
        }
        try check(FileManager.default.fileExists(atPath: blockedJournal.destinationURL.path),
                  "Orphan cleanup deleted the only copy from an interrupted move")
        try check(FileManager.default.fileExists(
            atPath: ownedDirectory.appendingPathComponent(".pending-screenshot-move.json").path
        ), "Failed recovery discarded its journal")
        print("PASS: failed recovery preserves both its screenshot and journal beyond orphan cleanup age")
    }

    private struct TestManifest: Codable {
        let version: Int
        let items: [ScreenshotShelfItem]
    }

    private struct TestFileIdentity: Codable {
        let device: Int32
        let inode: UInt64
        let created: Date
    }

    private struct TestStamp: Codable {
        let size: Int
        let modified: Date
        let created: Date
        let identity: TestFileIdentity
    }

    private struct TestMoveJournal: Codable {
        let itemID: UUID
        let sourceURL: URL
        let destinationURL: URL
        let originalStamp: TestStamp
    }

    private static func prepareInterruptedMove(source: URL, storage: URL) throws -> TestMoveJournal {
        var attributes = stat()
        try check(lstat(source.path, &attributes) == 0, "Could not stat interrupted-move fixture")
        let created = Date(timeIntervalSince1970:
            TimeInterval(attributes.st_birthtimespec.tv_sec) + TimeInterval(attributes.st_birthtimespec.tv_nsec) / 1_000_000_000)
        let modified = Date(timeIntervalSince1970:
            TimeInterval(attributes.st_mtimespec.tv_sec) + TimeInterval(attributes.st_mtimespec.tv_nsec) / 1_000_000_000)
        let id = UUID()
        let directory = storage.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = TestMoveJournal(
            itemID: id, sourceURL: source, destinationURL: directory.appendingPathComponent(source.lastPathComponent),
            originalStamp: TestStamp(
                size: Int(attributes.st_size), modified: modified, created: created,
                identity: TestFileIdentity(device: attributes.st_dev, inode: attributes.st_ino, created: created)
            )
        )
        try JSONEncoder().encode(TestManifest(version: 1, items: [])).write(
            to: storage.appendingPathComponent("manifest.json"), options: .atomic
        )
        try JSONEncoder().encode(journal).write(
            to: directory.appendingPathComponent(".pending-screenshot-move.json"), options: .atomic
        )
        try FileManager.default.moveItem(at: source, to: journal.destinationURL)
        return journal
    }

    @MainActor
    private static func checkCaptureTiming() async throws {
        for original: Bool? in [nil, true, false] {
            let name = "ScreenshotTimingLease.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let preference = ThumbnailPreferencesFixture(original)
            let lease = ScreenshotThumbnailLease(defaults: defaults, preferences: preference)
            try check(preference.writes == 0, "An unused timing option changed macOS preferences")
            try check(lease.apply(.immediate) && preference.showThumbnail == false, "Immediate mode did not skip the preview")
            try check(lease.apply(.floatingPreview) && preference.showThumbnail == true, "Preview mode did not re-enable the preview")
            lease.restore()
            try check(preference.showThumbnail == original, "Stopping failed to restore the exact original value, including an absent key")
            _ = lease.apply(.immediate)
            let recovered = ScreenshotThumbnailLease(defaults: defaults, preferences: preference)
            try check(preference.showThumbnail == original, "An interrupted run did not recover its thumbnail setting")
            _ = recovered.apply(.immediate)
            preference.showThumbnail = true
            recovered.restore()
            try check(preference.showThumbnail == true, "Restore overwrote a newer choice made in Screenshot.app")
        }
        print("PASS: immediate/preview choice, exact preference restoration, crash recovery and external preference changes (isolated stores only)")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-fast-check-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "ScreenshotTimingWorker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.setVolatileDomain(["ScreenshotShelfFolderOverride": source.path, "ScreenshotShelfCaptureEnabled": true], forName: UserDefaults.argumentDomain)
        let preference = ThumbnailPreferencesFixture(true)
        let manager = ScreenshotShelfManager(storageURL: root.appendingPathComponent("owned"), defaults: defaults, thumbnailPreferences: preference)
        manager.startMonitoring()
        defer { manager.stopMonitoring() }
        try await eventually("timing monitor starts") { manager.isMonitoring }
        try check(preference.writes == 0, "Existing installations must keep their current thumbnail setting until choosing a timing")
        manager.captureTiming = .immediate
        var timings: [ScreenshotCaptureTiming: [Double]] = [:]
        for timing in [ScreenshotCaptureTiming.immediate, .floatingPreview] {
            manager.captureTiming = timing
            for i in 0..<3 {
                let expected = manager.items.count + 1
                let start = Date()
                try writeImage(to: source.appendingPathComponent("\(timing.rawValue)-\(i).png"), screenshotMetadata: true)
                try await eventually("timed complete screenshot", timeout: 4) { manager.items.count == expected }
                timings[timing, default: []].append(Date().timeIntervalSince(start))
            }
        }
        let fast = timings[.immediate]!.sorted()[1]
        let preview = timings[.floatingPreview]!.sorted()[1]
        try check(fast < preview, "Immediate mode did not reduce collection latency after file creation")
        manager.captureTiming = .immediate
        let count = manager.items.count
        let partial = source.appendingPathComponent("partial.png")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: partial)
        let metadata = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        _ = metadata.withUnsafeBytes { setxattr(partial.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, metadata.count, 0, 0) }
        try await pause(0.25)
        try check(manager.items.count == count, "Immediate mode collected an incomplete screenshot")
        try writeImage(to: partial, screenshotMetadata: true)
        try await eventually("complete image replaces its partial write") { manager.items.count == count + 1 }
        manager.setSessionSuppressed(true)
        try check(preference.showThumbnail == true, "Privacy suspension must restore the original preview setting")
        manager.setSessionSuppressed(false)
        try check(preference.showThumbnail == false, "Resuming collection must reapply the saved timing choice")
        manager.captureEnabled = false
        try check(preference.showThumbnail == true, "Disabling collection must restore preview behavior")
        print("PASS: saved-file collection median \(Int(fast * 1000))ms immediate / \(Int(preview * 1000))ms preview; privacy/disable restore preferences")
    }

    @MainActor
    private static func checkScreenshotActivitySuppression() throws {
        let fixture = FileShelfActivityFixture()
        for screenshots in [0, 5, 50] {
            FileShelfActivityFixture.ScreenshotShelfManager.shared.items = Array(repeating: 0, count: screenshots)
            FileShelfActivityFixture.FileShelfManager.shared.files = []
            try check(fixture.candidateCount() == nil, "Screenshot history recreated a permanent file-shelf capsule")
            FileShelfActivityFixture.FileShelfManager.shared.files = [1, 2]
            try check(fixture.candidateCount() == 2, "Screenshot history changed the ordinary file shelf count")
        }
        fixture.settingsModel.current.fileShelfLiveActivityEnabled = false
        try check(fixture.candidateCount() == nil, "The file-shelf activity setting was ignored")
        print("PASS: production file-shelf activity stays absent for 5/50 screenshots while ordinary file activities remain available")
    }

    @MainActor
    private static func checkNativeDragPayload() throws {
        let urls = (1...5).map { URL(fileURLWithPath: "/tmp/测试 Screenshot \($0).png") }
        let items = ScreenshotShelfDragPayload.items(for: urls, at: NSPoint(x: 20, y: 30))
        try check(items.count == 5, "Five selected files did not create five NSDraggingItems")
        let writers = items.compactMap { $0.item as? NSPasteboardWriting }
        try check(writers.count == 5, "A drag item does not provide a native pasteboard writer")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try check(
            pasteboard.writeObjects(writers),
            "Could not access macOS pasteboard service; run the checks outside a restrictive process sandbox"
        )
        try check(pasteboard.pasteboardItems?.count == 5, "Native drag pasteboard collapsed multiple files")
        let roundTrip = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        try check(roundTrip == urls, "Native drag lost file URLs, Unicode names, or selection order")
        try check(ScreenshotShelfDragPayload.items(for: [], at: .zero).isEmpty,
                  "An empty selection unexpectedly created a drag item")
        print("PASS: five selected screenshots round-trip as five distinct native file URLs")
    }

    private static func writeImage(
        to url: URL, screenshotMetadata: Bool, metadataValue: Any = true
    ) throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let blue = NSColor(deviceRed: 0.1, green: 0.4, blue: 0.8, alpha: 1)
        for y in 0..<8 {
            for x in 0..<8 { bitmap.setColor(blue, atX: x, y: y) }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckError.failed("Could not create PNG test fixture")
        }
        try png.write(to: url)
        if screenshotMetadata {
            let value = try PropertyListSerialization.data(
                fromPropertyList: metadataValue, format: .binary, options: 0
            )
            let result = value.withUnsafeBytes {
                setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture",
                         $0.baseAddress, value.count, 0, 0)
            }
            try check(result == 0, "Could not set native screenshot metadata on test fixture")
        }
    }

    @MainActor
    private static func eventually(
        _ description: String, timeout: TimeInterval = 5, condition: () -> Bool
    ) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() {
            guard Date() < deadline else { throw CheckError.failed("Timed out: \(description)") }
            try await pause(0.05)
        }
    }

    private static func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw CheckError.failed(message) }
    }
}
