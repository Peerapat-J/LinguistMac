public enum TranslationLanguageCatalog {
    public static let defaultLanguages: [TranslationLanguage] = [
        .autoDetect,
        .arabic,
        .dutch,
        .english,
        .french,
        .german,
        .hindi,
        .indonesian,
        .italian,
        .japanese,
        .korean,
        .simplifiedChinese,
        .traditionalChinese,
        .polish,
        .brazilianPortuguese,
        .russian,
        .spanish,
        .thai,
        .turkish,
        .ukrainian,
        .vietnamese
    ]

    public static var targetLanguages: [TranslationLanguage] {
        defaultLanguages.filter(\.canBeTargetLanguage)
    }

    public static func language(forID id: String) -> TranslationLanguage? {
        defaultLanguages.first { $0.id == id } ?? languageAliases[id.lowercased()]
    }

    private static let languageAliases: [String: TranslationLanguage] = [
        "de-de": .german,
        "en-gb": .english,
        "en-us": .english,
        "es-es": .spanish,
        "fr-fr": .french,
        "it-it": .italian,
        "nl-nl": .dutch,
        "pt": .brazilianPortuguese,
        "ru-ru": .russian,
        "zh": .simplifiedChinese,
        "zh-cn": .simplifiedChinese,
        "zh-hans-cn": .simplifiedChinese,
        "zh-hant-tw": .traditionalChinese,
        "zh-tw": .traditionalChinese
    ]
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
