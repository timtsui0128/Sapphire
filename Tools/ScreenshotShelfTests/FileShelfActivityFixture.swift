import Foundation

// Dependency fixtures for the production checkForFileShelf method. Nested names
// keep all state separate from the user's real shelf and screenshot history.
@MainActor
final class FileShelfActivityFixture {
    enum ActivityType { case fileShelf }
    enum Payload { case fileShelf(count: Int) }
    enum LiveActivityContent { case standard(data: Payload, id: String) }
    final class FileShelfManager {
        static let shared = FileShelfManager()
        var files: [Int] = []
    }
    final class ScreenshotShelfManager {
        static let shared = ScreenshotShelfManager()
        var items: [Int] = []
    }
    struct Settings { var fileShelfLiveActivityEnabled = true }
    final class SettingsModel { var current = Settings() }
    let settingsModel = SettingsModel()
}
