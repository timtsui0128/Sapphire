import AppKit
import Combine

/// A visible map of the snap trigger, never a drop receiver or input overlay.
/// Each display controller owns its own instance and explicitly hides it on
/// release, cancellation, panel expansion and Mission Control handoff.
@MainActor
final class SnapActivationHint {
    private(set) var window: NSPanel?
    private var privacyObservation: AnyCancellable?

    init() {
        privacyObservation = SessionPrivacyState.shared.$isSuppressed.sink { [weak self] suppressed in
            if suppressed { self?.hide() }
        }
    }

    func show(frame: CGRect, isTargeted: Bool, relativeTo host: NSWindow) {
        guard !SessionPrivacyState.shouldSuppressUI(), !frame.isNull, !frame.isEmpty else {
            hide()
            return
        }
        if window == nil {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.sharingType = .none
            panel.collectionBehavior = host.collectionBehavior
            panel.level = host.level
            panel.contentView = SnapActivationHintView(frame: CGRect(origin: .zero, size: frame.size))
            window = panel
            (NSApp.delegate as? AppDelegate)?.attachAuxiliaryNotchWindow(panel)
        }
        guard let window else { return }
        window.appearance = host.effectiveAppearance
        if window.frame != frame { window.setFrame(frame, display: false) }
        (window.contentView as? SnapActivationHintView)?.update(isTargeted: isTargeted)
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() { window?.orderOut(nil) }

    func stop() {
        guard let window else { return }
        window.orderOut(nil)
        (NSApp.delegate as? AppDelegate)?.detachAuxiliaryNotchWindow(window)
        window.close()
        self.window = nil
    }
}

@MainActor
final class SnapActivationHintView: NSVisualEffectView {
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let opaqueBackground = NSView()
    private(set) var isTargeted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1.5
        opaqueBackground.frame = bounds
        opaqueBackground.autoresizingMask = [.width, .height]
        opaqueBackground.wantsLayer = true
        addSubview(opaqueBackground)
        icon.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 23, weight: .medium)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        for view in [icon, labels] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        update(isTargeted: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(isTargeted: Bool, reduceTransparency: Bool? = nil) {
        self.isTargeted = isTargeted
        opaqueBackground.isHidden = !(reduceTransparency ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        title.stringValue = L10n.string(isTargeted ? "Hold here to choose a layout" : "Drag here to split the window")
        subtitle.stringValue = L10n.string("Top edge: Mission Control")
        icon.contentTintColor = isTargeted ? .controlAccentColor : .labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            opaqueBackground.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = (isTargeted ? NSColor.controlAccentColor : .separatorColor).cgColor
        }
        setAccessibilityLabel(title.stringValue + ". " + subtitle.stringValue)
    }
}
