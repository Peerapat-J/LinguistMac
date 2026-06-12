import Foundation
import LinguistMacCore

enum AppLanguagePreferenceApplier {
    private static let appleLanguagesKey = "AppleLanguages"

    static func apply(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        if let appleLanguages = language.appleLanguages {
            defaults.set(appleLanguages, forKey: appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: appleLanguagesKey)
        }
    }
}
