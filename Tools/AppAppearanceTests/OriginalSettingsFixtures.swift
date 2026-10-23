import AppKit
import SwiftUI

// Only service state is replaced. The render script extracts the actual original
// pages, permission rows, and reusable controls from the application sources.
struct RenderSwipeActions {
    var fileDropLeading: FileDropSwipeAction = .share
    var fileDropTrailing: FileDropSwipeAction = .delete
}

struct RenderSettings {
    var nearbyShareEnabled = true
    var nearbyShareDeviceDisplayName = "My Mac"
    var nearbyShareDownloadLocationPath = "/tmp"
    var nearbyShareOpenOnClick = true
    var swipeActionSettings = RenderSwipeActions()
    var bluetoothNotifyLowBattery = true
    var bluetoothNotifySound = false
    var bluetoothLiveActivityEnabled = true
    var showBluetoothContinuityDevices = false
    var showBluetoothDeviceName = true
}

final class SettingsEditingSession: ObservableObject {
    @Published var settings = RenderSettings()
}

@propertyWrapper
struct EditingSettings: DynamicProperty {
    @EnvironmentObject private var session: SettingsEditingSession
    init() {}
    var wrappedValue: SettingsEditingSession { session }
    var projectedValue: EnvironmentObject<SettingsEditingSession>.Wrapper { $session }
}

enum PermissionType { case files }
enum PermissionStatus { case granted, denied, notRequested }
enum SettingsSection {
    case nearbyShare, bluetooth
    var requiredPermissions: [PermissionType] { [.files] }
}

struct PermissionItem: Identifiable {
    let id = "files"
    let type = PermissionType.files
    let title = "Files and Folders"
    let description = "Access files you choose to share."
    let iconName = "folder.fill"
    let iconColor = Color.blue
}

final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()
    let allPermissions = [PermissionItem()]
    func status(for type: PermissionType) -> PermissionStatus { .notRequested }
    func checkAllPermissions() {}
    func requestPermission(_ type: PermissionType) {}
}

struct PermissionFeatureInfoButton: View {
    let permission: PermissionItem
    var body: some View { Image(systemName: "info.circle").foregroundStyle(.secondary) }
}
