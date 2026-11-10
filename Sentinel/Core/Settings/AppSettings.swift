import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }
    var displayName: String { self == .spanish ? "Español" : "English" }
}

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var theme: AppThemeMode {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Keys.language) ?? "es") ?? .spanish
        theme = AppThemeMode(rawValue: UserDefaults.standard.string(forKey: Keys.theme) ?? "system") ?? .system
    }

    private enum Keys {
        static let language = "sentinel.language"
        static let theme = "sentinel.theme"
    }
}
