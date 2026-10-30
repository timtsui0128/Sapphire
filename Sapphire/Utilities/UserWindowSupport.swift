//
//  UserWindowSupport.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit
import SwiftUI
import ServiceManagement
import Combine

extension Notification.Name {
    static let sapphireHelperConnectionLost = Notification.Name("sapphireHelperConnectionLost")
    static let sapphireHelperConnectionRestored = Notification.Name("sapphireHelperConnectionRestored")
    static let sapphireSettingsWillClose = Notification.Name("sapphireSettingsWillClose")
    static let sapphireUpdateAvailable = Notification.Name("sapphireUpdateAvailable")
}

enum SapphireStandardMenu {
    static func installIfNeeded() {
        guard NSApp.mainMenu == nil || !hasEditMenu else { return }

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: L10n.string("Quit TopLet"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem(title: L10n.string("Edit"), action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L10n.string("Edit"))
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: L10n.string("Undo"), action: Selector("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.string("Redo"), action: Selector("redo:"), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.string("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.string("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.string("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.string("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    private static var hasEditMenu: Bool {
        NSApp.mainMenu?.items.contains { item in
            item.submenu?.items.contains { $0.action == Selector("undo:") } == true
        } == true
    }

    static func refreshLanguage() {
        let titles = ["terminate:": "Quit TopLet", "undo:": "Undo", "redo:": "Redo",
                      "cut:": "Cut", "copy:": "Copy", "paste:": "Paste", "selectAll:": "Select All"]
        func refresh(_ menu: NSMenu) {
            for item in menu.items {
                if let action = item.action, let key = titles[NSStringFromSelector(action)] {
                    item.title = L10n.string(key)
                }
                if let submenu = item.submenu {
                    if submenu.items.contains(where: { $0.action == Selector("undo:") }) {
                        item.title = L10n.string("Edit")
                        submenu.title = item.title
                    }
                    refresh(submenu)
                }
            }
        }
        if let menu = NSApp.mainMenu { refresh(menu) }
    }
}

enum UtilityWindowMetrics {
    static func visibleFrame(for screen: NSScreen? = NSScreen.main) -> NSRect {
        screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 950, height: 650)
    }

    static func maxUserWindowHeight(screen: NSScreen? = NSScreen.main) -> CGFloat {
        visibleFrame(for: screen).height
    }

    static func settingsDefaultSize(screen: NSScreen? = NSScreen.main) -> NSSize {
        let visible = visibleFrame(for: screen)
        let width = min(
            NotchConfiguration.settingsWindowWidth,
            floor(visible.width * 0.92)
        )
        let height = floor(visible.height)
        return NSSize(
            width: min(visible.width, max(NotchConfiguration.settingsWindowMinWidth, width)),
            height: min(visible.height, max(NotchConfiguration.settingsWindowMinHeight, height))
        )
    }

    static func onboardingWindowSize(screen: NSScreen? = NSScreen.main) -> NSSize {
        let visible = visibleFrame(for: screen)
        let width = min(
            NotchConfiguration.onboardingWindowWidth,
            floor(visible.width * 0.92)
        )
        let height = floor(visible.height)
        return NSSize(
            width: max(NotchConfiguration.settingsWindowMinWidth, width),
            height: max(NotchConfiguration.settingsWindowMinHeight, height)
        )
    }

    static func fittedSize(
        preferredWidth: CGFloat,
        preferredHeight: CGFloat,
        screen: NSScreen? = NSScreen.main,
        maxWidthFraction: CGFloat = 0.90,
        maxHeightFraction: CGFloat = 0.82
    ) -> NSSize {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let maxWidth = floor(visible.width * maxWidthFraction)
        let maxHeight = floor(visible.height * maxHeightFraction)
        return NSSize(
            width: min(preferredWidth, max(1, maxWidth)),
            height: min(preferredHeight, max(1, maxHeight))
        )
    }

    /// Geometry snapshots keep topology selection testable without changing physical displays.
    struct ScreenGeometry {
        let displayID: UInt32
        let frame: NSRect
        let visibleFrame: NSRect
    }

    static func targetVisibleFrame(
        for windowFrame: NSRect,
        preferredDisplayID: UInt32?,
        screens: [ScreenGeometry]
    ) -> NSRect? {
        let connected = screens.filter { isUsable($0.frame) && isUsable($0.visibleFrame) }
        guard !connected.isEmpty else { return nil }
        // A disconnected NSScreen instance must never supply geometry. Prefer the
        // largest actual overlap; the connected screen identity resolves ties.
        let preferred = connected.first { $0.displayID == preferredDisplayID }
        let intersections = connected.map { screen -> (ScreenGeometry, CGFloat) in
            let overlap = screen.frame.intersection(windowFrame)
            return (screen, overlap.isNull ? 0 : overlap.width * overlap.height)
        }
        let largestArea = intersections.map { $0.1 }.max() ?? 0
        if largestArea > 0 {
            let candidates = intersections.filter { $0.1 == largestArea }.map { $0.0 }
            return (candidates.first { $0.displayID == preferred?.displayID } ?? candidates[0]).visibleFrame
        }
        if let preferred { return preferred.visibleFrame }
        // The old external display may no longer exist. Pick the nearest connected
        // display instead of NSScreen.main, which can belong to another window.
        let point = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        return connected.min { distanceSquared(point, to: $0.frame) < distanceSquared(point, to: $1.frame) }?.visibleFrame
    }

    static func fittedFrame(_ frame: NSRect, minimumSize: NSSize, visibleFrame: NSRect) -> NSRect {
        guard isUsable(visibleFrame) else { return frame }
        let minimum = boundedMinimum(minimumSize, visibleFrame: visibleFrame)
        let width = min(visibleFrame.width, max(minimum.width, frame.width.isFinite ? frame.width : minimum.width))
        let height = min(visibleFrame.height, max(minimum.height, frame.height.isFinite ? frame.height : minimum.height))
        let overlaps = isUsable(frame) && !frame.intersection(visibleFrame).isEmpty
        let proposedX = overlaps ? frame.minX : visibleFrame.midX - width / 2
        // Preserve the titlebar's height when shrinking a window already on screen.
        let proposedY = overlaps ? frame.maxY - height : visibleFrame.midY - height / 2
        return NSRect(
            x: min(max(proposedX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(proposedY, visibleFrame.minY), visibleFrame.maxY - height),
            width: width, height: height
        )
    }

    @MainActor
    @discardableResult
    static func constrain(
        window: NSWindow,
        minimumSize: NSSize,
        preferredScreen: NSScreen? = nil
    ) -> NSRect? {
        let screens = NSScreen.screens.compactMap { screen -> ScreenGeometry? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return ScreenGeometry(displayID: id.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
        let preferred = preferredScreen ?? window.screen
        let preferredID = (preferred?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let visible = targetVisibleFrame(for: window.frame, preferredDisplayID: preferredID, screens: screens) else { return nil }
        return constrain(window: window, minimumSize: minimumSize, visibleFrame: visible)
    }

    /// All limits are window-frame sizes, including a titled window's titlebar.
    /// This overload lets native fixture windows exercise a synthetic smaller display.
    @MainActor
    @discardableResult
    static func constrain(window: NSWindow, minimumSize: NSSize, visibleFrame: NSRect) -> NSRect {
        guard isUsable(visibleFrame) else { return window.frame }
        let minimum = boundedMinimum(minimumSize, visibleFrame: visibleFrame)
        let fitted = fittedFrame(window.frame, minimumSize: minimum, visibleFrame: visibleFrame)
        // Relax old minima first. Otherwise AppKit can refuse the smaller frame or
        // restore the old external-display size as content constraints are applied.
        window.contentMinSize = .zero
        window.minSize = .zero
        window.maxSize = visibleFrame.size
        let maximumContent = window.contentRect(forFrameRect: NSRect(origin: .zero, size: visibleFrame.size)).size
        window.contentMaxSize = NSSize(width: max(0, maximumContent.width), height: max(0, maximumContent.height))
        window.minSize = minimum
        let minimumContent = window.contentRect(forFrameRect: NSRect(origin: .zero, size: minimum)).size
        window.contentMinSize = NSSize(width: max(0, minimumContent.width), height: max(0, minimumContent.height))
        if window.frame != fitted { window.setFrame(fitted, display: window.isVisible, animate: false) }
        return window.frame
    }

    private static func boundedMinimum(_ size: NSSize, visibleFrame: NSRect) -> NSSize {
        NSSize(
            width: min(visibleFrame.width, max(1, size.width.isFinite ? size.width : 1)),
            height: min(visibleFrame.height, max(1, size.height.isFinite ? size.height : 1))
        )
    }

    private static func isUsable(_ rect: NSRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }

    private static func distanceSquared(_ point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    static func centeredFrame(size: NSSize, screen: NSScreen? = NSScreen.main) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

enum UtilityWindowPresenter {
    private static let elevatedWindowLevel = NSWindow.Level.normal

    static func presentSettingsWindow(_ window: NSWindow) {
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            guard !SessionPrivacyState.shouldSuppressUI() else { window.orderOut(nil); return }

            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            if NSApp.isHidden {
                NSApp.unhide(nil)
            }

            window.collectionBehavior = .fullScreenAuxiliary
            window.level = .normal
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func present(_ window: NSWindow) {
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            guard !SessionPrivacyState.shouldSuppressUI() else { window.orderOut(nil); return }

            activateAsRegularApp()
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.level = elevatedWindowLevel
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.center()

            window.makeKeyAndOrderFront(nil)
        }
    }

    static func activateAsRegularApp() {
        guard !SessionPrivacyState.shouldSuppressUI() else { return }
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
enum HelperAlertPresenter {
    private static var hostWindow: KeyableWindow?
    private static var activeModalCount = 0

    static func showHelperConnectionLost(onDismiss: (() -> Void)? = nil) {
        presentModal(
            messageText: "Sapphire Helper Needs Attention",
            informativeText: """
            TopLet lost connection to its system helper.

            Click “Reset Helper” to unregister TopLet’s own background items, reinstall the helper, and relaunch. Other apps are not affected.
            """,
            alertStyle: .warning,
            buttonTitles: ["Reset Helper", "OK"]
        ) { index in
            if index == 0 {
                HelperManager.shared.resetOwnBackgroundActivity()
            }
            onDismiss?()
        }
    }

    static func present(_ issue: HelperIssue) {
        let buttons: [String]
        switch issue {
        case .notFound:
            buttons = ["Reset Helper", "Relaunch TopLet", "OK"]
        case .needsApproval:
            buttons = ["Open Login Items", "OK"]
        case .spawnFailed:
            buttons = ["Reset Helper", "Open Login Items", "OK"]
        }

        presentModal(
            messageText: "Sapphire Helper  ·  \(issue.code)",
            informativeText: issue.instructions,
            alertStyle: issue == .spawnFailed ? .critical : .warning,
            buttonTitles: buttons
        ) { index in
            switch issue {
            case .notFound:
                if index == 0 {
                    HelperManager.shared.resetOwnBackgroundActivity()
                } else if index == 1 {
                    HelperManager.relaunchApp()
                }
            case .needsApproval:
                if index == 0 {
                    SMAppService.openSystemSettingsLoginItems()
                }
            case .spawnFailed:
                if index == 0 {
                    HelperManager.shared.resetOwnBackgroundActivity()
                } else if index == 1 {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        }
    }

    static func presentModal(
        messageText: String,
        informativeText: String,
        alertStyle: NSAlert.Style = .warning,
        accessoryView: NSView? = nil,
        buttonTitles: [String],
        completion: @escaping (Int) -> Void
    ) {
        guard !SessionPrivacyState.shouldSuppressUI() else {
            completion(-1)
            return
        }
        UtilityWindowPresenter.activateAsRegularApp()

        let host = acquireHostWindow()
        host.orderFrontRegardless()
        host.makeKeyAndOrderFront(nil)

        let alert = NSAlert()
        alert.messageText = L10n.string(messageText)
        alert.informativeText = L10n.string(informativeText)
        alert.alertStyle = alertStyle
        if let accessoryView {
            alert.accessoryView = accessoryView
            alert.window.initialFirstResponder = accessoryView
        }
        for title in buttonTitles {
            alert.addButton(withTitle: L10n.string(title))
        }

        activeModalCount += 1

        DispatchQueue.main.async {
            guard !SessionPrivacyState.shouldSuppressUI() else {
                releaseHostWindowIfIdle()
                completion(-1)
                return
            }
            var privacyObservation: AnyCancellable?
            alert.beginSheetModal(for: host) { response in
                privacyObservation?.cancel()
                privacyObservation = nil
                releaseHostWindowIfIdle()
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                completion(SessionPrivacyState.shouldSuppressUI() ? -1 : index)
            }
            privacyObservation = SessionPrivacyState.shared.$isSuppressed.sink { suppressed in
                guard suppressed else { return }
                host.endSheet(alert.window, returnCode: .cancel)
                alert.window.orderOut(nil)
                host.orderOut(nil)
            }
        }
    }

    private static func acquireHostWindow() -> KeyableWindow {
        if let hostWindow {
            return hostWindow
        }

        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("TopLet")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.001
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.center()
        hostWindow = window
        return window
    }

    private static func releaseHostWindowIfIdle() {
        activeModalCount = max(0, activeModalCount - 1)
        guard activeModalCount == 0 else { return }
        hostWindow?.orderOut(nil)
        hostWindow = nil
    }
}

final class FocusableHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleStandardEditShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handleStandardEditShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command) else {
            return false
        }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let selector: Selector?
        switch key {
        case "c":
            selector = #selector(NSText.copy(_:))
        case "v":
            selector = #selector(NSText.paste(_:))
        case "x":
            selector = #selector(NSText.cut(_:))
        case "a":
            selector = #selector(NSText.selectAll(_:))
        case "z":
            selector = event.modifierFlags.contains(.shift) ? Selector("redo:") : Selector("undo:")
        default:
            selector = nil
        }

        guard let selector else { return false }
        return NSApp.sendAction(selector, to: nil, from: self)
    }
}
