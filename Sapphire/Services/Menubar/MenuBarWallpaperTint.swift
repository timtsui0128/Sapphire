//
//  MenuBarWallpaperTint.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-27
//

import AppKit
import Combine
import ImageIO

extension Notification.Name {
    static let menuBarWallpaperTintDidChange = Notification.Name("com.sapphire.menuBarWallpaperTintDidChange")
}

@MainActor
final class MenuBarWallpaperTint: ObservableObject {
    static let shared = MenuBarWallpaperTint()

    struct Tint: Equatable {
        let leading: NSColor
        let trailing: NSColor
        var center: NSColor? = nil

        var average: NSColor {
            leading.blended(withFraction: 0.5, of: trailing) ?? leading
        }
    }

    @Published private(set) var tints: [CGDirectDisplayID: Tint] = [:]
    private var owners = Set<AnyHashable>()

    private var isRunning = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var storeWatcher: DispatchSourceFileSystemObject?
    private var pendingSample: DispatchWorkItem?
    private struct SampleKey: Hashable {
        let url: URL
        let aspectRatio: CGFloat
    }
    private var cache: [SampleKey: Tint] = [:]

    private let sampleQueue = DispatchQueue(label: "com.sapphire.menubar-wallpaper-tint", qos: .utility)

    private init() {}

    func tint(for displayID: CGDirectDisplayID) -> Tint? {
        tints[displayID]
    }

    func start(owner: AnyHashable = "menuBarOverlay") {
        owners.insert(owner)
        guard !isRunning else { return }
        isRunning = true

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSample() }
        }))
        let app = NotificationCenter.default
        observers.append((app, app.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSample() }
        }))
        watchWallpaperStore()
        scheduleSample(delay: 0)
    }

    func stop(owner: AnyHashable = "menuBarOverlay") {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        guard isRunning else { return }
        isRunning = false
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        storeWatcher?.cancel()
        storeWatcher = nil
        pendingSample?.cancel()
        pendingSample = nil
    }

    // MARK: - Change sources

    private func watchWallpaperStore() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleSample() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        storeWatcher = source
    }

    private func scheduleSample(delay: TimeInterval = 0.4) {
        pendingSample?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.sample() }
        }
        pendingSample = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Sampling

    private func sample() {
        let requests: [(CGDirectDisplayID, SampleKey)] = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, SampleKey)? in
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            return (screen.displayID, SampleKey(url: url, aspectRatio: screen.frame.width / max(1, screen.frame.height)))
        }
        let cached = cache
        sampleQueue.async { [weak self] in
            var sampled: [CGDirectDisplayID: Tint] = [:]
            var fresh: [SampleKey: Tint] = [:]
            for (displayID, key) in requests {
                if let tint = cached[key] ?? fresh[key] ?? Self.sampleTopStrip(of: key.url, aspectRatio: key.aspectRatio) {
                    sampled[displayID] = tint
                    fresh[key] = tint
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isRunning else { return }
                    self.cache = fresh
                    guard sampled != self.tints else { return }
                    self.tints = sampled
                    NotificationCenter.default.post(name: .menuBarWallpaperTintDidChange, object: nil)
                }
            }
        }
    }

    nonisolated static func sampleTopStrip(of url: URL, aspectRatio: CGFloat) -> Tint? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 160,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        // Wallpaper normally fills each display. Sample the visible top edge
        // after its centered aspect-fill crop, including different screen ratios.
        var visible = CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height)
        let aspect = max(0.1, aspectRatio)
        if visible.width / visible.height > aspect {
            let width = visible.height * aspect
            visible.origin.x = (visible.width - width) / 2
            visible.size.width = width
        } else {
            let height = visible.width / aspect
            visible.origin.y = (visible.height - height) / 2
            visible.size.height = height
        }
        let stripRect = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: max(2, visible.height * 0.06)).integral
        guard let strip = thumbnail.cropping(to: stripRect) else { return nil }

        var pixels = [UInt8](repeating: 0, count: 12)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 3,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 12,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(strip, in: CGRect(x: 0, y: 0, width: 3, height: 1))
            return true
        }
        guard drawn else { return nil }

        func color(at offset: Int) -> NSColor {
            NSColor(
                srgbRed: CGFloat(pixels[offset]) / 255,
                green: CGFloat(pixels[offset + 1]) / 255,
                blue: CGFloat(pixels[offset + 2]) / 255,
                alpha: 1
            )
        }
        return Tint(leading: color(at: 0), trailing: color(at: 8), center: color(at: 4))
    }
}
