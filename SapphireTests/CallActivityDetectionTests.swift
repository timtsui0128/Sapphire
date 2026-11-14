import XCTest
@testable import Sapphire

final class CallActivityDetectionTests: XCTestCase {
    func testWhatsAppStatusRequiresMatchingAudioInput() {
        let app = AppActivityApp.whatsApp
        XCTAssertTrue(app.hasActiveMicrophone(["net.whatsapp.WhatsApp"]))
        XCTAssertTrue(app.hasActiveMicrophone(["net.whatsapp.WhatsApp.AudioHelper"]))
        XCTAssertTrue(app.hasActiveMicrophone(["desktop.WhatsApp.helper"]))
        XCTAssertFalse(app.hasActiveMicrophone([]))
        XCTAssertFalse(app.hasActiveMicrophone(["net.whatsapp.WhatsAppFake", "com.apple.FaceTime"]))
        XCTAssertFalse(app.hasActiveMicrophone(["desktop.WhatsApp.helper"], forBundleID: "net.whatsapp.WhatsApp"))
        XCTAssertEqual(app.controls, [.show])
    }

    func testFaceTimeUsesSystemCallOnlyWhenAttributed() {
        let faceTime = "com.apple.FaceTime", phone = "com.apple.mobilephone"
        let audio: Set<String> = ["com.apple.avconferenced"]
        XCTAssertTrue(CallAudioAttribution.faceTimeHasSystemInput(inputs: audio, frontmostBundleID: "com.apple.finder", isRunning: { $0 == faceTime }))
        XCTAssertTrue(CallAudioAttribution.faceTimeHasSystemInput(inputs: audio, frontmostBundleID: faceTime, isRunning: { _ in true }))
        XCTAssertFalse(CallAudioAttribution.faceTimeHasSystemInput(inputs: audio, frontmostBundleID: phone, isRunning: { _ in true }))
        XCTAssertFalse(CallAudioAttribution.faceTimeHasSystemInput(inputs: audio, frontmostBundleID: "com.apple.finder", isRunning: { _ in true }))
        XCTAssertFalse(CallAudioAttribution.faceTimeHasSystemInput(inputs: audio, frontmostBundleID: nil, isRunning: { _ in false }))
        XCTAssertFalse(CallAudioAttribution.faceTimeHasSystemInput(inputs: [], frontmostBundleID: faceTime, isRunning: { _ in true }))
    }

    func testSystemCallStillRequiresRealInputDevice() {
        func counts(_ device: String) -> Bool {
            MicrophoneUsageFilter.shouldCount(processID: 200, bundleID: "com.apple.avconferenced",
                                             inputDeviceNames: [device], ownProcessID: 100, ownBundleID: "com.cshariq.sapphire")
        }
        XCTAssertTrue(counts("AirPods Microphone"))
        XCTAssertFalse(counts("Sapphire-com.apple.FaceTime"))
    }
}
