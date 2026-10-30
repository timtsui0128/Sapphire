import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class TopDropClipboard: ObservableObject {
    static let shared = TopDropClipboard()
    @Published private(set) var didCopy = false
    private let clipboard: NSPasteboard
    private let screenshotURLs: @MainActor () -> Set<URL>
    private let reportError: @MainActor (String) -> Void
    private var preservedDrags: [Int: Date] = [:]

    init(clipboard: NSPasteboard = .general,
         screenshotURLs: @escaping @MainActor () -> Set<URL> = {
             Set(ScreenshotShelfManager.shared.items.map { $0.fileURL.standardizedFileURL })
         },
         reportError: @escaping @MainActor (String) -> Void = { message in
             HelperAlertPresenter.presentModal(messageText: "Couldn’t copy to clipboard", informativeText: message,
                                               alertStyle: .warning, buttonTitles: ["OK"]) { _ in }
         }) {
        self.clipboard = clipboard
        self.screenshotURLs = screenshotURLs
        self.reportError = reportError
    }

    func resetFeedback() { didCopy = false }

    func consumePreservedScreenshotDrag(_ sequence: Int) -> Bool {
        preservedDrags = preservedDrags.filter { $0.value > Date().addingTimeInterval(-60) }
        return preservedDrags.removeValue(forKey: sequence) != nil
    }

    @discardableResult
    func copy(_ items: [AirDropContent], dragSequence: Int? = nil) -> Bool {
        guard !SessionPrivacyState.shouldSuppressUI() else { return false }
        didCopy = false
        guard !items.isEmpty, items.count <= AirDropPasteboard.maximumItems else { return false }
        let files = items.compactMap { if case .file(let url) = $0 { return url }; return nil }
        let scopedURLs = files.filter { $0.startAccessingSecurityScopedResource() }
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            var payload: [NSPasteboardItem] = []
            var inlineBytes = 0
            for item in items {
                let entry = NSPasteboardItem()
                switch item {
                case .file(let url):
                    guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
                        throw QuickAirDropError.missingFile(url.lastPathComponent)
                    }
                    entry.setString(url.absoluteString, forType: .fileURL)
                case .link(let url):
                    entry.setString(url.absoluteString, forType: .URL)
                    entry.setString(url.absoluteString, forType: .string)
                    inlineBytes += url.absoluteString.utf8.count
                case .text(let text):
                    entry.setString(text, forType: .string)
                    inlineBytes += text.utf8.count
                case .image(let data):
                    inlineBytes += data.count
                    guard inlineBytes <= AirDropPasteboard.maximumInlineBytes,
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          CGImageSourceGetCount(source) > 0,
                          let type = CGImageSourceGetType(source),
                          [UTType.png.identifier, UTType.tiff.identifier].contains(type as String) else {
                        throw QuickAirDropError.empty
                    }
                    entry.setData(data, forType: NSPasteboard.PasteboardType(type as String))
                }
                guard inlineBytes <= AirDropPasteboard.maximumInlineBytes else { throw QuickAirDropError.tooLarge }
                payload.append(entry)
            }
            // Read and validate everything first: an invalid drop must not erase
            // the user's previous clipboard. File URLs preserve multi-file paste.
            clipboard.clearContents()
            guard clipboard.writeObjects(payload) else {
                throw NSError(domain: "TopDropClipboard", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: L10n.string("The clipboard is unavailable. Please try again.")])
            }
            if let dragSequence, !Set(files.map(\.standardizedFileURL)).isDisjoint(with: screenshotURLs()) {
                // Copying a reference is not delivery to another app. Keep shelf
                // files so its successful native drag callback cannot delete them.
                preservedDrags[dragSequence] = Date()
            }
            didCopy = true
            return true
        } catch {
            reportError(error.localizedDescription)
            return false
        }
    }
}
