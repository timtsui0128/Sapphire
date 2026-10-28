import AppKit
import Combine
import SwiftUI
@MainActor final class SessionPrivacyState: ObservableObject {
    static let shared = SessionPrivacyState()
    @Published var isSuppressed = false
    static func shouldSuppressUI() -> Bool { shared.isSuppressed }
}
struct TestScreenshot { let id: UUID; let fileURL: URL }
@MainActor final class ScreenshotShelfManager {
    static let shared = ScreenshotShelfManager()
    var items: [TestScreenshot] = []
    func didFinishDrag(ids: Set<UUID>, accepted: Bool) {}
}
enum L10n {
    static func string(_ value: String) -> String { value }
    static func format(_ value: String, _ args: CVarArg...) -> String { String(format: value, arguments: args) }
}
