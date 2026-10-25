import AppKit
import SwiftUI
import Vision

@MainActor
private final class Preservation: ObservableObject {
    var identities = Set<UUID>()
    let filename = "Screenshots"
    let selectedIDs = Set([1, 2, 3, 4, 5])
}

@MainActor
private struct LanguageFixture: View {
    @ObservedObject var language: AppLanguageController
    let appearance: AppAppearance
    let preservation: Preservation
    @State private var draft = "General"
    @State private var pinned = true
    @State private var identity = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppLanguageSettingsSection(language: language)
            Text("Screenshots").font(.title2.bold())
            Text(LocalizedStringKey("Keep until I remove"))
            Text("Drag \(preservation.selectedIDs.count) screenshots")
            Toggle("Keep panel open", isOn: $pinned)
            TextField("Notes", text: $draft)
            Text(verbatim: preservation.filename)
            AppAppearanceSettingsSection(appearance: appearance)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .preference(key: StateIdentityKey.self, value: identity)
        .onPreferenceChange(StateIdentityKey.self) { preservation.identities.insert($0) }
        .appLanguage(language)
    }
}

private struct StateIdentityKey: PreferenceKey {
    static let defaultValue = UUID()
    static func reduce(value: inout UUID, nextValue: () -> UUID) { value = nextValue() }
}

private final class TestThumbnailPreferences: ScreenshotThumbnailPreferences {
    var showThumbnail: Bool? = true
    func synchronize() -> Bool { true }
}

@MainActor
@main
enum LanguageChecks {
    static func spin() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }


    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let suiteName = "local.sapphire.language-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let systemLanguagesBefore = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        var system = ["en-GB"]
        let language = AppLanguageController(defaults: defaults, preferredLanguages: { system })
        precondition(language.selection == .system && language.resolvedLanguage == .english)
        for chinese in ["zh-Hans", "zh-Hans-CN", "zh-CN", "zh-Hant-TW"] {
            system = [chinese]
            language.refresh()
            precondition(language.resolvedLanguage == .simplifiedChinese)
        }
        system = ["fr-FR", "zh-Hans"]
        language.refresh()
        precondition(language.resolvedLanguage == .english)
        language.selection = .english
        system = ["zh-Hans"]
        language.refresh()
        precondition(language.resolvedLanguage == .english)
        language.selection = .simplifiedChinese
        precondition(AppLanguageController(defaults: defaults).selection == .simplifiedChinese)
        language.selection = .system
        precondition(language.resolvedLanguage == .simplifiedChinese)
        defaults.set("unsupported", forKey: AppLanguage.defaultsKey)
        precondition(AppLanguageController(defaults: defaults, preferredLanguages: { ["de-DE"] }).resolvedLanguage == .english)
        precondition(UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] == systemLanguagesBefore)
        print("PASS: default/system resolution, explicit overrides, persistence, invalid preference fallback; macOS language untouched")

        precondition(L10n.string("Screenshots", language: .english) == "Screenshots")
        precondition(L10n.string("Screenshots", language: .simplifiedChinese) == "截图")
        precondition(L10n.string("untranslated-user-filename.png", language: .simplifiedChinese) == "untranslated-user-filename.png")
        let template = L10n.string("Could not add %@: %@", language: .simplifiedChinese)
        precondition(String(format: template, "General.png", "example") == "无法添加 General.png：example")
        print("PASS: packaged English/Chinese resources, native lookup, interpolation and verbatim data")

        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain([AppLanguage.defaultsKey: "en"], forName: UserDefaults.argumentDomain)
        SapphireStandardMenu.installIfNeeded()
        let menu = NSApp.mainMenu!
        let editMenu = menu.items.first { $0.submenu?.items.contains(where: { $0.action == Selector("undo:") }) == true }!.submenu!
        let shortcuts = editMenu.items.map(\.keyEquivalent)
        let actions = editMenu.items.map { $0.action.map(NSStringFromSelector) }
        UserDefaults.standard.setVolatileDomain([AppLanguage.defaultsKey: "zh-Hans"], forName: UserDefaults.argumentDomain)
        SapphireStandardMenu.refreshLanguage()
        SapphireStandardMenu.installIfNeeded()
        precondition(NSApp.mainMenu === menu, "Changing menu language replaced the existing menu")
        precondition(editMenu.items.first?.title == "撤销")
        precondition(editMenu.items.map(\.keyEquivalent) == shortcuts)
        precondition(editMenu.items.map { $0.action.map(NSStringFromSelector) } == actions)
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        SapphireStandardMenu.refreshLanguage()
        print("PASS: existing AppKit menus translate without replacing actions, keyboard shortcuts or menu identity")

        language.selection = .english
        let preservation = Preservation()
        let appearanceDefaults = UserDefaults(suiteName: suiteName)!
        let appearance = AppAppearance(defaults: appearanceDefaults)
        appearance.mode = .dark
        let host = NSHostingView(rootView: LanguageFixture(language: language, appearance: appearance, preservation: preservation).appAppearance(appearance))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 1400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.frame = NSRect(x: 0, y: 0, width: 740, height: 1400)
        spin()

        let scenarios: [(AppAppearanceMode, AppLanguage)] = [
            (.dark, .english), (.dark, .simplifiedChinese), (.dark, .english), (.dark, .simplifiedChinese),
            (.light, .english), (.light, .simplifiedChinese)
        ]
        for (mode, choice) in scenarios {
            appearance.mode = mode
            window.appearance = NSAppearance(named: mode == .dark ? .darkAqua : .aqua)
            language.selection = choice
            spin()
            host.layoutSubtreeIfNeeded()
            let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: image)
            let name = "settings-\(choice.rawValue)-\(mode.rawValue)"
            try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image.cgImage!, options: [:]).perform([request])
            let texts = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            try texts.joined(separator: "\n").write(to: output.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
            let expected = choice == .english ? "Screenshots" : "截图"
            precondition(texts.contains(where: { $0.contains(expected) }), "Visible UI did not change: \(texts)")
            // OCR can read the English capital I as a lower-case l; check an
            // unambiguous phrase while keeping the complete Chinese check.
            let retention = choice == .english ? "Keep until" : "保留至手动移除"
            precondition(texts.contains(where: { $0.replacingOccurrences(of: " ", with: "").contains(retention.replacingOccurrences(of: " ", with: "")) }), "Dynamic UI option did not change: \(texts)")
            precondition(texts.contains("General"), "Editing draft was lost or translated")
            precondition(texts.contains("Screenshots"), "User filename was translated")
        }
        precondition(preservation.identities.count == 1, "Language switch discarded SwiftUI state")
        precondition(preservation.selectedIDs.count == 5)
        print("PASS: same native host switches English/Chinese six times in light/dark; draft, filenames and SwiftUI state survive")
        try await checkChineseFolderRecovery()
    }

    static func checkChineseFolderRecovery() async throws {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain([AppLanguage.defaultsKey: "zh-Hans"], forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sapphire-language-folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("initially-missing")
        let suite = "local.sapphire.language-folder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let testArguments: [String: Any] = ["ScreenshotShelfFolderOverride": source.path, "ScreenshotShelfCaptureEnabled": true, AppLanguage.defaultsKey: "zh-Hans"]
        defaults.setVolatileDomain(testArguments, forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(testArguments, forName: UserDefaults.argumentDomain)
        let manager = ScreenshotShelfManager(storageURL: root.appendingPathComponent("owned"), defaults: defaults, thumbnailPreferences: TestThumbnailPreferences())
        manager.startMonitoring()
        defer { manager.stopMonitoring() }
        for _ in 0..<100 where manager.lastError == nil { try await Task.sleep(for: .milliseconds(30)) }
        precondition(manager.lastError?.hasPrefix("无法监测") == true, "Expected the real Chinese folder error; got \(manager.lastError ?? "nil"), language \(UserDefaults.standard.string(forKey: AppLanguage.defaultsKey) ?? "nil"), monitoring \(manager.isMonitoring)")
        precondition(!manager.isMonitoring, "Translated error incorrectly reported the folder as watched")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        manager.retryFailedOperations()
        for _ in 0..<100 where !manager.isMonitoring || manager.lastError != nil { try await Task.sleep(for: .milliseconds(30)) }
        precondition(manager.isMonitoring && manager.lastError == nil, "Chinese folder error did not clear after access recovered")
        print("PASS: real screenshot worker reports a Chinese folder failure and recovers monitoring without matching English text")
    }
}
