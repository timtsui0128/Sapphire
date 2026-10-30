//
//  ScreenshotShelfView.swift
//  Sapphire
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A collection of screenshots with selectable retention and a multi-file macOS drag source.
@MainActor
struct ScreenshotShelfView: View {
    @ObservedObject private var language = AppLanguageController.shared
    @ObservedObject private var manager: ScreenshotShelfManager
    @ObservedObject private var airDrop = QuickAirDrop.shared
    private var selectedIDs: Set<UUID> { manager.selectedIDs }
    @State private var copyMessage: String?

    var onDragStateChanged: ((Bool) -> Void)? = nil

    init(
        manager: ScreenshotShelfManager? = nil,
        onDragStateChanged: ((Bool) -> Void)? = nil
    ) {
        _manager = ObservedObject(wrappedValue: manager ?? .shared)
        self.onDragStateChanged = onDragStateChanged
    }

    private var selectedItems: [ScreenshotShelfItem] {
        manager.items.filter { selectedIDs.contains($0.id) }
    }

    private var allSelected: Bool {
        !manager.items.isEmpty && selectedIDs.count == manager.items.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar

            if manager.items.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 112)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(manager.items) { item in
                            ScreenshotShelfCard(
                                item: item,
                                isSelected: selectedIDs.contains(item.id)
                            ) {
                                toggleSelection(item.id)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.visible)
                .frame(height: 122)
            }

            selectionBar
            statusBar
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appContentAppearance()
        .onAppear {
            if manager.captureEnabled { manager.startMonitoring() }
        }
        .onChange(of: manager.items.map(\.id)) { _, _ in
            copyMessage = nil
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label("Screenshots", systemImage: "rectangle.on.rectangle")
                .font(.headline)
            Text("\(manager.items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Toggle("Auto-collect", isOn: $manager.captureEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .help("Move newly saved screenshots into Sapphire's storage folder.")
            Menu {
                Toggle("Copy new screenshots to clipboard", isOn: $manager.automaticallyCopyNewScreenshots)
                Divider()
                Picker("Collect screenshots", selection: $manager.captureTiming) {
                    ForEach(ScreenshotCaptureTiming.allCases) { timing in
                        Text(LocalizedStringKey(timing.title)).tag(timing)
                    }
                }
                .pickerStyle(.inline)
                Text("Immediate collection skips the macOS floating preview.")
                Divider()
                Picker("Keep new screenshots", selection: $manager.retention) {
                    ForEach(ScreenshotShelfRetention.allCases) { retention in
                        Text(LocalizedStringKey(retention.title)).tag(retention)
                    }
                }
                .pickerStyle(.inline)
                Text("Changes apply to new screenshots and imports.")
                Divider()
                Text("Auto-collected screenshots move into Sapphire.")
                Text("Manually added files are copied.")
                Button("Show Sapphire storage folder") {
                    NSWorkspace.shared.open(manager.storageFolderURL)
                }
                Divider()
                Button("Add screenshots…", action: importScreenshots)
                Divider()
                Button("Choose screenshot folder…") { manager.chooseFolder() }
                Button("Use macOS screenshot folder") { manager.useSystemScreenshotFolder() }
                if let folder = manager.watchedFolder {
                    Button("Show source screenshot folder") {
                        NSWorkspace.shared.open(folder)
                    }
                }
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Screenshot collection timing, retention, storage, and import settings")
            .accessibilityLabel("Screenshot settings")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Your screenshots, ready together.")
                .font(.subheadline.weight(.medium))
            Text("Take a screenshot with ⇧⌘4 or ⇧⌘3 and let it save.\nSapphire moves it here, ready to select and drag together.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var selectionBar: some View {
        HStack(spacing: 8) {
            Button(allSelected ? "Deselect all" : "Select all") {
                manager.setSelection(allSelected ? [] : Set(manager.items.map(\.id)))
                copyMessage = nil
            }
            .disabled(manager.items.isEmpty)
            .keyboardShortcut("a", modifiers: .command)

            Button {
                let count = selectedItems.count
                if manager.copyItems(ids: selectedIDs) {
                    copyMessage = count == 1 ? L10n.string("Copied 1 screenshot.") : L10n.format("Copied %lld screenshots.", count)
                } else {
                    copyMessage = nil
                    NSSound.beep()
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(selectedItems.isEmpty)
            .keyboardShortcut("c", modifiers: .command)
            .help("Copy selected screenshot files. File paste support depends on the destination app.")

            Button {
                airDrop.share(selectedItems.map { .file($0.fileURL) })
            } label: {
                Label("AirDrop", systemImage: QuickAirDrop.symbolName)
            }
            .disabled(selectedItems.isEmpty || airDrop.isPreparing)
            .help("AirDrop all selected screenshots together. Choose a device in the system window.")

            Button {
                manager.removeItems(ids: selectedIDs)
                manager.setSelection([])
                copyMessage = nil
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedItems.isEmpty)
            .help("Remove the selected screenshots from Sapphire storage. Originals of manually added files are kept.")
            .accessibilityLabel("Remove selected screenshots from shelf")

            Spacer(minLength: 6)

            batchDragHandle
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var batchDragHandle: some View {
        let count = selectedItems.count
        return Label {
            if count == 0 {
                Text("Select screenshots to drag")
            } else if count == 1 {
                Text("Drag 1 screenshot")
            } else {
                Text("Drag \(count) screenshots")
            }
        } icon: {
            Image(systemName: "hand.draw")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(count == 0 ? Color.secondary : Color.accentColor)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(count == 0 ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.14))
        }
        .overlay {
            ScreenshotBatchDragSource(
                items: selectedItems,
                onDragStateChanged: onDragStateChanged,
                onDragEnded: { ids, accepted in
                    manager.didFinishDrag(ids: ids, accepted: accepted)
                }
            )
        }
        .help("Drag this handle into a conversation to attach all selected screenshots. Each screenshot keeps its own retention setting; canceled drags keep everything.")
    }

    @ViewBuilder
    private var statusBar: some View {
        if let error = manager.lastError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .lineLimit(1)
                    .help(error)
                Spacer(minLength: 0)
                Button("Retry") { manager.retryFailedOperations() }
                Button("Choose folder…") { manager.chooseFolder() }
            }
            .font(.caption2)
            .buttonStyle(.borderless)
        } else {
            HStack(spacing: 5) {
                Image(systemName: manager.isMonitoring ? "checkmark.circle" : "pause.circle")
                Text(copyMessage ?? monitoringStatus)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(newScreenshotRetentionStatus)
                    .help("This retention setting applies to new screenshots and imports. Existing screenshots keep their original setting.")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .help(manager.watchedFolder?.path ?? L10n.string("Choose a screenshot folder to collect captures."))
        }
    }

    private var monitoringStatus: String {
        guard manager.captureEnabled else { return L10n.string("Auto-collect paused") }
        guard manager.isMonitoring else { return L10n.string("Waiting for screenshot folder") }
        return L10n.format("Collecting from %@", manager.watchedFolder?.lastPathComponent ?? L10n.string("screenshot folder"))
    }

    private var newScreenshotRetentionStatus: String {
        switch manager.retention {
        case .persistent: return L10n.string("New: keep until removed")
        case .twentyFourHours: return L10n.string("New: keep for 24 hours")
        case .afterSuccessfulDrag: return L10n.string("New: remove after drop")
        }
    }

    private func toggleSelection(_ id: UUID) {
        manager.setSelection(selectedIDs.symmetricDifference([id]))
        copyMessage = nil
    }

    private func importScreenshots() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Add screenshots")
        panel.prompt = L10n.string("Add")
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                manager.importFiles(from: panel.urls)
            }
        }
    }
}

@MainActor
private struct ScreenshotShelfCard: View {
    @ObservedObject private var language = AppLanguageController.shared
    let item: ScreenshotShelfItem
    let isSelected: Bool
    let onToggle: () -> Void
    @State private var image: NSImage?

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary, Color(nsColor: .windowBackgroundColor))
                        .font(.system(size: 18, weight: .medium))
                        .padding(6)
                }
                .frame(width: 114, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                }
                Text(item.name)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 114, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(item.name)\n\(item.capturedAt.formatted(date: .abbreviated, time: .shortened))\n\(retentionDescription)")
        .accessibilityLabel(item.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Click to \(L10n.string(isSelected ? "deselect" : "select")) this screenshot. \(retentionDescription)")
        .task(id: item.fileURL) {
            image = nil
            let thumbnail = await ScreenshotShelfThumbnails.shared.thumbnail(for: item.fileURL)
            guard !Task.isCancelled, let thumbnail else { return }
            image = NSImage(cgImage: thumbnail, size: .zero)
        }
    }

    private var retentionDescription: String {
        if item.removeAfterSuccessfulDrag == true {
            return L10n.string("Removed after a successful drop.")
        }
        if let expiresAt = item.expiresAt {
            return L10n.format("Removed %@.", expiresAt.formatted(.dateTime.locale(L10n.locale)))
        }
        return L10n.string("Kept until you remove it.")
    }
}

/// ImageIO downsamples on this actor's executor, avoiding full-resolution decoding on the UI thread.
private actor ScreenshotShelfThumbnails {
    static let shared = ScreenshotShelfThumbnails()
    private var images: [URL: CGImage] = [:]
    private var insertionOrder: [URL] = []

    func thumbnail(for url: URL) -> CGImage? {
        if let image = images[url] { return image }
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        images[url] = image
        insertionOrder.append(url)
        if insertionOrder.count > 120 {
            images.removeValue(forKey: insertionOrder.removeFirst())
        }
        return image
    }
}

/// Each NSURL is a separate pasteboard writer, so browsers receive N files rather than one bundle.
@MainActor
enum ScreenshotShelfDragPayload {
    /// Snapshot the exact payload so later captures or selection changes cannot
    /// change which screenshots a completed drag is allowed to remove.
    struct Batch {
        let ids: Set<UUID>
        let urls: [URL]

        init(items: [ScreenshotShelfItem]) {
            ids = Set(items.map(\.id))
            urls = items.map(\.fileURL)
        }
    }

    static func accepted(_ operation: NSDragOperation) -> Bool {
        !operation.intersection([.copy, .move, .link, .generic]).isEmpty
    }

    static func items(for urls: [URL], at origin: NSPoint) -> [NSDraggingItem] {
        let icon = NSImage(systemSymbolName: "photo", accessibilityDescription: "Screenshot")
            ?? NSImage(size: NSSize(width: 48, height: 48))
        return urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 5)) * 4
            item.setDraggingFrame(
                NSRect(x: origin.x + offset - 24, y: origin.y - offset - 24, width: 48, height: 48),
                contents: icon
            )
            return item
        }
    }
}

@MainActor
private struct ScreenshotBatchDragSource: NSViewRepresentable {
    let items: [ScreenshotShelfItem]
    var onDragStateChanged: ((Bool) -> Void)?
    var onDragEnded: (Set<UUID>, Bool) -> Void

    func makeNSView(context: Context) -> ScreenshotBatchDragView {
        ScreenshotBatchDragView()
    }

    func updateNSView(_ view: ScreenshotBatchDragView, context: Context) {
        view.items = items
        view.onDragStateChanged = onDragStateChanged
        view.onDragEnded = onDragEnded
        view.setAccessibilityLabel("Drag \(items.count) screenshot files")
        view.setAccessibilityHelp("Drag into a conversation, or use Copy to copy the selected files.")
        view.window?.invalidateCursorRects(for: view)
    }
}

@MainActor
private final class ScreenshotBatchDragView: NSView, NSDraggingSource {
    var items: [ScreenshotShelfItem] = []
    var onDragStateChanged: ((Bool) -> Void)?
    var onDragEnded: ((Set<UUID>, Bool) -> Void)?
    private var mouseDownLocation: NSPoint?
    private var mouseDownEvent: NSEvent?
    private var isDragging = false
    private var activeDrag: ActiveDrag?

    private struct ActiveDrag {
        let batch: ScreenshotShelfDragPayload.Batch
        let onStateChanged: ((Bool) -> Void)?
        let onEnded: ((Set<UUID>, Bool) -> Void)?
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        if !items.isEmpty { addCursorRect(bounds, cursor: .openHand) }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let start = mouseDownLocation, let mouseDownEvent, !items.isEmpty else { return }
        let location = convert(event.locationInWindow, from: nil)
        guard hypot(location.x - start.x, location.y - start.y) >= 4 else { return }
        let batch = ScreenshotShelfDragPayload.Batch(items: items)
        let draggingItems = ScreenshotShelfDragPayload.items(for: batch.urls, at: start)
        activeDrag = ActiveDrag(
            batch: batch,
            onStateChanged: onDragStateChanged,
            onEnded: onDragEnded
        )
        isDragging = true
        activeDrag?.onStateChanged?(true)
        let session = beginDraggingSession(with: draggingItems, event: mouseDownEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let completedDrag = activeDrag
        activeDrag = nil
        isDragging = false
        mouseDownLocation = nil
        mouseDownEvent = nil
        completedDrag?.onStateChanged?(false)
        if let completedDrag {
            guard !QuickAirDrop.shared.consumeDeferredScreenshotDrag(session.draggingSequenceNumber) else { return }
            completedDrag.onEnded?(
                completedDrag.batch.ids,
                ScreenshotShelfDragPayload.accepted(operation)
            )
        }
    }
}
