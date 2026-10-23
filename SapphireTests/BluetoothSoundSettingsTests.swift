import Foundation
import Testing
@testable import Sapphire

@Suite("Bluetooth sound opt-in migration")
struct BluetoothSoundSettingsTests {
    @Test func newSettingsAreSilentAndVisualActivityRemainsEnabled() {
        let settings = Settings()
        #expect(!settings.bluetoothNotifySound)
        #expect(settings.bluetoothLiveActivityEnabled)
    }

    @Test func oldEnabledPayloadMigratesToSilent() throws {
        var dictionary = try #require(SettingsPersistence.encodeToDictionary(Settings()))
        dictionary.removeValue(forKey: "bluetoothSoundPreferenceVersion")
        dictionary["bluetoothNotifySound"] = true
        let payload = try JSONSerialization.data(withJSONObject: dictionary)
        let settings = try #require(SettingsPersistence.decodeFromPayload(payload))
        #expect(!settings.bluetoothNotifySound)
        #expect(settings.bluetoothSoundPreferenceVersion == 1)
        #expect(settings.bluetoothLiveActivityEnabled)
    }

    @Test func laterExplicitOptInSurvivesPayloadReload() throws {
        var settings = Settings()
        settings.normalizeCollectionOrders()
        settings.bluetoothNotifySound = true
        let payload = try SettingsPersistence.encoder.encode(settings)
        let restored = try #require(SettingsPersistence.decodeFromPayload(payload))
        #expect(restored.bluetoothNotifySound)
        #expect(restored.bluetoothSoundPreferenceVersion == 1)
    }
}
