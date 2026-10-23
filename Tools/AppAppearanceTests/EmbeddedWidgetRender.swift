import AppKit
import SwiftUI

/// Test the actual feature view over a colored witness surface. An opaque card
/// would cover this pixel even when the native panel underneath is glass.
@MainActor
func checkEmbeddedWidget<Content: View>(_ content: Content, size: CGSize, scheme: ColorScheme, to output: URL) async throws {
    let witness = NSColor(srgbRed: 0.91, green: 0.17, blue: 0.61, alpha: 1)
    let feature = content
        .appPanelAppearance()
        .environment(\.expandedNotchColorScheme, scheme)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color(nsColor: witness))
    let root = HStack(spacing: 0) {
        Color(nsColor: witness).frame(width: 16)
        feature
    }
    let host = NSHostingView(rootView: root)
    let frame = NSRect(x: 0, y: 0, width: size.width + 16, height: size.height)
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.frame = frame
    try await Task.sleep(for: .milliseconds(60))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    func sample(_ x: CGFloat) -> NSColor {
        bitmap.colorAt(x: Int(x * CGFloat(bitmap.pixelsWide) / frame.width), y: Int(24 * CGFloat(bitmap.pixelsHigh) / frame.height))!.usingColorSpace(.sRGB)!
    }
    let color = sample(19), reference = sample(3)
    guard abs(color.redComponent - reference.redComponent) < 0.02,
          abs(color.greenComponent - reference.greenComponent) < 0.02,
          abs(color.blueComponent - reference.blueComponent) < 0.02 else {
        throw NSError(domain: "EmbeddedWidgetRender", code: 1, userInfo: [NSLocalizedDescriptionKey: "An opaque card covers the panel material in \(output.lastPathComponent): \(color)"])
    }
    try bitmap.representation(using: .png, properties: [:])!.write(to: output)
    print("PASS: \(output.lastPathComponent) reveals the parent panel material, including under a dark host")
    window.close()
}
