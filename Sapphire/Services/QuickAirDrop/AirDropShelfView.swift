import AppKit
import SwiftUI

/// An AirDrop tool inside the same shelf as Screenshots and Files.
@MainActor
struct AirDropShelfView: View {
    @ObservedObject private var sharing: QuickAirDrop
    @State private var isTargeted = false

    init(sharing: QuickAirDrop? = nil) {
        _sharing = ObservedObject(wrappedValue: sharing ?? .shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AirDrop", systemImage: QuickAirDrop.symbolName)
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6]))
                VStack(spacing: 8) {
                    if sharing.isPreparing {
                        ProgressView().controlSize(.small)
                        Text("Preparing AirDrop…").font(.subheadline.weight(.medium))
                    } else {
                        Image(systemName: QuickAirDrop.symbolName)
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                        Text("Drop items here to AirDrop")
                            .font(.subheadline.weight(.medium))
                        Text("Files, folders, images, links, and text")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 126)
            .overlay {
                AirDropDropTarget(sharing: sharing, isTargeted: $isTargeted)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                Button("Choose Files for AirDrop…", action: sharing.chooseFiles)
                Button("AirDrop from Clipboard", action: sharing.shareClipboard)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(sharing.isPreparing)

            Text("Choose the receiving device in the macOS AirDrop window. Cancel to keep your files.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { isTargeted = false }
    }
}

private struct AirDropDropTarget: NSViewRepresentable {
    let sharing: QuickAirDrop
    @Binding var isTargeted: Bool

    func makeNSView(context: Context) -> AirDropDropView {
        let view = AirDropDropView(frame: .zero, sharing: sharing)
        view.targetChanged = { isTargeted = $0 }
        view.onClick = { sharing.chooseFiles() }
        return view
    }
    func updateNSView(_ view: AirDropDropView, context: Context) {
        view.targetChanged = { isTargeted = $0 }
    }
    static func dismantleNSView(_ view: AirDropDropView, coordinator: ()) {
        view.targetChanged = nil
    }
}

/// Only the visible drop area receives drag/click events. Buttons and other
/// shelf tabs retain their normal input and accessibility behavior.
@MainActor
final class AirDropDropView: NSView {
    let sharing: QuickAirDrop
    var onClick: (() -> Void)?
    var targetChanged: ((Bool) -> Void)?
    private(set) var isTargeted = false

    init(frame: NSRect, sharing: QuickAirDrop) {
        self.sharing = sharing
        super.init(frame: frame)
        registerForDraggedTypes(AirDropPasteboard.types)
        setAccessibilityElement(false) // The visible SwiftUI buttons are the keyboard/AX alternatives.
    }
    required init?(coder: NSCoder) { nil }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        if !SessionPrivacyState.shouldSuppressUI(), !sharing.isPreparing { onClick?() }
    }
    func clearTarget() { setTarget(false) }
    private func setTarget(_ targeted: Bool) {
        guard isTargeted != targeted else { return }
        isTargeted = targeted
        targetChanged?(targeted)
    }
    func accepts(_ pasteboard: NSPasteboard, operations: NSDragOperation) -> Bool {
        !SessionPrivacyState.shouldSuppressUI() && !sharing.isPreparing && operations.contains(.copy) && AirDropPasteboard.canRead(pasteboard)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = accepts(sender.draggingPasteboard, operations: sender.draggingSourceOperationMask)
        setTarget(accepted)
        return accepted ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearTarget() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        accepts(sender.draggingPasteboard, operations: sender.draggingSourceOperationMask)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        clearTarget()
        guard accepts(sender.draggingPasteboard, operations: sender.draggingSourceOperationMask) else { return false }
        return sharing.sharePasteboard(sender.draggingPasteboard, dragSequence: sender.draggingSequenceNumber)
    }
}

@MainActor
struct QuickAirDropSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AirDrop in Sapphire", systemImage: QuickAirDrop.symbolName)
                .font(.headline)
            Text("Open File Shelf → AirDrop in Sapphire to drop items, choose files, or share your clipboard. You can also AirDrop selected screenshots from the Screenshots tab.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }
}
