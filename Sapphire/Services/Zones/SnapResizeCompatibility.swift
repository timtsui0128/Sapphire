import Foundation

/// Some applications animate individual AX size and position writes when
/// Enhanced UI is enabled. Scope the compatibility change to one placement and
/// always restore the app's prior state, including on cancellation/failure.
enum SnapResizeCompatibility {
    static func perform<Result>(
        assistiveTechnologyActive: Bool,
        readEnhancedUI: () -> Bool?,
        writeEnhancedUI: (Bool) -> Bool,
        operation: (_ enhancedUIWasEnabled: Bool) -> Result
    ) -> Result {
        let wasEnabled = readEnhancedUI() == true
        let changed = wasEnabled && !assistiveTechnologyActive && writeEnhancedUI(false)
        defer { if changed { _ = writeEnhancedUI(true) } }
        return operation(wasEnabled)
    }
}
