import AppKit
import Foundation

// The real identity mapper uses only these flags for in-app Apple Music.
enum AppleMusicPlaybackIdentity {
    static let hostBundleID = "local.sapphire.artwork-checks"
    static let isInAppPlaybackActive = false
}

@main
struct MusicArtworkChecks {
    @MainActor static func main() async throws {
        let controller = NativeMediaController()
        controller.isListening = true
        let parser = NowPlayingStreamParser()
        var last: TrackInfo.Payload?
        controller.onTrackInfoReceived = { last = $0?.payload }

        func image(_ red: Int, _ green: Int) throws -> String {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            var pixel = [red, green, 0, 255]
            pixel.withUnsafeMutableBufferPointer { buffer in
                for x in 0..<4 { for y in 0..<4 { rep.setPixel(buffer.baseAddress!, atX: x, y: y) } }
            }
            return rep.representation(using: .png, properties: [:])!.base64EncodedString()
        }
        func feed(_ metadata: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: ["payload": metadata])
            data.append(0x0A)
            for event in parser.consume(data) {
                controller.handleTrackUpdate(event.metadata, artwork: event.artwork)
            }
        }
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { print("FAIL: \(message)"); exit(1) }
            print("PASS: \(message)")
        }
        let a = try image(255, 0), b = try image(0, 255)
        try feed(["bundleIdentifier": "com.netease.163music", "title": "Song A",
                  "artist": "Artist", "album": "Album A", "playing": true, "artworkData": a])
        let artA = last?.artwork
        check(artA != nil, "first NetEase cover appears")
        try feed(["title": "Song B", "album": "Album B"])
        check(last?.title == "Song B" && last?.artwork == nil,
              "new song without a cover never inherits the previous song image")
        try feed(["elapsedTime": 1.0, "playing": true])
        check(last?.artwork == nil, "transport diffs cannot resurrect an old cover")
        try feed(["artworkData": b])
        let artB = last?.artwork
        check(last?.title == "Song B" && artB != nil && artB !== artA,
              "a delayed artwork-only diff updates the current NetEase song")
        try feed(["title": "Song C", "artworkData": b])
        check(last?.title == "Song C" && last?.artwork === artB,
              "songs sharing an album can explicitly reuse the same cached image")
        try feed(["title": "Song D"])
        try feed(["title": "Song E"])
        check(last?.artwork == nil, "rapid consecutive song changes stay clear until their own art arrives")
        try await Task.sleep(for: .seconds(2.25))
        check(last?.artworkKnownAbsent == true, "grace timer follows the latest song after rapid skips")
        try feed(["artworkData": a])
        check(last?.title == "Song E" && last?.artwork != nil,
              "cover arriving after the grace period still updates the current song")
        try feed(["bundleIdentifier": "com.apple.Music", "title": "Other player"])
        check(last?.bundleIdentifier == "com.apple.Music" && last?.artwork == nil,
              "switching players cannot retain the previous player cover")
        controller.stop()
        print("All native music artwork checks passed.")
        await ArtworkManagerFixture.runChecks()
    }
}
