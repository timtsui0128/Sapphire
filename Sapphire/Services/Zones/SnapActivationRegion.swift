import CoreGraphics

/// AppKit screen coordinates. Keep the trigger independent of the expanded
/// panel and hover probe, whose frames grow while handling a drag.
enum SnapActivationRegion {
    static let topInset: CGFloat = 48
    static let systemEdgeHeight: CGFloat = 12

    static func frame(in screen: CGRect, topInset: CGFloat = topInset) -> CGRect {
        guard !screen.isEmpty, !screen.isInfinite, !screen.isNull,
              topInset.isFinite, topInset > systemEdgeHeight,
              screen.height > topInset else { return .null }
        let width = min(320, screen.width)
        let height = min(64, screen.height - topInset)
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - topInset - height,
                      width: width, height: height)
    }

    static func contains(_ point: CGPoint, in screen: CGRect, topInset: CGFloat = topInset) -> Bool {
        let region = frame(in: screen, topInset: topInset)
        guard !region.isNull else { return false }
        return point.x >= region.minX && point.x <= region.maxX
            && point.y >= region.minY && point.y <= region.maxY
    }

    /// Give the real target a visible affordance before the cursor reaches it.
    /// Merely approaching must not start the dwell timer or capture input.
    static func isApproaching(_ point: CGPoint, in screen: CGRect, topInset: CGFloat = topInset) -> Bool {
        let target = frame(in: screen, topInset: topInset)
        guard !target.isNull, !isSystemTopEdge(point, in: screen) else { return false }
        let approach = CGRect(x: target.minX - 120, y: target.minY - 128,
                              width: target.width + 240,
                              height: screen.maxY - systemEdgeHeight - (target.minY - 128))
            .intersection(screen)
        return approach.contains(point)
    }

    static func inset(menuBarHeight: CGFloat, safeAreaTop: CGFloat) -> CGFloat {
        max(32, max(menuBarHeight, safeAreaTop) + 8)
    }

    /// Leave the physical top edge to Mission Control across the whole display.
    /// A gap above the activation area avoids toggling at a shared boundary.
    static func isSystemTopEdge(_ point: CGPoint, in screen: CGRect) -> Bool {
        guard !screen.isEmpty, !screen.isInfinite, !screen.isNull else { return false }
        return point.x >= screen.minX && point.x <= screen.maxX
            && point.y >= screen.maxY - systemEdgeHeight && point.y <= screen.maxY
    }
}
