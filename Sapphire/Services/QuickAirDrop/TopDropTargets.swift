import Foundation

enum DropZone: Hashable {
    case shelf
    case airdrop
    case clipboard
    case device(String)
}

enum TopDropTargets {
    static let quickActions: [DropZone] = [.airdrop, .clipboard]

    // A gap, the menu bar or an unmeasured panel is not an action. Use the same
    // bounds for hover and release so the highlighted target matches the result.
    static func destination(at point: CGPoint?, frames: [DropZone: CGRect]) -> DropZone? {
        guard let point else { return nil }
        return quickActions.first { frames[$0]?.contains(point) == true }
    }
}
