import AppKit
import Foundation

// Render-free fixture; all image routing/loading methods come from MusicManager.
@MainActor final class ArtworkManagerFixture {
    var artwork: NSImage?
    var artworkURL: URL?
    var loadingArtworkURL: URL?
    var loadingArtworkTrackToken: String?
    var loadingArtworkRequestID: UUID?
    var remoteArtworkTask: Task<Void, Never>?
    var displayedRemoteArtwork: (url: URL, image: NSImage)?
    var artworkTrackToken: String?
    var currentTrackArtworkToken = ""
    var lastTrackIdentity: String?
    var isSpotifySourceSelected = false
    var isPhoneMediaSourceSelected = false
    func refreshArtworkColorExtractionIfNeeded() {}

    func changeTrack(_ token: String) {
        clearArtwork()
        currentTrackArtworkToken = token
        lastTrackIdentity = token
    }

    static func runChecks() async {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { print("FAIL: \(message)"); exit(1) }
            print("PASS: \(message)")
        }
        let manager = ArtworkManagerFixture()
        let coverA = NSImage(size: NSSize(width: 4, height: 4))
        let coverB = NSImage(size: NSSize(width: 8, height: 8))
        manager.changeTrack("A")
        manager.applyArtwork(coverA, trackIdentity: "A")
        manager.changeTrack("B")
        check(manager.artwork == nil, "displayed artwork clears immediately at a track boundary")
        manager.applyArtwork(coverA, trackIdentity: "A")
        check(manager.artwork == nil, "late native artwork with an old identity is rejected")
        manager.applyArtwork(coverB, trackIdentity: "B")
        check(manager.artwork === coverB, "current native cover appears without another track change")

        let cache = FileImageCache.shared
        let urlA = URL(string: "https://artwork.invalid/a")!
        let urlB = URL(string: "https://artwork.invalid/b")!
        func waitForRequests(_ count: Int) async {
            for _ in 0..<100 where cache.requests.count < count { await Task.yield() }
            check(cache.requests.count == count, "artwork request \(count) starts")
        }
        manager.changeTrack("A")
        manager.showRemoteArtwork(urlA)
        let oldA = manager.remoteArtworkTask!
        await waitForRequests(1)
        manager.changeTrack("B")
        manager.showRemoteArtwork(urlB)
        let oldB = manager.remoteArtworkTask!
        await waitForRequests(2)
        manager.changeTrack("A")
        manager.showRemoteArtwork(urlA)
        let latestA = manager.remoteArtworkTask!
        await waitForRequests(3)
        cache.complete(2, with: coverA)
        await latestA.value
        check(manager.artwork === coverA && manager.currentTrackArtworkToken == "A",
              "a current request preserves the song identity instead of replacing it with a URL")
        cache.complete(1, with: coverB)
        await oldB.value
        check(manager.artwork === coverA, "out-of-order request from a previous song cannot overwrite the current cover")
        cache.complete(0, with: coverB)
        await oldA.value
        check(manager.artwork === coverA, "returning to the same song and URL still rejects its earlier cancelled request")
        manager.showRemoteArtwork(urlA)
        check(cache.requests.count == 3 && manager.artwork === coverA,
              "unchanged artwork uses the displayed image without another download")
        manager.changeTrack("Shared Album")
        manager.showRemoteArtwork(urlA)
        let sharedAlbum = manager.remoteArtworkTask!
        await waitForRequests(4)
        manager.showRemoteArtwork(urlA)
        check(cache.requests.count == 4, "the same current-track download is coalesced")
        cache.complete(3, with: coverA)
        await sharedAlbum.value
        check(manager.artwork === coverA && manager.artworkTrackToken == "Shared Album",
              "a cached album cover can be assigned to a different song")
        print("All music artwork checks passed.")
    }
}

// Deliberately completes cancelled downloads to reproduce a slow network race.
@MainActor final class FileImageCache {
    static let shared = FileImageCache()
    var requests: [CheckedContinuation<NSImage?, Never>] = []
    func image(for url: URL) async -> NSImage? {
        await withCheckedContinuation { requests.append($0) }
    }
    func complete(_ index: Int, with image: NSImage) { requests[index].resume(returning: image) }
}
