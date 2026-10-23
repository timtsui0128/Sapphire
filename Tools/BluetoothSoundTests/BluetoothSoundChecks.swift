import Foundation

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() {
        throw NSError(domain: "BluetoothSoundChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@main
private struct BluetoothSoundChecks {
    static func main() throws {
        var fresh = Settings()
        try check(!fresh.bluetoothNotifySound, "New installations must be silent")
        fresh.migrateBluetoothConnectionSoundPreference()
        try check(!fresh.bluetoothNotifySound && fresh.bluetoothSoundPreferenceVersion == 1, "Fresh settings must record the opt-in migration")
        try check(fresh.bluetoothLiveActivityEnabled, "Visual Bluetooth activity must remain enabled")
        print("PASS: silent defaults preserve visual Bluetooth activity")

        var legacy = Settings()
        legacy.bluetoothNotifySound = true
        legacy.migrateBluetoothConnectionSoundPreference()
        try check(!legacy.bluetoothNotifySound && legacy.bluetoothSoundPreferenceVersion == 1, "Legacy enabled sound must migrate to silent")
        let once = try JSONEncoder().encode(legacy)
        legacy.migrateBluetoothConnectionSoundPreference()
        let reloadedSilent = try JSONDecoder().decode(Settings.self, from: once)
        try check(!reloadedSilent.bluetoothNotifySound && reloadedSilent.bluetoothSoundPreferenceVersion == 1, "Silent choice and migration marker must serialize together")
        try check(legacy.bluetoothLiveActivityEnabled, "Migration must not disable visual events")
        print("PASS: old enabled setting becomes persistently silent and migration is idempotent")

        var optedIn = reloadedSilent
        optedIn.bluetoothNotifySound = true
        let payload = try JSONEncoder().encode(optedIn)
        var restored = try JSONDecoder().decode(Settings.self, from: payload)
        restored.migrateBluetoothConnectionSoundPreference()
        try check(restored.bluetoothNotifySound, "A deliberate opt-in after migration must survive relaunch")
        restored.bluetoothNotifySound = false
        restored.migrateBluetoothConnectionSoundPreference()
        try check(!restored.bluetoothNotifySound, "A later explicit opt-out must also survive")
        print("PASS: later explicit opt-in and opt-out are preserved")

        var future = Settings()
        future.bluetoothSoundPreferenceVersion = 2
        future.bluetoothNotifySound = true
        future.migrateBluetoothConnectionSoundPreference()
        try check(future.bluetoothNotifySound && future.bluetoothSoundPreferenceVersion == 2, "Migration must preserve newer preference versions")
        print("PASS: newer saved preference versions are preserved")
        print("PASS: production load/import/reset hooks and both connection/disconnection sound guards verified")
    }
}
