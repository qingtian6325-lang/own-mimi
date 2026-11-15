import Foundation
import SwiftUI

/// In-app UI language. Does **not** change SpringBoard / home-screen name
/// (`CFBundleDisplayName` stays system-locale via InfoPlist.strings only).
/// Never writes `AppleLanguages` — icon name must not follow the in-app picker.
public enum AppLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case chinese
    case english

    public var id: String { rawValue }

    /// Settings row label (always bilingual so the picker is readable in either language).
    public var settingsLabel: String {
        switch self {
        case .system: return "跟随系统 / Follow System"
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    public var settingsLabelLocalized: String {
        switch self {
        case .system: return MimiL10n.string("跟随系统")
        case .chinese: return MimiL10n.string("中文")
        case .english: return "English"
        }
    }
}

@MainActor
public final class AppLanguageStore: ObservableObject {
    public static let shared = AppLanguageStore()

    public nonisolated static let storageKey = "mimi_app_language_preference"

    private let defaults: UserDefaults

    @Published public var preference: AppLanguagePreference {
        didSet {
            guard oldValue != preference else { return }
            defaults.set(preference.rawValue, forKey: Self.storageKey)
            objectWillChange.send()
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.storageKey),
           let pref = AppLanguagePreference(rawValue: raw) {
            preference = pref
        } else {
            preference = .system
        }
    }

    /// Locale used for in-app String Catalog lookups and SwiftUI `.environment(\.locale)`.
    public var effectiveLocale: Locale {
        switch preference {
        case .system:
            return Locale.autoupdatingCurrent
        case .chinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }

    /// BCP-47 code used when resolving `.lproj` / catalog language explicitly.
    public var effectiveLanguageCode: String {
        switch preference {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
            if preferred.hasPrefix("zh") { return "zh-Hans" }
            if preferred.hasPrefix("en") { return "en" }
            return preferred
        case .chinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }

    /// In-app product name (catalog: zh-Hans「咪咪记账」, en「Mimi Money»).
    public var productDisplayName: String {
        MimiL10n.string("咪咪记账")
    }
}

/// String Catalog lookups for `MimiMoneyCore` (SPM module bundle).
public enum MimiL10n {
    /// Resolve a UI string for the current in-app language preference.
    public static func string(_ key: String, locale: Locale? = nil) -> String {
        let resolvedLocale = locale ?? resolvedLocaleForLookup()
        return String(
            localized: String.LocalizationValue(key),
            bundle: .mimiModule,
            locale: resolvedLocale
        )
    }

    public static func string(_ key: String.LocalizationValue, locale: Locale? = nil) -> String {
        let resolvedLocale = locale ?? resolvedLocaleForLookup()
        return String(localized: key, bundle: .mimiModule, locale: resolvedLocale)
    }

    /// Read preference from UserDefaults so lookups work off the main actor too.
    private static func resolvedLocaleForLookup() -> Locale {
        let raw = UserDefaults.standard.string(forKey: AppLanguageStore.storageKey)
            ?? AppLanguagePreference.system.rawValue
        switch AppLanguagePreference(rawValue: raw) ?? .system {
        case .system:
            return Locale.autoupdatingCurrent
        case .chinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }
}

public extension Text {
    /// Localized `Text` from the MimiMoneyCore String Catalog (respects `.environment(\.locale)`).
    static func mimi(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .mimiModule)
    }
}
