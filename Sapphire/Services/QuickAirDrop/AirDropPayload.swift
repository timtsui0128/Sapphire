import AppKit
import ImageIO
import UniformTypeIdentifiers

enum AirDropContent: Sendable, Equatable {
    case file(URL)
    case link(URL)
    case text(String)
    case image(Data)
}

enum QuickAirDropError: LocalizedError {
    case empty, tooLarge, unavailable
    case missingFile(String)
    var errorDescription: String? {
        switch self {
        case .empty: return L10n.string("Choose files, an image, a web link, or text to share.")
        case .tooLarge: return L10n.string("This clipboard or drag contains too much data. Save it as a file and share that file instead.")
        case .unavailable: return L10n.string("AirDrop is not available for these items on this Mac.")
        case .missingFile(let name): return L10n.format("The file %@ is no longer available.", name)
        }
    }
}

enum AirDropPasteboard {
    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff, .rtf]
    static let maximumInlineBytes = 64 * 1_024 * 1_024
    static let maximumItems = 512

    /// Hover inspects advertised types only. The general clipboard is read only
    /// after the user explicitly chooses the clipboard command.
    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: types) != nil
    }

    static func read(_ pasteboard: NSPasteboard) throws -> [AirDropContent] {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !files.isEmpty {
            guard files.count <= maximumItems else { throw QuickAirDropError.tooLarge }
            var seen = Set<URL>()
            return files.filter { seen.insert($0.standardizedFileURL).inserted }.map(AirDropContent.file)
        }
        let items = pasteboard.pasteboardItems ?? []
        guard items.count <= maximumItems else { throw QuickAirDropError.tooLarge }
        var result: [AirDropContent] = []
        var total = 0
        for item in items {
            if let value = item.string(forType: .URL), let url = URL(string: value),
               ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                result.append(.link(url))
                total += value.utf8.count
            } else if let data = item.data(forType: .png) ?? item.data(forType: .tiff) {
                total += data.count
                guard total <= maximumInlineBytes else { throw QuickAirDropError.tooLarge }
                result.append(.image(data))
            } else if let text = item.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                total += text.utf8.count
                result.append(.text(text))
            } else if let rtf = item.data(forType: .rtf) {
                guard rtf.count <= maximumInlineBytes else { throw QuickAirDropError.tooLarge }
                if let text = NSAttributedString(rtf: rtf, documentAttributes: nil)?.string, !text.isEmpty {
                    total += text.utf8.count
                    result.append(.text(text))
                }
            }
            guard total <= maximumInlineBytes else { throw QuickAirDropError.tooLarge }
        }
        guard !result.isEmpty else { throw QuickAirDropError.empty }
        return result
    }
}

struct PreparedAirDrop: Sendable {
    let items: [AirDropContent]
    let temporaryDirectory: URL

    @MainActor var sharingItems: [Any] {
        items.compactMap { item in
            switch item {
            case .file(let url), .link(let url): return url as NSURL
            case .text(let text): return text as NSString
            case .image: return nil // Images have already become temporary files.
            }
        }
    }

    static func prepare(_ items: [AirDropContent], snapshotURLs: Set<URL>, cache: URL) throws -> PreparedAirDrop {
        guard !items.isEmpty else { throw QuickAirDropError.empty }
        let fm = FileManager.default
        let directory = cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: directory) } }
        var prepared: [AirDropContent] = []
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            switch item {
            case .file(let url):
                guard url.isFileURL, fm.fileExists(atPath: url.path), fm.isReadableFile(atPath: url.path) else {
                    throw QuickAirDropError.missingFile(url.lastPathComponent)
                }
                if snapshotURLs.contains(url.standardizedFileURL) {
                    let folder = directory.appendingPathComponent(String(index), isDirectory: true)
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    let copy = folder.appendingPathComponent(url.lastPathComponent)
                    try fm.copyItem(at: url, to: copy)
                    prepared.append(.file(copy))
                } else {
                    prepared.append(.file(url))
                }
            case .image(let data):
                guard data.count <= AirDropPasteboard.maximumInlineBytes,
                      let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                      let type = CGImageSourceGetType(source), let ext = UTType(type as String)?.preferredFilenameExtension else {
                    throw QuickAirDropError.empty
                }
                let file = directory.appendingPathComponent("Image-\(index + 1).\(ext)")
                try data.write(to: file, options: .atomic)
                prepared.append(.file(file))
            case .link, .text: prepared.append(item)
            }
        }
        try Task.checkCancellation()
        succeeded = true
        return PreparedAirDrop(items: prepared, temporaryDirectory: directory)
    }
}
