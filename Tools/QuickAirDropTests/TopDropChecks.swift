import AppKit

@MainActor private final class TestDrag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation = NSPoint(x: 40, y: 40)
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard: NSPasteboard
    var draggingSource: Any? { nil }
    var draggingSequenceNumber = 73
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight = .none
    init(board: NSPasteboard) { draggingPasteboard = board }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@MainActor func checkTopDrop() throws {
    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "TopDrop", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    let suite = "AirDropDragPreferencesTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try check(AirDropDragPreferences.isEnabled(in: defaults), "Top drag should default to quick actions")
    defaults.set(false, forKey: AirDropDragPreferences.key)
    try check(!AirDropDragPreferences.isEnabled(in: defaults), "The saved opt-out must retain ordinary shelf routing")

    let frames: [DropZone: CGRect] = [
        .airdrop: CGRect(x: 15, y: 15, width: 237.5, height: 120),
        .clipboard: CGRect(x: 267.5, y: 15, width: 237.5, height: 120)
    ]
    try check(TopDropTargets.destination(at: CGPoint(x: 100, y: 60), frames: frames) == .airdrop, "Left target must choose AirDrop")
    try check(TopDropTargets.destination(at: CGPoint(x: 360, y: 60), frames: frames) == .clipboard, "Right target must choose Clipboard, not AirDrop")
    for point in [CGPoint(x: 260, y: 60), CGPoint(x: 100, y: 0), CGPoint(x: -1, y: 40), CGPoint(x: 800, y: 60)] {
        try check(TopDropTargets.destination(at: point, frames: frames) == nil, "A gap or point outside the cards must not trigger an action")
    }
    try check(TopDropTargets.destination(at: .zero, frames: [:]) == nil, "An unmeasured panel must not default to AirDrop")
    print("PASS: AirDrop and Clipboard hit regions route separately; gaps and unmeasured/outside drops perform no action")

    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let probe = HoverProbeWindow(level: .normal, collectionBehavior: [])
    probe.setContentSize(NSSize(width: 300, height: 150))
    let drag = TestDrag(board: board)
    drag.draggingDestinationWindow = probe
    var entered = 0
    var drops = 0
    var finished: [Bool] = []
    probe.onFileDragBegan = { _ in entered += 1 }
    probe.onFileDrop = { payload, _, sequence in
        drops += 1
        return payload === board && sequence == 73
    }
    probe.onFileDragEnded = { _, accepted in finished.append(accepted) }
    board.writeObjects([URL(fileURLWithPath: "/tmp/Test.pdf") as NSURL, URL(fileURLWithPath: "/tmp/Test.png") as NSURL])
    try check(!FileDragPasteboard.containsDroppableContent(board, newerThan: board.changeCount), "Stale file pasteboard cannot activate a new drag")
    try check(probe.draggingEntered(drag) == .copy, "PDF and image files must activate the top destination")
    try check(entered == 1 && drops == 0, "Hover must reveal the destination without sharing")
    try check(probe.prepareForDragOperation(drag) && probe.performDragOperation(drag), "Native release must pass the full payload and sequence")
    probe.draggingEnded(drag)
    probe.concludeDragOperation(drag)
    try check(drops == 1 && finished == [true] && probe.ignoresMouseEvents, "Drop completion must run once and release mouse interception")

    try check(probe.draggingEntered(drag) == .copy, "A later drag must work")
    probe.draggingExited(drag)
    probe.draggingEnded(drag)
    try check(drops == 1 && finished == [true, false], "Canceling a drag must never share")
    drag.draggingSourceOperationMask = .move
    try check(probe.draggingEntered(drag).isEmpty, "Move-only drag must not be accepted as a transfer")
    print("PASS: top drag preferences, native PDF/image payload and sequence, hover-only feedback, cancellation and mouse pass-through")
}
