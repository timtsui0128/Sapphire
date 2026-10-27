import AppKit
import Combine

@MainActor
protocol AirDropSharingSession: AnyObject {
    func canShare(_ items: [Any]) -> Bool
    func present(_ items: [Any], completion: @escaping (Bool, Error?) -> Void)
}

@MainActor
private final class SystemAirDropSession: NSObject, AirDropSharingSession, NSSharingServiceDelegate {
    private let service: NSSharingService
    private var completion: ((Bool, Error?) -> Void)?
    init?(service: NSSharingService? = NSSharingService(named: .sendViaAirDrop)) {
        guard let service else { return nil }
        self.service = service
        super.init()
        service.delegate = self
    }
    func canShare(_ items: [Any]) -> Bool { service.canPerform(withItems: items) }
    func present(_ items: [Any], completion: @escaping (Bool, Error?) -> Void) {
        self.completion = completion
        service.perform(withItems: items)
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish(true, nil) }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish(false, error) }
    private func finish(_ success: Bool, _ error: Error?) {
        let reply = completion
        completion = nil
        reply?(success, error)
    }
}

struct AirDropScreenshotReference {
    let id: UUID
    let url: URL
}

@MainActor
final class QuickAirDrop: ObservableObject {
    static let shared = QuickAirDrop()
    static let symbolName = NSImage(systemSymbolName: "airdrop", accessibilityDescription: nil) != nil ? "airdrop" : "square.and.arrow.up"
    static let enabledKey = "SapphireQuickAirDropMenuBarEnabled"
    @Published var menuBarEnabled: Bool { didSet { defaults.set(menuBarEnabled, forKey: Self.enabledKey) } }
    @Published private(set) var isPreparing = false
    @Published private(set) var lastError: String?

    private let defaults: UserDefaults
    private let cache: URL
    private let factory: @MainActor () -> AirDropSharingSession?
    private let screenshots: @MainActor () -> [AirDropScreenshotReference]
    private let didShareScreenshots: @MainActor (Set<UUID>) -> Void
    private let errorPresenter: @MainActor (String) -> Void
    private var preparation: Task<PreparedAirDrop, Error>?
    private var preparationID: UUID?
    private var panel: NSOpenPanel?
    private var privacy: AnyCancellable?
    private var deferredDrags: [Int: Date] = [:]
    private struct Transfer {
        let session: AirDropSharingSession
        let payload: PreparedAirDrop
        let scopedURLs: [URL]
        let screenshotIDs: Set<UUID>
    }
    private var transfers: [UUID: Transfer] = [:]

    init(defaults: UserDefaults = .standard, cache: URL? = nil,
         factory: @escaping @MainActor () -> AirDropSharingSession? = { SystemAirDropSession() },
         screenshots: @escaping @MainActor () -> [AirDropScreenshotReference] = {
             ScreenshotShelfManager.shared.items.map { AirDropScreenshotReference(id: $0.id, url: $0.fileURL) }
         },
         didShareScreenshots: @escaping @MainActor (Set<UUID>) -> Void = { ScreenshotShelfManager.shared.didFinishDrag(ids: $0, accepted: true) },
         errorPresenter: @escaping @MainActor (String) -> Void = { message in
             HelperAlertPresenter.presentModal(messageText: "Couldn’t open AirDrop", informativeText: message,
                                               alertStyle: .warning, buttonTitles: ["OK"]) { _ in }
         }) {
        self.defaults = defaults
        self.cache = cache ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.cshariq.sapphire", isDirectory: true)
            .appendingPathComponent("QuickAirDrop", isDirectory: true)
        self.factory = factory
        self.screenshots = screenshots
        self.didShareScreenshots = didShareScreenshots
        self.errorPresenter = errorPresenter
        menuBarEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        privacy = SessionPrivacyState.shared.$isSuppressed.sink { [weak self] suppressed in
            if suppressed { self?.cancelPreparation() }
        }
        let cacheRoot = self.cache
        Task.detached(priority: .utility) {
            // Keep interrupted hand-offs for a day, including after Sapphire quits.
            let fm = FileManager.default
            for directory in (try? fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])) ?? [] {
                guard UUID(uuidString: directory.lastPathComponent) != nil,
                      let values = try? directory.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey]),
                      values.isDirectory == true, let date = values.creationDate, date < Date().addingTimeInterval(-86400) else { continue }
                try? fm.removeItem(at: directory)
            }
        }
    }

    func chooseFiles() {
        guard !SessionPrivacyState.shouldSuppressUI(), !isPreparing, panel == nil else { return }
        let chooser = NSOpenPanel()
        chooser.title = L10n.string("Choose items to AirDrop")
        chooser.prompt = "AirDrop"
        chooser.canChooseFiles = true
        chooser.canChooseDirectories = true
        chooser.allowsMultipleSelection = true
        panel = chooser
        chooser.begin { [weak self] response in
            guard let self, self.panel === chooser else { return }
            self.panel = nil
            guard response == .OK, !SessionPrivacyState.shouldSuppressUI() else { return }
            self.share(chooser.urls.map(AirDropContent.file))
        }
    }

    func shareClipboard() {
        guard !SessionPrivacyState.shouldSuppressUI(), !isPreparing else { return }
        do { share(try AirDropPasteboard.read(.general)) } catch { report(error) }
    }

    @discardableResult
    func sharePasteboard(_ pasteboard: NSPasteboard, dragSequence: Int) -> Bool {
        guard !SessionPrivacyState.shouldSuppressUI(), !isPreparing else { return false }
        do { return share(try AirDropPasteboard.read(pasteboard), dragSequence: dragSequence) }
        catch { report(error); return false }
    }

    /// The screenshot source must not interpret opening a picker as successful
    /// delivery. Retention is applied only from the service's success callback.
    func consumeDeferredScreenshotDrag(_ sequence: Int) -> Bool {
        deferredDrags = deferredDrags.filter { $0.value > Date().addingTimeInterval(-60) }
        return deferredDrags.removeValue(forKey: sequence) != nil
    }

    @discardableResult
    func share(_ items: [AirDropContent], dragSequence: Int? = nil) -> Bool {
        guard !SessionPrivacyState.shouldSuppressUI(), !isPreparing else { return false }
        guard !items.isEmpty else { report(QuickAirDropError.empty); return false }
        guard items.count <= AirDropPasteboard.maximumItems else { report(QuickAirDropError.tooLarge); return false }
        let urls = items.compactMap { if case .file(let url) = $0 { return url.standardizedFileURL }; return nil }
        let known = screenshots().filter { urls.contains($0.url.standardizedFileURL) }
        let snapshotURLs = Set(known.map { $0.url.standardizedFileURL })
        let ids = Set(known.map(\.id))
        let scopes = urls.filter { $0.startAccessingSecurityScopedResource() }
        if let dragSequence, !ids.isEmpty { deferredDrags[dragSequence] = Date() }
        let id = UUID()
        preparationID = id
        isPreparing = true
        lastError = nil
        let root = cache
        let worker = Task.detached(priority: .userInitiated) { try PreparedAirDrop.prepare(items, snapshotURLs: snapshotURLs, cache: root) }
        preparation = worker
        Task {
            do {
                let prepared = try await worker.value
                guard preparationID == id, !SessionPrivacyState.shouldSuppressUI() else {
                    scopes.forEach { $0.stopAccessingSecurityScopedResource() }
                    try? FileManager.default.removeItem(at: prepared.temporaryDirectory)
                    return
                }
                preparation = nil
                preparationID = nil
                isPreparing = false
                guard let service = factory(), service.canShare(prepared.sharingItems) else {
                    scopes.forEach { $0.stopAccessingSecurityScopedResource() }
                    try? FileManager.default.removeItem(at: prepared.temporaryDirectory)
                    report(QuickAirDropError.unavailable)
                    return
                }
                transfers[id] = Transfer(session: service, payload: prepared, scopedURLs: scopes, screenshotIDs: ids)
                service.present(prepared.sharingItems) { [weak self] success, error in self?.finish(id, success: success, error: error) }
            } catch {
                scopes.forEach { $0.stopAccessingSecurityScopedResource() }
                guard preparationID == id else { return }
                preparation = nil
                preparationID = nil
                isPreparing = false
                if !(error is CancellationError) { report(error) }
            }
        }
        return true
    }

    private func finish(_ id: UUID, success: Bool, error: Error?) {
        guard let transfer = transfers.removeValue(forKey: id) else { return }
        transfer.scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        try? FileManager.default.removeItem(at: transfer.payload.temporaryDirectory)
        guard !SessionPrivacyState.shouldSuppressUI() else { return }
        if success, !transfer.screenshotIDs.isEmpty { didShareScreenshots(transfer.screenshotIDs) }
        if let error {
            let ns = error as NSError
            let cancelled = (ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError)
                || (ns.domain == NSOSStatusErrorDomain && ns.code == -128) // userCanceledErr
            if !cancelled { report(error) }
        }
    }

    func cancelPreparation() {
        preparationID = nil
        preparation?.cancel()
        preparation = nil
        isPreparing = false
        panel?.cancel(nil)
        panel = nil
        // Existing OS-managed transfers remain under AirDrop's control.
    }

    private func report(_ error: Error) {
        guard !SessionPrivacyState.shouldSuppressUI() else { return }
        lastError = error.localizedDescription
        errorPresenter(error.localizedDescription)
    }
}
