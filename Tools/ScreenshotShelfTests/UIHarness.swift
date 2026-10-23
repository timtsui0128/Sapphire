import AppKit
import SwiftUI
import WebKit

/// Local, isolated browser-drop acceptance test. Contains only generated fixtures.
@main
struct ScreenshotShelfUIHarness: App {
    @StateObject private var manager: ScreenshotShelfManager

    init() {
        let root = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-screenshot-ui-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "com.sapphire.screenshots.ui-test")!
        defaults.set(false, forKey: "ScreenshotShelfCaptureEnabled")
        // A second argument selects a policy for fresh fixtures, allowing real
        // successful/canceled drag checks without touching the user's shelf.
        let retention = CommandLine.arguments.dropFirst(2).first
            .flatMap(ScreenshotShelfRetention.init(rawValue:)) ?? .persistent
        defaults.set(retention.rawValue, forKey: "ScreenshotShelfRetention")
        let manager = ScreenshotShelfManager(storageURL: root.appendingPathComponent("owned"), defaults: defaults)
        _manager = StateObject(wrappedValue: manager)
        let sources = root.appendingPathComponent("fixtures")
        try! FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        var urls: [URL] = []
        for index in 1...5 {
            let image = NSImage(size: NSSize(width: 640, height: 400))
            image.lockFocus()
            NSColor(calibratedHue: CGFloat(index) / 6, saturation: 0.32, brightness: 0.95, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 640, height: 400).fill()
            ("Screenshot \(index)" as NSString).draw(at: NSPoint(x: 40, y: 190), withAttributes: [
                .font: NSFont.systemFont(ofSize: 44, weight: .semibold),
                .foregroundColor: NSColor.black
            ])
            ("Generated test fixture" as NSString).draw(at: NSPoint(x: 42, y: 145), withAttributes: [
                .font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.darkGray
            ])
            image.unlockFocus()
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            let url = sources.appendingPathComponent("Screenshot \(index).png")
            try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
            urls.append(url)
        }
        manager.importFiles(from: urls)
    }

    var body: some Scene {
        Window("Screenshot Shelf — Local Browser Test", id: "ui-test") {
            VStack(spacing: 0) {
                ScreenshotShelfView(manager: manager)
                Divider()
                BrowserDropTarget().frame(height: 225)
            }
            .frame(width: 680)
        }
        .windowResizability(.contentSize)
    }
}

private struct BrowserDropTarget: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.loadHTMLString("""
        <!doctype html><html><meta name="viewport" content="width=device-width">
        <style>
        body{font:14px -apple-system,sans-serif;margin:16px;color:#222;background:#fff}
        #drop{border:2px dashed #8c9dac;border-radius:12px;padding:18px;text-align:center}
        #drop.active{background:#e4f2ff;border-color:#007aff}
        h3{margin:0 0 8px;font-size:17px} p{margin:8px}
        #files{font-size:12px;line-height:1.5}
        </style>
        <div id="drop"><h3>Local browser attachment test</h3>
        <p>Drag the selected screenshots here.</p>
        <strong id="result" role="status">0 files received</strong>
        <div id="files"></div></div>
        <script>
        const drop = document.getElementById('drop');
        drop.addEventListener('dragover', event => {
          event.preventDefault(); event.dataTransfer.dropEffect='copy'; drop.classList.add('active');
        });
        drop.addEventListener('dragleave', () => drop.classList.remove('active'));
        drop.addEventListener('drop', event => {
          event.preventDefault(); drop.classList.remove('active');
          const files = Array.from(event.dataTransfer.files);
          document.getElementById('result').textContent = files.length + ' files received';
          document.getElementById('files').textContent = files.map(file => file.name + ' (' + file.size + ' bytes)').join(' · ');
        });
        </script></html>
        """, baseURL: nil)
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
