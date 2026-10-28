import AppKit
import SwiftUI

// Only rendering/configuration are replaced; the actual NotchController routing
// method is compiled by run.sh against the real capture manager.
struct ResolvedNotchConfiguration { var expandAnimation: Animation = .default }
@MainActor final class ScreenshotClickFixture {
    enum NotchState { case initial, autoExpanded, hoverExpanded, clickExpanded }
    enum Mode { case musicPlayer, fileShelf, defaultWidgets }
    struct Scratch {
        var collapseTask: DispatchWorkItem?
        var isCollapseTimerActive = true
    }
    struct DragManager { var isDraggingInActivationZone = false }
    struct ShelfState { var selectedItemForPreview: String? = "previous file preview" }
    var isPinned = false
    var isFileDragSessionInProgress = false
    var dragManager = DragManager()
    var scratch = Scratch()
    var expansionAnimation: Animation = .default
    var measuredClickContentSize = CGSize(width: 500, height: 300)
    var fileShelfState = ShelfState()
    var navigationStack: [Mode] = [.musicPlayer]
    var currentMode: Mode { navigationStack.last ?? .defaultWidgets }
    var notchState: NotchState = .autoExpanded
    var cancelledHoverTasks = 0
    func cancelHoverExpandTask() { cancelledHoverTasks += 1 }
}
