import AppKit
import Combine
import Sparkle

@MainActor
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private var checker: UpdateChecker!
    private var observation: AnyCancellable?
    private var handledOffer = false
    private var handledReady = false
    private var mode: String { Bundle.main.object(forInfoDictionaryKey: "TestMode") as! String }
    private var result: URL { URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "TestResult") as! String) }

    private func record(_ state: String, _ message: String = "") {
        let info: [String: String] = ["state": state, "message": message,
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String]
        try! JSONSerialization.data(withJSONObject: info).write(to: result, options: .atomic)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            if mode == "rename" {
                precondition(UserDefaults.standard.string(forKey: "TopLetRenameFixture") == "keep-existing-selection")
            }
            record("relaunched")
            NSApp.terminate(nil)
            return
        }
        if mode == "rename" {
            UserDefaults.standard.set("keep-existing-selection", forKey: "TopLetRenameFixture")
            UserDefaults.standard.synchronize()
        }
        checkPolicyAndCallbacks()
        let feed = URL(string: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as! String)!
        checker = UpdateChecker(feedURL: feed, archivePolicy: { $0.host == "127.0.0.1" })
        observation = checker.$status.sink { [weak self] status in
            // Published emits before the assignment; invoke controls on the next main turn.
            DispatchQueue.main.async { self?.handle(status) }
        }
        checker.startPeriodicChecks(interval: 18000)
        if mode == "automatic" { checker.setAutomaticDownloadsEnabled(true) }
        checker.checkForUpdates()
        DispatchQueue.main.asyncAfter(deadline: .now() + 55) { [weak self] in
            self?.record("timeout")
            NSApp.terminate(nil)
        }
    }

    private func handle(_ status: UpdateStatus) {
        switch status {
        case .available(_, let asset) where !handledOffer:
            handledOffer = true
            record("offered")
            if mode != "automatic" { checker.downloadUpdate(asset: asset) }
        case .readyToInstall where !handledReady:
            handledReady = true
            record("ready")
            if mode == "cancel" || mode == "lock" {
                if mode == "lock" { SessionPrivacyState.shared.isSuppressed = true }
                else { checker.cancelDownload() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.record("cancelled")
                    NSApp.terminate(nil)
                }
            } else if mode == "quit" {
                checker.stopPeriodicChecks()
                NSApp.terminate(nil)
            } else {
                checker.installAndRelaunch()
            }
        case .error(let message):
            record("rejected", message)
            NSApp.terminate(nil)
        default: break
        }
    }

    private func checkPolicyAndCallbacks() {
        assert(PersonalUpdateChannel.allowsArchive(URL(string: "https://github.com/timtsui0128/Sapphire/releases/download/personal-v0.2.0/Sapphire.zip")!))
        assert(PersonalUpdateChannel.allowsArchive(URL(string: "https://github.com/timtsui0128/Sapphire/releases/download/personal-v0.1.8/TopLet-0.1.8-arm64.zip")!))
        assert(PersonalUpdateChannel.allowsArchive(URL(string: "https://github.com/timtsui0128/Sapphire/releases/download/personal-v0.1.8/TopLet18-17.delta")!))
        assert(PersonalUpdateChannel.allowsArchive(URL(string: "https://github.com/timtsui0128/Sapphire/releases/download/personal-v0.2.0/Sapphire13-12.delta")!))
        for value in ["https://github.com/cshariq/Sapphire/releases/download/personal-v0.2.0/Sapphire.zip",
                      "https://github.com/timtsui0128/Other/releases/download/personal-v0.2.0/Sapphire.zip",
                      "http://github.com/timtsui0128/Sapphire/releases/download/personal-v0.2.0/Sapphire.zip",
                      "https://github.com.evil.example/timtsui0128/Sapphire/releases/download/personal-v0.2.0/Sapphire.zip",
                      "https://user@github.com/timtsui0128/Sapphire/releases/download/personal-v0.2.0/Sapphire.zip"] {
            assert(!PersonalUpdateChannel.allowsArchive(URL(string: value)!))
        }
        let driver = UpdateChecker()
        var readyCalls = 0
        driver.showReady(toInstallAndRelaunch: { choice in assert(choice == .skip); readyCalls += 1 })
        driver.stopPeriodicChecks()
        assert(readyCalls == 0, "Quitting must not discard a prepared update")
        SessionPrivacyState.shared.isSuppressed = true
        assert(readyCalls == 1)
        driver.cancelDownload()
        assert(readyCalls == 1, "Do not invoke Sparkle replies twice")
        SessionPrivacyState.shared.isSuppressed = false
        var cancellations = 0
        driver.showDownloadInitiated { cancellations += 1 }
        driver.showDownloadDidReceiveExpectedContentLength(10)
        driver.showDownloadDidReceiveData(ofLength: 20)
        assert(driver.status == .downloading(progress: 1))
        assert(driver.downloadDetail != nil, "The UI should show actual byte progress")
        driver.cancelDownload()
        driver.cancelDownload()
        assert(cancellations == 1)
        driver.showDownloadDidStartExtractingUpdate()
        assert(driver.isExtracting)
        driver.dismissUpdateInstallation()
        assert(!driver.isExtracting)
    }
}

@main
struct UpdateHarness {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = HarnessDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
