//
//  SnappingManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-11.
//

import AppKit
import ApplicationServices
import QuartzCore

/// Keep the moved AX window, rather than choosing a new frontmost window at drop.
struct SnapWindowTarget: @unchecked Sendable {
    let pid: pid_t
    let window: AXUIElement

    init?(window: AXUIElement) {
        guard AX.role(of: window) == kAXWindowRole as String,
              let pid = AX.pid(of: window), pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        self.pid = pid
        self.window = window
    }
}

enum SnapZoneHitTesting {
    static let tolerance: CGFloat = 18

    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    static func nearest<Region>(
        _ regions: [Region],
        to point: CGPoint,
        frame: (Region) -> CGRect
    ) -> Region? {
        var best: (region: Region, distance: CGFloat)?
        for region in regions {
            let distance = distance(from: point, to: frame(region))
            if distance == 0 { return region }
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (region, distance)
            }
        }
        return best?.region
    }
}

@MainActor
final class SnappingManager {
    private struct Display: Sendable {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    private nonisolated static let queue = DispatchQueue(label: "com.sapphire.snapping", qos: .userInteractive)

    private nonisolated static let generationLock = NSLock()
    private nonisolated(unsafe) static var generations: [pid_t: UInt64] = [:]

    private nonisolated static let smoothDuration: CFTimeInterval = 0.25
    private nonisolated static let smoothFrameInterval: CFTimeInterval = 1.0 / 60.0

    static func snap(layoutID: UUID, zoneID: UUID) {
        let layouts = LayoutTemplate.allTemplates + SettingsModel.shared.current.customSnapLayouts
        guard let layout = layouts.first(where: { $0.id == layoutID }),
              let zone = layout.zones.first(where: { $0.id == zoneID }) else {
            print("[SnappingManager] Could not find layout/zone for shortcut.")
            return
        }

        snap(zone: zone)
    }

    static func snap(zone: SnapZone, target: SnapWindowTarget? = nil, screen: NSScreen? = nil, afterWindowDrag: Bool = false) {
        guard AccessibilityPermission.isProcessTrusted else {
            presentFailure(.permission)
            return
        }
        if let target {
            guard let app = NSRunningApplication(processIdentifier: target.pid) else {
                presentFailure(.windowUnavailable)
                return
            }
            snap(app: app, to: zone, target: target, screen: screen, afterWindowDrag: afterWindowDrag)
            return
        }
        guard let app = frontmostApplication() else {
            presentFailure(.windowUnavailable)
            return
        }
        snap(app: app, to: zone, screen: screen, afterWindowDrag: afterWindowDrag)
    }

    static func snap(app: NSRunningApplication, to zone: SnapZone, target: SnapWindowTarget? = nil, screen: NSScreen? = nil, afterWindowDrag: Bool = false) {
        guard !SessionPrivacyState.shouldSuppressUI() else { return }
        guard AccessibilityPermission.isProcessTrusted else {
            presentFailure(.permission)
            return
        }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        let displays = NSScreen.screens.map { Display(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let fallbackDisplay = NSScreen.main.map { Display(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let requestedDisplay = screen.map { Display(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let mainDisplayFrame = self.mainDisplayFrame
        let animation = SettingsModel.shared.current.snapWindowAnimation
        let pid = app.processIdentifier
        let generation = nextGeneration(for: pid)

        // Let the source application's mouse-up/tiling transaction finish first.
        queue.asyncAfter(deadline: .now() + (afterWindowDrag ? 0.12 : 0)) {
            guard isCurrent(generation, for: pid), !SessionPrivacyState.shouldSuppressUI(),
                  !CGEventSource.buttonState(.combinedSessionState, button: .left) else { return }
            guard let windowElement = target?.window ?? mostLikelyMainWindow(pid: pid),
                  let axFrame = AX.windowFrame(of: windowElement),
                  axFrame.width > 0, axFrame.height > 0 else {
                reportFailure(.windowUnavailable, pid: pid, generation: generation)
                return
            }
            guard AX.bool("AXFullScreen", of: windowElement) != true else {
                reportFailure(.unsupportedWindow, pid: pid, generation: generation)
                return
            }

            let cocoaFrame = CGRect(
                x: axFrame.minX,
                y: (mainDisplayFrame?.maxY ?? 0) - axFrame.minY - axFrame.height,
                width: axFrame.width,
                height: axFrame.height
            )
            guard let display = requestedDisplay ?? display(for: cocoaFrame, in: displays) ?? fallbackDisplay,
                  let targetFrame = SnapWindowPlacement.frame(for: zone, in: display.visibleFrame) else { return }
            let mainDisplayMaxY = mainDisplayFrame?.maxY ?? display.frame.maxY
            let targetAXFrame = SnapWindowPlacement.axFrame(from: targetFrame, primaryDisplayMaxY: mainDisplayMaxY)

            if animation == .smooth {
                animate(windowElement, from: axFrame, to: targetAXFrame, pid: pid, generation: generation)
                guard isCurrent(generation, for: pid) else { return }
            }

            let result = SnapWindowPlacement.apply(targetAXFrame,
                read: { AX.windowFrame(of: windowElement) },
                setSize: { _ = AX.set(kAXSizeAttribute as String, toSize: $0, on: windowElement) },
                setPosition: { _ = AX.set(kAXPositionAttribute as String, toPoint: $0, on: windowElement) },
                shouldContinue: { isCurrent(generation, for: pid) && AXIsProcessTrusted()
                    && !SessionPrivacyState.isSuppressedSnapshot
                    && !CGEventSource.buttonState(.combinedSessionState, button: .left) },
                pause: { Thread.sleep(forTimeInterval: $0) })
            if result == .failed {
                reportFailure(.unsupportedWindow, pid: pid, generation: generation)
            }
        }
    }

    // MARK: - Moving the window (snapping queue)

    private nonisolated static func animate(
        _ window: AXUIElement,
        from start: CGRect,
        to end: CGRect,
        pid: pid_t,
        generation: UInt64
    ) {
        let startTime = CACurrentMediaTime()
        while isCurrent(generation, for: pid), AXIsProcessTrusted(), !SessionPrivacyState.isSuppressedSnapshot,
              !CGEventSource.buttonState(.combinedSessionState, button: .left) {
            let elapsed = CACurrentMediaTime() - startTime
            let progress = elapsed / smoothDuration
            guard progress < 1 else { return }

            let eased = 1 - pow(1 - progress, 3)
            let frame = CGRect(
                x: (start.minX + (end.minX - start.minX) * eased).rounded(),
                y: (start.minY + (end.minY - start.minY) * eased).rounded(),
                width: (start.width + (end.width - start.width) * eased).rounded(),
                height: (start.height + (end.height - start.height) * eased).rounded()
            )
            let sized = AX.set(kAXSizeAttribute as String, toSize: frame.size, on: window)
            let positioned = AX.set(kAXPositionAttribute as String, toPoint: frame.origin, on: window)
            guard sized || positioned else { return }

            let nextFrameTime = startTime + (floor(elapsed / smoothFrameInterval) + 1) * smoothFrameInterval
            let wait = nextFrameTime - CACurrentMediaTime()
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
    }

    private nonisolated static func nextGeneration(for pid: pid_t) -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        let generation = (generations[pid] ?? 0) &+ 1
        generations[pid] = generation
        return generation
    }

    private nonisolated static func isCurrent(_ generation: UInt64, for pid: pid_t) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generations[pid] == generation
    }

    // MARK: - Lookup

    private enum Failure { case permission, windowUnavailable, unsupportedWindow }
    private static var isPresentingFailure = false

    private nonisolated static func reportFailure(_ failure: Failure, pid: pid_t, generation: UInt64) {
        Task { @MainActor in
            guard isCurrent(generation, for: pid) else { return }
            presentFailure(AccessibilityPermission.isProcessTrusted ? failure : .permission)
        }
    }

    private static func presentFailure(_ failure: Failure) {
        guard !isPresentingFailure, !SessionPrivacyState.shouldSuppressUI() else { return }
        let message: String
        switch failure {
        case .permission:
            if #available(macOS 27.0, *) {
                message = "Allow TopLet in System Settings → Privacy & Security → Device Control and Data Access to move and resize windows. If it is already enabled after an update, remove the old entry and add the TopLet app you are currently using."
            } else {
                message = "Allow TopLet in System Settings → Privacy & Security → Accessibility to move and resize windows. If it is already enabled after an update, remove the old entry and add the TopLet app you are currently using."
            }
        case .windowUnavailable:
            message = "The dragged window is no longer available. Drag a normal application window to a layout and try again."
        case .unsupportedWindow:
            message = "This window did not accept the selected layout. Exit full screen and try a larger zone; some apps limit how small their windows can be."
        }
        isPresentingFailure = true
        HelperAlertPresenter.presentModal(messageText: "Couldn’t arrange this window",
            informativeText: message, alertStyle: .warning,
            buttonTitles: failure == .permission ? ["Open Window Control Settings", "Cancel"] : ["OK"]) { index in
                isPresentingFailure = false
                if failure == .permission, index == 0 { AccessibilityPermission.openSystemSettings() }
            }
    }

    private static func frontmostApplication() -> NSRunningApplication? {
        let ownBundleID = Bundle.main.bundleIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != ownBundleID {
            return frontmost
        }

        if let activeApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.isActive && $0.bundleIdentifier != ownBundleID
        }) {
            return activeApp
        }

        if let bundleID = ActiveAppMonitor.shared.activeAppBundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return app
        }

        return nil
    }

    private nonisolated static func mostLikelyMainWindow(pid: pid_t) -> AXUIElement? {
        let appElement = AX.application(pid: pid)

        if let focused = AX.focusedWindow(ofApplication: appElement), !isMinimized(focused) {
            return focused
        }

        if let main = AX.mainWindow(ofApplication: appElement), !isMinimized(main) {
            return main
        }

        var fallbackWindow: AXUIElement?
        for window in AX.elements(kAXWindowsAttribute as String, of: appElement) where !isMinimized(window) {
            if fallbackWindow == nil {
                fallbackWindow = window
            }

            if AX.subrole(of: window) == kAXStandardWindowSubrole as String {
                return window
            }
        }

        return fallbackWindow
    }

    private nonisolated static func isMinimized(_ window: AXUIElement) -> Bool {
        AX.bool(kAXMinimizedAttribute as String, of: window) == true
    }

    private nonisolated static func display(for cocoaFrame: CGRect, in displays: [Display]) -> Display? {
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        return displays.first(where: { $0.frame.contains(center) })
            ?? displays.first(where: { $0.frame.intersects(cocoaFrame) })
    }

    private static var mainDisplayFrame: CGRect? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return displayID == mainDisplayID
        }?.frame
    }
}
