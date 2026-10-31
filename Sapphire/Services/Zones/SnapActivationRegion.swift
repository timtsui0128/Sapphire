import CoreGraphics

/// AppKit screen coordinates. Keep the trigger independent of the expanded
/// panel and hover probe, whose frames grow while handling a drag.
enum SnapActivationRegion {
    static func frame(in screen: CGRect) -> CGRect {
        guard !screen.isEmpty, !screen.isInfinite, !screen.isNull else { return .null }
        let width = min(260, screen.width)
        let height = min(48, screen.height)
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height,
                      width: width, height: height)
    }

    static func contains(_ point: CGPoint, in screen: CGRect) -> Bool {
        let region = frame(in: screen)
        guard !region.isNull else { return false }
        // Include the physical top edge, where users naturally park the cursor.
        return point.x >= region.minX && point.x <= region.maxX
            && point.y >= region.minY && point.y <= region.maxY
    }
}
