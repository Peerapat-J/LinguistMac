public extension LanguagePackReadiness {
    var displayText: String {
        switch self {
        case .unknown:
            "Checking"
        case .ready:
            "Ready"
        case .needsDownload:
            "Needs Download"
        case .unavailable:
            "Unsupported"
        }
    }
}

public struct AppleLanguagePackPair: Identifiable, Equatable, Hashable, Sendable {
    public let sourceLanguage: TranslationLanguage
    public let targetLanguage: TranslationLanguage

    public var id: String {
        "\(sourceLanguage.id)->\(targetLanguage.id)"
    }

    public var displayName: String {
        "\(sourceLanguage.displayName) -> \(targetLanguage.displayName)"
    }

    public init(
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }

    public static func current(settings: AppSettings) -> AppleLanguagePackPair? {
        guard !settings.sourceLanguage.supportsAutoDetect,
              settings.targetLanguage.canBeTargetLanguage,
              settings.sourceLanguage != settings.targetLanguage
        else {
            return nil
        }

        return AppleLanguagePackPair(
            sourceLanguage: settings.sourceLanguage,
            targetLanguage: settings.targetLanguage
        )
    }
}

public struct AppleLanguagePackSelection: Equatable, Sendable {
    public let pair: AppleLanguagePackPair?
    public let readiness: LanguagePackReadiness
    public let isPreparing: Bool
    public let message: String?

    public var canPrepare: Bool {
        pair != nil && readiness == .needsDownload && !isPreparing
    }

    public init(
        pair: AppleLanguagePackPair?,
        readiness: LanguagePackReadiness,
        isPreparing: Bool = false,
        message: String? = nil
    ) {
        self.pair = pair
        self.readiness = readiness
        self.isPreparing = isPreparing
        self.message = message
    }

    public static func initial(settings: AppSettings) -> AppleLanguagePackSelection {
        AppleLanguagePackSelection(
            pair: AppleLanguagePackPair.current(settings: settings),
            readiness: .unknown
        )
    }
}

public struct AppleLanguagePackReadinessRow: Identifiable, Equatable, Sendable {
    public let pair: AppleLanguagePackPair
    public let readiness: LanguagePackReadiness
    public let isCurrentPair: Bool
    public let isPreparing: Bool
    public let message: String?

    public var id: String {
        pair.id
    }

    public var canPrepare: Bool {
        readiness == .needsDownload && !isPreparing
    }

    public init(
        pair: AppleLanguagePackPair,
        readiness: LanguagePackReadiness,
        isCurrentPair: Bool,
        isPreparing: Bool = false,
        message: String? = nil
    ) {
        self.pair = pair
        self.readiness = readiness
        self.isCurrentPair = isCurrentPair
        self.isPreparing = isPreparing
        self.message = message
    }
}

public struct AppleLanguagePackGroup: Identifiable, Equatable, Sendable {
    public let language: TranslationLanguage
    public let rows: [AppleLanguagePackReadinessRow]

    public var id: String {
        language.id
    }

    public init(
        language: TranslationLanguage,
        rows: [AppleLanguagePackReadinessRow]
    ) {
        self.language = language
        self.rows = rows
    }
}

public enum AppleLanguagePackCatalog {
    public static func supportedLanguages(from languages: [TranslationLanguage]) -> [TranslationLanguage] {
        languages.filter { !$0.supportsAutoDetect }
    }

    public static func groups(
        from languages: [TranslationLanguage],
        settings: AppSettings
    ) -> [AppleLanguagePackGroup] {
        let supportedLanguages = supportedLanguages(from: languages)
        let currentPair = AppleLanguagePackPair.current(settings: settings)
        return supportedLanguages.map { language in
            AppleLanguagePackGroup(
                language: language,
                rows: groupRows(
                    for: language,
                    supportedLanguages: supportedLanguages,
                    currentPair: currentPair
                )
            )
        }
    }

    private static func groupRows(
        for language: TranslationLanguage,
        supportedLanguages: [TranslationLanguage],
        currentPair: AppleLanguagePackPair?
    ) -> [AppleLanguagePackReadinessRow] {
        var pairs = supportedLanguages
            .filter { $0 != language }
            .flatMap { otherLanguage in
                [
                    AppleLanguagePackPair(sourceLanguage: language, targetLanguage: otherLanguage),
                    AppleLanguagePackPair(sourceLanguage: otherLanguage, targetLanguage: language)
                ]
            }

        if let currentPair {
            if let currentPairIndex = pairs.firstIndex(of: currentPair) {
                pairs.remove(at: currentPairIndex)
                pairs.insert(currentPair, at: 0)
            }
        }

        return pairs.map { pair in
            AppleLanguagePackReadinessRow(
                pair: pair,
                readiness: .unknown,
                isCurrentPair: pair == currentPair
            )
        }
    }
}
