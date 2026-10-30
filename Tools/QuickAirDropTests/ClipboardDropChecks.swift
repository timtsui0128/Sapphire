import AppKit

@MainActor func checkClipboardDrop(root: URL) throws {
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NSError(domain: "ClipboardDrop", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let files = try ["One.pdf", "Two.png", "Three.txt"].map { name -> URL in
        let file = root.appendingPathComponent(name)
        try Data(name.utf8).write(to: file)
        return file
    }
    var errors: [String] = []
    let copier = TopDropClipboard(clipboard: board, screenshotURLs: { [files[1]] }, reportError: { errors.append($0) })
    try check(copier.copy(files.map(AirDropContent.file), dragSequence: 901), "Multiple file drop should copy")
    let actual = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    try check(actual == files, "Native file paste must preserve all files in order, not path text")
    try check(copier.didCopy, "Successful drop must publish copy feedback")
    try check(copier.consumePreservedScreenshotDrag(901), "Copying screenshots must suppress delete-after-drag retention")
    try check(!copier.consumePreservedScreenshotDrag(901), "Retention deferral is single-use")
    try check(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "Copy must not move or remove originals")
    copier.resetFeedback()
    try check(!copier.didCopy, "A new drag clears old success feedback")
    print("PASS: three native file URLs paste together; screenshots survive copy and retention deferral is consumed once")

    board.clearContents()
    board.setString("keep previous clipboard", forType: .string)
    let before = board.changeCount
    try check(!copier.copy([.file(files[0]), .file(root.appendingPathComponent("missing.pdf"))], dragSequence: 902), "Missing files must reject the entire batch")
    try check(board.changeCount == before && board.string(forType: .string) == "keep previous clipboard", "Invalid drop must not erase the clipboard or partially copy")
    try check(!copier.consumePreservedScreenshotDrag(902), "Failed copy cannot consume screenshot retention")
    SessionPrivacyState.shared.isSuppressed = true
    try check(!copier.copy([.file(files[0])]) && board.changeCount == before, "Locked sessions must not overwrite the clipboard")
    SessionPrivacyState.shared.isSuppressed = false
    try check(!copier.copy([]) && board.changeCount == before, "Empty drop must preserve clipboard")
    print("PASS: missing/empty file batches and locked sessions leave the previous clipboard untouched")

    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 8, bitsPerPixel: 32)!
    let png = bitmap.representation(using: .png, properties: [:])!
    try check(copier.copy([.image(png)]) && board.data(forType: .png) == png, "Inline dragged images remain pasteable as image data")
    let imageChange = board.changeCount
    try check(!copier.copy([.image(Data("not an image".utf8))]) && board.changeCount == imageChange, "Malformed image leaves clipboard unchanged")
    let link = URL(string: "https://example.com/a?q=1")!
    try check(copier.copy([.link(link)]) && board.string(forType: .URL) == link.absoluteString, "Links retain native URL representation")
    try check(copier.copy([.text("  原始文本\n")]) && board.string(forType: .string) == "  原始文本\n", "Text stays verbatim")
    try check(errors.count == 2, "Only the missing file and malformed image should report errors")
    print("PASS: PNG, links and text preserve native paste types; malformed image data is rejected")
}
