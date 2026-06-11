public enum TranslationLanguageCatalog {
    public static let defaultLanguages: [TranslationLanguage] = [
        .autoDetect,
        .english,
        .thai,
        .japanese,
        .korean,
        .simplifiedChinese
    ]

    public static var targetLanguages: [TranslationLanguage] {
        defaultLanguages.filter(\.canBeTargetLanguage)
    }

    public static func language(forID id: String) -> TranslationLanguage? {
        defaultLanguages.first { $0.id == id }
    }
}

public struct LanguageSelection: Equatable, Sendable {
    public var source: TranslationLanguage
    public var target: TranslationLanguage

    public init(
        source: TranslationLanguage = .autoDetect,
        target: TranslationLanguage = .english
    ) {
        self.source = source
        self.target = target.canBeTargetLanguage ? target : .english
    }

    public var canSwap: Bool {
        source.canBeTargetLanguage
    }

    public mutating func swap() {
        guard canSwap else {
            return
        }

        let oldSource = source
        source = target
        target = oldSource
    }
}

public extension AppSettings {
    var languageSelection: LanguageSelection {
        get {
            LanguageSelection(source: sourceLanguage, target: targetLanguage)
        }
        set {
            sourceLanguage = newValue.source
            targetLanguage = newValue.target
        }
    }
}
