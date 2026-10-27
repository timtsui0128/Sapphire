// Hidden test hosts do not show user-facing error alerts.
import AppKit
@MainActor enum HelperAlertPresenter {
    static func presentModal(messageText: String, informativeText: String, alertStyle: NSAlert.Style,
                             buttonTitles: [String], completion: @escaping (Int) -> Void) { completion(0) }
}
