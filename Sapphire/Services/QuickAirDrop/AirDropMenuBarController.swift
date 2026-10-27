import AppKit
import Combine
import SwiftUI

@MainActor
final class AirDropMenuBarController: NSObject {
    private let sharing: QuickAirDrop
    private var item: NSStatusItem?
    private var observations = Set<AnyCancellable>()
    private var openMenu: NSMenu?

    init(sharing: QuickAirDrop? = nil) {
        self.sharing = sharing ?? .shared
        super.init()
        let sharing = self.sharing
        sharing.$menuBarEnabled.sink { [weak self] enabled in self?.updateVisibility(enabled: enabled) }.store(in: &observations)
        sharing.$isPreparing.sink { [weak self] preparing in self?.refresh(preparing: preparing) }.store(in: &observations)
        SessionPrivacyState.shared.$isSuppressed.sink { [weak self] suppressed in
            guard let self else { return }
            if suppressed { self.openMenu?.cancelTracking() }
            self.updateVisibility(enabled: self.sharing.menuBarEnabled, suppressed: suppressed)
        }.store(in: &observations)
        NotificationCenter.default.publisher(for: .sapphireLanguageDidChange).sink { [weak self] _ in
            self?.refresh(preparing: self?.sharing.isPreparing ?? false)
        }.store(in: &observations)
    }

    func shutdown() {
        observations.removeAll()
        openMenu?.cancelTracking()
        openMenu = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        sharing.cancelPreparation()
    }

    private func updateVisibility(enabled: Bool, suppressed: Bool? = nil) {
        guard enabled, !(suppressed ?? SessionPrivacyState.shouldSuppressUI()) else {
            openMenu?.cancelTracking()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        guard item == nil else { return }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.autosaveName = "SapphireQuickAirDrop"
        if let button = status.button {
            button.target = self
            button.action = #selector(showMenu)
            button.setAccessibilityIdentifier("SapphireQuickAirDrop")
            let drop = AirDropMenuDropView(frame: button.bounds, sharing: sharing)
            drop.autoresizingMask = [.width, .height]
            drop.onClick = { [weak self] in self?.showMenu() }
            button.addSubview(drop)
        }
        item = status
        refresh(preparing: sharing.isPreparing)
    }

    private func refresh(preparing: Bool) {
        let title = L10n.string(preparing ? "Preparing AirDrop…" : "Sapphire AirDrop — drop files, images, links, or text here")
        item?.button?.image = NSImage(systemSymbolName: preparing ? "hourglass" : QuickAirDrop.symbolName, accessibilityDescription: title)
        item?.button?.image?.isTemplate = true
        item?.button?.toolTip = title
        item?.button?.setAccessibilityLabel(title)
    }

    @objc private func showMenu() {
        guard !SessionPrivacyState.shouldSuppressUI(), let button = item?.button else { return }
        let menu = NSMenu()
        func add(_ title: String, action: Selector?, enabled: Bool = true) {
            let row = NSMenuItem(title: L10n.string(title), action: action, keyEquivalent: "")
            row.target = self
            row.isEnabled = enabled
            menu.addItem(row)
        }
        menu.autoenablesItems = false
        add("Sapphire AirDrop", action: nil, enabled: false)
        add("Drop files, images, links, or text onto this icon.", action: nil, enabled: false)
        menu.addItem(.separator())
        add("Choose Files for AirDrop…", action: #selector(chooseFiles), enabled: !sharing.isPreparing)
        add("AirDrop from Clipboard", action: #selector(shareClipboard), enabled: !sharing.isPreparing)
        menu.addItem(.separator())
        add("AirDrop Settings…", action: #selector(openSettings))
        openMenu = menu
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
        openMenu = nil
    }

    @objc private func chooseFiles() { sharing.chooseFiles() }
    @objc private func shareClipboard() { sharing.shareClipboard() }
    @objc private func openSettings() {
        guard !SessionPrivacyState.shouldSuppressUI() else { return }
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
        NotificationCenter.default.post(name: NSNotification.Name("SapphireSelectSection"), object: SettingsSection.fileShelf.rawValue)
    }
}

/// A native destination covers precisely its status button. It never installs a
/// global event tap or intercepts neighboring menu-bar items.
@MainActor
final class AirDropMenuDropView: NSView {
    let sharing: QuickAirDrop
    var onClick: (() -> Void)?
    private(set) var isTargeted = false
    init(frame: NSRect, sharing: QuickAirDrop) {
        self.sharing = sharing
        super.init(frame: frame)
        registerForDraggedTypes(AirDropPasteboard.types)
        setAccessibilityElement(false) // The native status button owns the label/action.
    }
    required init?(coder: NSCoder) { nil }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { if !SessionPrivacyState.shouldSuppressUI() { onClick?() } }
    override func rightMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func draw(_ dirtyRect: NSRect) {
        guard isTargeted else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 5, yRadius: 5).fill()
    }
    func accepts(_ pasteboard: NSPasteboard, operations: NSDragOperation) -> Bool {
        !SessionPrivacyState.shouldSuppressUI() && !sharing.isPreparing && operations.contains(.copy) && AirDropPasteboard.canRead(pasteboard)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isTargeted = accepts(sender.draggingPasteboard, operations: sender.draggingSourceOperationMask)
        needsDisplay = true
        return isTargeted ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        accepts(sender.draggingPasteboard, operations: sender.draggingSourceOperationMask)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        needsDisplay = true
        guard accepts(sender.draggingPasteboard, operations: sender.draggingSourceOperationMask) else { return false }
        return sharing.sharePasteboard(sender.draggingPasteboard, dragSequence: sender.draggingSequenceNumber)
    }
}

struct QuickAirDropSettingsView: View {
    @ObservedObject private var sharing = QuickAirDrop.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow(title: "AirDrop in the Menu Bar",
                      description: "Drop files, images, links, or text onto Sapphire’s AirDrop icon to choose a nearby device.",
                      isOn: $sharing.menuBarEnabled)
            Divider().padding(.leading, 20)
            HStack(spacing: 10) {
                Button("Choose Files for AirDrop…", action: sharing.chooseFiles)
                Button("AirDrop from Clipboard", action: sharing.shareClipboard)
            }
            .buttonStyle(.bordered)
            .disabled(sharing.isPreparing)
            .padding()
            Text("You choose the recipient in the macOS AirDrop window. You can also select several screenshots in the shelf and click AirDrop.")
                .font(.caption).foregroundStyle(.secondary)
                .padding([.horizontal, .bottom])
        }
    }
}
