import Foundation

enum ExpandedPanelLayout {
    static func toolbarOffset(menuBarHeight: CGFloat, panelTopInset: CGFloat,
                              isFloatingIsland: Bool, usesTranslucency: Bool) -> CGFloat {
        guard usesTranslucency, !isFloatingIsland else { return 0 }
        // Keep the entire toolbar below menu titles/status items, on every display.
        return max(0, menuBarHeight - panelTopInset) + 6
    }
}
