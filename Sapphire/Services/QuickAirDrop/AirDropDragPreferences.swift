import Foundation

enum AirDropDragPreferences {
    static let key = "AirDropOpenOnTopDrag"
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
