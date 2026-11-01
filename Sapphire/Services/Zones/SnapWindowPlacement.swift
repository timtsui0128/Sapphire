import Foundation

enum SnapWindowPlacement {
    static func frame(for zone: SnapZone, in visibleFrame: CGRect) -> CGRect? {
        guard [zone.x, zone.y, zone.width, zone.height].allSatisfy(\.isFinite) else { return nil }
        let x = max(0, min(1, zone.x)), y = max(0, min(1, zone.y))
        let width = max(0, min(1 - x, zone.width)), height = max(0, min(1 - y, zone.height))
        guard width > 0, height > 0, visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }
        return CGRect(x: visibleFrame.minX + visibleFrame.width * x,
                      y: visibleFrame.minY + visibleFrame.height * (1 - y - height),
                      width: visibleFrame.width * width, height: visibleFrame.height * height)
    }

    static func axFrame(from frame: CGRect, primaryDisplayMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryDisplayMaxY - frame.maxY, width: frame.width, height: frame.height)
    }

    static func matches(_ actual: CGRect?, _ target: CGRect) -> Bool {
        guard let actual else { return false }
        return abs(actual.minX - target.minX) <= 2 && abs(actual.minY - target.minY) <= 2
            && abs(actual.width - target.width) <= 2 && abs(actual.height - target.height) <= 2
    }

    enum Result: String { case applied, cancelled, permissionDenied, windowUnavailable, notSettable, sizeLimited, failed }
    enum WriteResult { case accepted, busy, denied, unavailable, unsupported, rejected }

    /// An AX success status does not guarantee that the window manager accepted
    /// the frame. Read it back and retry briefly after the app finishes its drag.
    static func apply(
        _ frame: CGRect,
        minimumSize: CGSize? = nil,
        read: () -> CGRect?,
        setSize: (CGSize) -> WriteResult,
        setPosition: (CGPoint) -> WriteResult,
        shouldContinue: () -> Bool,
        pause: (TimeInterval) -> Void
    ) -> Result {
        // Size/position are separate AX transactions. Chromium and some native
        // apps acknowledge a write before committing it. Do not send the next
        // write while the previous one is still animating with stale geometry.
        func writeAndWait(_ write: () -> WriteResult, matchesProperty: (CGRect) -> Bool) -> Result? {
            guard shouldContinue() else { return .cancelled }
            switch write() {
            case .denied: return .permissionDenied
            case .unavailable: return .windowUnavailable
            case .unsupported: return .notSettable
            case .busy, .rejected: return .failed
            case .accepted: break
            }
            for _ in 0..<8 {
                guard shouldContinue() else { return .cancelled }
                if let actual = read(), matchesProperty(actual) { return nil }
                pause(0.04)
            }
            return nil // Still retry the complete frame, including the move.
        }

        for delay in [0.08, 0.16, 0.24] {
            guard shouldContinue() else { return .cancelled }
            if matches(read(), frame) { return .applied }
            // Resizing again after moving also handles crossing to a display
            // where the requested size no longer hits the old screen's limits.
            var retry = false
            for resize in [true, false, true, false] {
                let result = resize
                    ? writeAndWait({ setSize(frame.size) }, matchesProperty: {
                        abs($0.width - frame.width) <= 2 && abs($0.height - frame.height) <= 2
                    })
                    : writeAndWait({ setPosition(frame.origin) }, matchesProperty: {
                        abs($0.minX - frame.minX) <= 2 && abs($0.minY - frame.minY) <= 2
                    })
                if let result {
                    if result != .failed { return result }
                    retry = true
                    break
                }
            }
            // Confirm after the source application's mouse-up transaction,
            // even when a synchronous write initially reports the exact frame.
            var stable = !retry
            for _ in 0..<2 {
                pause(delay / 2)
                guard shouldContinue() else { return .cancelled }
                stable = stable && matches(read(), frame)
            }
            if stable { return .applied }
        }
        if let minimumSize, minimumSize.width.isFinite, minimumSize.height.isFinite,
           minimumSize.width >= 0, minimumSize.height >= 0, let actual = read(),
           (minimumSize.width > frame.width + 2 || minimumSize.height > frame.height + 2),
           (actual.width > frame.width + 2 || actual.height > frame.height + 2) {
            return .sizeLimited
        }
        return .failed
    }
}
