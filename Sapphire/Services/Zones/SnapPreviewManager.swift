//
//  SnapPreviewManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-24.
//

import SwiftUI
import AppKit

@MainActor
class SnapPreviewManager {
    static let shared = SnapPreviewManager()

    private var previewWindow: NSWindow?

    private init() {}

    func showPreview(for zone: SnapZone) {
        guard !SessionPrivacyState.shouldSuppressUI() else {
            previewWindow?.orderOut(nil)
            return
        }
        if previewWindow == nil {
            createPreviewWindow()
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
              let targetFrame = SnapWindowPlacement.frame(for: zone, in: screen.visibleFrame) else { return }

        if !(previewWindow?.isVisible ?? false) {
            previewWindow?.contentView?.alphaValue = 0
            previewWindow?.setFrame(targetFrame, display: true)
            previewWindow?.orderFront(nil)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            previewWindow?.animator().setFrame(targetFrame, display: true)
            previewWindow?.contentView?.animator().alphaValue = 1.0
        }
    }

    func hidePreview() {
        guard let window = previewWindow, window.isVisible else { return }
        guard !SessionPrivacyState.shouldSuppressUI() else {
            window.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.contentView?.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    private func createPreviewWindow() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .mainMenu - 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true

        let previewView = SnapPreviewView()
        let hostingView = NSHostingView(rootView: previewView)

        window.contentView = hostingView
        self.previewWindow = window
    }
}

fileprivate struct SnapPreviewView: View {
    var body: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(1)
    }
}
