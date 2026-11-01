import CoreGraphics

/// AppKit screen coordinates. Keep the trigger independent of the expanded
/// panel and hover probe, whose frames grow while handling a drag.
enum SnapActivationRegion {
    static let topInset: CGFloat = 48
    static let systemEdgeHeight: CGFloat = 12

    static func frame(in screen: CGRect) -> CGRect {
        guard !screen.isEmpty, !screen.isInfinite, !screen.isNull,
              screen.height > topInset else { return .null }
        let width = min(260, screen.width)
        let height = min(48, screen.height - topInset)
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - topInset - height,
                      width: width, height: height)
    }

    static func contains(_ point: CGPoint, in screen: CGRect) -> Bool {
        let region = frame(in: screen)
        guard !region.isNull else { return false }
        return point.x >= region.minX && point.x <= region.maxX
            && point.y >= region.minY && point.y <= region.maxY
    }

    /// Leave the physical top edge to Mission Control across the whole display.
    /// A gap above the activation area avoids toggling at a shared boundary.
    static func isSystemTopEdge(_ point: CGPoint, in screen: CGRect) -> Bool {
        guard !screen.isEmpty, !screen.isInfinite, !screen.isNull else { return false }
        return point.x >= screen.minX && point.x <= screen.maxX
            && point.y >= screen.maxY - systemEdgeHeight && point.y <= screen.maxY
    }
}
