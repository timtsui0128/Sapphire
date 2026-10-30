import AppKit
import Foundation
import SwiftUI

@MainActor private final class TestSession: AirDropSharingSession {
    var supported = true
    var received: [Any] = []
    var reply: ((Bool, Error?) -> Void)?
    func canShare(_ items: [Any]) -> Bool { supported }
    func present(_ items: [Any], completion: @escaping (Bool, Error?) -> Void) {
        received = items
        reply = completion
    }
}

private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw NSError(domain: "QuickAirDropChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main private struct QuickAirDropChecks {
    @MainActor static func wait(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "QuickAirDropChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for asynchronous sharing preparation"])
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        setbuf(stdout, nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SapphireQuickAirDropChecks-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try checkTopDrop()
        try checkClipboardDrop(root: root)
        let files = try (0..<5).map { index -> URL in
            let url = root.appendingPathComponent("Screenshot-\(index).png")
            try Data("source \(index)".utf8).write(to: url)
            return url
        }
        board.writeObjects((files + [files[0]]).map { $0 as NSURL })
        let decoded = try AirDropPasteboard.read(board)
        try check(decoded == files.map(AirDropContent.file), "All five files must retain their order without duplicate representations")
        print("PASS: native pasteboard accepts five screenshot files together and deduplicates file URLs")

        board.clearContents()
        let link = NSPasteboardItem()
        link.setString("https://example.com/page?q=1", forType: .URL)
        link.setString("duplicate title", forType: .string)
        board.writeObjects([link])
        try check(try AirDropPasteboard.read(board) == [.link(URL(string: "https://example.com/page?q=1")!)], "Share web URLs as links, without duplicate title text")
        board.clearContents()
        let text = "  General / 截图\nActual user text  "
        board.setString(text, forType: .string)
        try check(try AirDropPasteboard.read(board) == [.text(text)], "User text must remain verbatim")
        board.clearContents()
        let rich = NSAttributedString(string: "Rich text becomes plain text")
        board.setData(try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
        try check(try AirDropPasteboard.read(board) == [.text(rich.string)], "RTF should share its plain text")
        board.clearContents()
        do { _ = try AirDropPasteboard.read(board); throw NSError(domain: "Expected rejection", code: 1) }
        catch is QuickAirDropError { }
        print("PASS: links, plain text and rich text decode without duplicate items; an empty pasteboard is rejected")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 16, bitsPerPixel: 32)!
        let png = bitmap.representation(using: .png, properties: [:])!
        board.setData(png, forType: .png)
        let image = try PreparedAirDrop.prepare(AirDropPasteboard.read(board), snapshotURLs: [], cache: root.appendingPathComponent("image-cache"))
        guard case .file(let imageURL) = image.items.first else { fatalError("Expected a staged image") }
        try check(try Data(contentsOf: imageURL) == png, "Clipboard image must be written without changing its bytes")
        try FileManager.default.removeItem(at: image.temporaryDirectory)
        do {
            _ = try PreparedAirDrop.prepare([.image(Data("invalid".utf8))], snapshotURLs: [], cache: root.appendingPathComponent("bad-image"))
            throw NSError(domain: "Expected invalid image rejection", code: 1)
        } catch is QuickAirDropError { }
        print("PASS: clipboard PNG becomes a temporary file; malformed image data is rejected")

        let sameNames = try (0..<2).map { index -> URL in
            let folder = root.appendingPathComponent("same-name-\(index)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("Screenshot.png")
            try Data("different screenshot \(index)".utf8).write(to: file)
            return file
        }
        let duplicates = try PreparedAirDrop.prepare(sameNames.map(AirDropContent.file), snapshotURLs: Set(sameNames), cache: root.appendingPathComponent("same-name-cache"))
        for (index, item) in duplicates.items.enumerated() {
            guard case .file(let url) = item else { fatalError("Expected screenshot snapshot") }
            try check(try url.lastPathComponent == "Screenshot.png" && Data(contentsOf: url) == Data(contentsOf: sameNames[index]), "Identical names must preserve separate files and contents")
        }
        try FileManager.default.removeItem(at: duplicates.temporaryDirectory)
        let external = try PreparedAirDrop.prepare([.file(files[0]), .file(root)], snapshotURLs: [], cache: root.appendingPathComponent("external-cache"))
        try check(external.items == [.file(files[0]), .file(root)], "Ordinary files and folders should be shared directly without a large copy")
        try FileManager.default.removeItem(at: external.temporaryDirectory)
        print("PASS: same-name screenshots remain separate; external files and folders are forwarded without unnecessary copying")

        let session = TestSession()
        let cache = root.appendingPathComponent("sharing-cache")
        let references = files.enumerated().map { AirDropScreenshotReference(id: UUID(), url: $0.element) }
        var completed: [Set<UUID>] = []
        var errors: [String] = []
        let share = QuickAirDrop(cache: cache, factory: { session }, screenshots: { references },
                                didShareScreenshots: { completed.append($0) }, errorPresenter: { errors.append($0) })
        try check(share.share(decoded, dragSequence: 123), "Accept a screenshot batch")
        try check(share.consumeDeferredScreenshotDrag(123), "The source must defer its normal drag-retention callback")
        try check(!share.consumeDeferredScreenshotDrag(123), "A sequence is consumed only once")
        try await wait { session.received.count == 5 }
        try check(completed.isEmpty, "Opening AirDrop is not successful delivery")
        let copies = session.received.map { ($0 as! NSURL) as URL }
        for (index, url) in copies.enumerated() {
            try check(url != files[index], "Managed screenshots must be snapshotted")
            try check(try Data(contentsOf: url) == Data(contentsOf: files[index]), "Snapshot bytes must match")
        }
        session.reply?(false, CocoaError(.userCancelled))
        try check(completed.isEmpty && errors.isEmpty, "Cancelling must preserve screenshot retention without an error alert")
        try check(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "Original screenshots must remain")
        try check(copies.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "Cancel cleans up temporary copies")
        print("PASS: five screenshots are staged separately; cancellation preserves originals and does not trigger shelf removal")

        session.received = []
        try check(share.share([.file(files[0])]), "Accept the next share after cancellation")
        try await wait { session.received.count == 1 }
        session.reply?(true, nil)
        session.reply?(true, nil)
        try check(completed == [Set([references[0].id])], "Only a single successful callback may apply screenshot retention")
        try check(FileManager.default.fileExists(atPath: files[0].path), "The coordinator never directly deletes original files")
        print("PASS: successful sharing applies retention once; duplicate callbacks cannot remove additional items")

        session.received = []
        try check(share.share([.file(files[1])]), "Begin another preparation")
        SessionPrivacyState.shared.isSuppressed = true
        try await Task.sleep(nanoseconds: 250_000_000)
        try check(session.received.isEmpty && !share.isPreparing, "Locking must cancel preparation before a system picker is shown")
        try check(!share.share([.file(files[0])]), "Sharing must be blocked while locked")
        SessionPrivacyState.shared.isSuppressed = false
        try check(share.share([.file(root.appendingPathComponent("missing.png"))]), "Preparation handles a file that disappeared")
        try await wait { !share.isPreparing }
        try check(session.received.isEmpty && errors.count == 1, "Missing files must fail without opening AirDrop")
        print("PASS: lock suppresses new sharing and cancels queued work; a missing file reports an error safely")

        let unsupported = QuickAirDrop(cache: cache, factory: { nil }, screenshots: { references },
                                       didShareScreenshots: { completed.append($0) }, errorPresenter: { errors.append($0) })
        let priorCompletions = completed.count
        try check(unsupported.share([.file(files[0])]), "Unavailable services should be detected after preparing safely")
        try check(!unsupported.share([.file(files[1])]), "A second preparation cannot race the first")
        try await wait { !unsupported.isPreparing }
        try check(errors.count == 2 && completed.count == priorCompletions, "An unavailable service must preserve screenshots and report a useful error")
        try check((try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)).isEmpty, "Cancelled, failed and completed transfers must clean temporary files")
        print("PASS: unavailable services report an error, concurrent preparation is rejected, and staging files are cleaned")

        let view = AirDropDropView(frame: NSRect(x: 0, y: 0, width: 24, height: 24), sharing: share)
        board.clearContents(); board.writeObjects([files[0] as NSURL])
        try check(view.accepts(board, operations: .copy), "The native shelf view accepts supported copy drags")
        try check(!view.accepts(board, operations: .move), "It must not claim destructive move drags")
        SessionPrivacyState.shared.isSuppressed = true
        try check(!view.accepts(board, operations: .copy), "Locked native destinations must refuse drags")
        var clicks = 0
        view.onClick = { clicks += 1 }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event)
        try check(clicks == 0, "Locked shelf clicks must be ignored")
        SessionPrivacyState.shared.isSuppressed = false
        view.mouseDown(with: event)
        try check(clicks == 1, "The drag overlay must still forward file-chooser clicks once")
        try check(NSImage(systemSymbolName: QuickAirDrop.symbolName, accessibilityDescription: nil) != nil, "The menu symbol must exist on the supported system")
        print("PASS: native drag target is copy-only, privacy gated, and forwards normal shelf clicks")
        if let path = CommandLine.arguments.dropFirst().first {
            let output = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for locale in ["en", "zh-Hans"] {
                for dark in [false, true] {
                    let content = VStack(spacing: 12) {
                        AirDropShelfView(sharing: share)
                        Divider()
                        QuickAirDropSettingsView()
                    }
                    .frame(width: 680, height: 460, alignment: .top)
                    .background(dark ? Color.black : Color.white)
                    .environment(\.locale, Locale(identifier: locale))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    let host = NSHostingView(rootView: content)
                    let frame = NSRect(x: 0, y: 0, width: 680, height: 460)
                    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.contentView = host
                    host.frame = frame
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(nanoseconds: 80_000_000)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("airdrop-\(locale)-\(dark ? "dark" : "light").png"))
                    window.close()
                    let cards = HStack(spacing: 15) {
                        DropZoneView(zone: .airdrop, icon: QuickAirDrop.symbolName, text: "Drop to AirDrop", isTargeted: false)
                        DropZoneView(zone: .clipboard, icon: "doc.on.clipboard", text: "Copy to Clipboard", isTargeted: true)
                    }
                    .padding(15).frame(width: 520, height: 150)
                    .background(dark ? Color.black : Color.white)
                    .environment(\.locale, Locale(identifier: locale))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    let cardsHost = NSHostingView(rootView: cards)
                    let cardsFrame = NSRect(x: 0, y: 0, width: 520, height: 150)
                    let cardsWindow = NSWindow(contentRect: cardsFrame, styleMask: [.borderless], backing: .buffered, defer: false)
                    cardsWindow.isReleasedWhenClosed = false
                    cardsWindow.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    cardsWindow.contentView = cardsHost
                    cardsHost.frame = cardsFrame
                    cardsHost.layoutSubtreeIfNeeded()
                    try await Task.sleep(nanoseconds: 80_000_000)
                    let cardsBitmap = cardsHost.bitmapImageRepForCachingDisplay(in: cardsHost.bounds)!
                    cardsHost.cacheDisplay(in: cardsHost.bounds, to: cardsBitmap)
                    try cardsBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("top-drop-\(locale)-\(dark ? "dark" : "light").png"))
                    cardsWindow.close()
                }
            }
            print("PASS: internal AirDrop shelf and settings render in English/Chinese, light/dark")
        }
        print("All Quick AirDrop checks passed; no real transfer was started.")
    }
}
