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

    enum Result { case applied, cancelled, failed }

    /// An AX success status does not guarantee that the window manager accepted
    /// the frame. Read it back and retry briefly after the app finishes its drag.
    static func apply(
        _ frame: CGRect,
        read: () -> CGRect?,
        setSize: (CGSize) -> Void,
        setPosition: (CGPoint) -> Void,
        shouldContinue: () -> Bool,
        pause: (TimeInterval) -> Void
    ) -> Result {
        for delay in [0.06, 0.12, 0.20] {
            guard shouldContinue() else { return .cancelled }
            if matches(read(), frame) { return .applied }
            setSize(frame.size)
            setPosition(frame.origin)
            setSize(frame.size)
            setPosition(frame.origin)
            pause(delay)
            guard shouldContinue() else { return .cancelled }
            if matches(read(), frame) { return .applied }
        }
        return .failed
    }
}
