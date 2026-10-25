import AppKit
import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultsKey = "SapphireAppLanguage"
    var id: String { rawValue }

    func resolved(preferredLanguages: [String]) -> AppLanguage {
        guard self == .system else { return self }
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true
            ? .simplifiedChinese : .english
    }
}

extension Notification.Name {
    static let sapphireLanguageDidChange = Notification.Name("SapphireLanguageDidChange")
}

/// Explicit bundle lookup for AppKit and other non-SwiftUI strings. Never changes
/// AppleLanguages, system preferences, persisted enum values, or user content.
enum L10n {
    static var locale: Locale {
        let choice = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        return Locale(identifier: choice.resolved(preferredLanguages: Locale.preferredLanguages).rawValue)
    }

    static func bundle(for language: AppLanguage, in resources: Bundle = .main) -> Bundle {
        let resolved = language.resolved(preferredLanguages: Locale.preferredLanguages)
        guard let path = resources.path(forResource: resolved.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return resources }
        return bundle
    }

    static func string(_ key: String, language: AppLanguage? = nil, resources: Bundle = .main) -> String {
        let choice = language ?? UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        return bundle(for: choice, in: resources).localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let choice = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        let language = choice.resolved(preferredLanguages: Locale.preferredLanguages)
        return String(format: string(key, language: language), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}

@MainActor
final class AppLanguageController: ObservableObject {
    static let shared = AppLanguageController()

    @Published var selection: AppLanguage {
        didSet {
            guard oldValue != selection else { return }
            defaults.set(selection.rawValue, forKey: AppLanguage.defaultsKey)
            refresh()
        }
    }
    @Published private(set) var resolvedLanguage: AppLanguage
    var locale: Locale { Locale(identifier: resolvedLanguage.rawValue) }

    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    private var observers = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard, preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        let choice = defaults.string(forKey: AppLanguage.defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        selection = choice
        resolvedLanguage = choice.resolved(preferredLanguages: preferredLanguages())
        Publishers.Merge(
            NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refresh() }
        .store(in: &observers)
    }

    func refresh() {
        let language = selection.resolved(preferredLanguages: preferredLanguages())
        guard resolvedLanguage != language else { return }
        resolvedLanguage = language
        NotificationCenter.default.post(name: .sapphireLanguageDidChange, object: self)
    }
}

private struct AppLanguageModifier: ViewModifier {
    @ObservedObject var language: AppLanguageController

    func body(content: Content) -> some View {
        content.environment(\.locale, language.locale)
    }
}

extension View {
    @MainActor
    func appLanguage(_ language: AppLanguageController? = nil) -> some View {
        modifier(AppLanguageModifier(language: language ?? .shared))
    }
}

@MainActor
struct AppLanguageSettingsSection: View {
    @ObservedObject private var language: AppLanguageController

    init(language: AppLanguageController? = nil) {
        _language = ObservedObject(wrappedValue: language ?? .shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Language").font(.headline)
            Picker("App language", selection: $language.selection) {
                Text("Follow System").tag(AppLanguage.system)
                Text(verbatim: "English").tag(AppLanguage.english)
                Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
            }
            .pickerStyle(.menu)
            Text("Changes apply immediately. Follow System uses Simplified Chinese for Chinese system languages and English for other languages.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .appLanguage(language)
    }
}
