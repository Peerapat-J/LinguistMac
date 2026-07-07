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

    public var reversed: AppleLanguagePackPair {
        AppleLanguagePackPair(sourceLanguage: targetLanguage, targetLanguage: sourceLanguage)
    }

    public var bidirectionalPairs: [AppleLanguagePackPair] {
        sourceLanguage == targetLanguage ? [self] : [self, reversed]
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
    public let language: TranslationLanguage
    public let pairedLanguage: TranslationLanguage
    public let pairs: [AppleLanguagePackPair]
    public let readinessByPairID: [String: LanguagePackReadiness]
    public let isCurrentPair: Bool
    public let isPreparing: Bool
    public let message: String?

    public var pair: AppleLanguagePackPair {
        pairs.first ?? AppleLanguagePackPair(sourceLanguage: language, targetLanguage: pairedLanguage)
    }

    public var id: String {
        "\(language.id)<->\(pairedLanguage.id)"
    }

    public var displayName: String {
        "\(language.displayName) ↔ \(pairedLanguage.displayName)"
    }

    public var readiness: LanguagePackReadiness {
        Self.combinedReadiness(Array(readinessByPairID.values))
    }

    public var canPrepare: Bool {
        readiness == .needsDownload && !isPreparing
    }

    public init(
        language: TranslationLanguage,
        pairedLanguage: TranslationLanguage,
        pairs: [AppleLanguagePackPair],
        readiness: LanguagePackReadiness,
        readinessByPairID: [String: LanguagePackReadiness]? = nil,
        isCurrentPair: Bool,
        isPreparing: Bool = false,
        message: String? = nil
    ) {
        self.language = language
        self.pairedLanguage = pairedLanguage
        self.pairs = pairs
        self.readinessByPairID = readinessByPairID ?? Dictionary(
            uniqueKeysWithValues: pairs.map { ($0.id, readiness) }
        )
        self.isCurrentPair = isCurrentPair
        self.isPreparing = isPreparing
        self.message = message
    }

    public init(
        pair: AppleLanguagePackPair,
        readiness: LanguagePackReadiness,
        isCurrentPair: Bool,
        isPreparing: Bool = false,
        message: String? = nil
    ) {
        self.init(
            language: pair.sourceLanguage,
            pairedLanguage: pair.targetLanguage,
            pairs: [pair],
            readiness: readiness,
            isCurrentPair: isCurrentPair,
            isPreparing: isPreparing,
            message: message
        )
    }

    private static func combinedReadiness(_ readineses: [LanguagePackReadiness]) -> LanguagePackReadiness {
        guard !readineses.isEmpty else {
            return .unknown
        }
        if readineses.contains(.unavailable) {
            return .unavailable
        }
        if readineses.contains(.needsDownload) {
            return .needsDownload
        }
        if readineses.contains(.unknown) {
            return .unknown
        }
        return .ready
    }
}

public struct AppleLanguagePackGroup: Identifiable, Equatable, Sendable {
    public let language: TranslationLanguage
    public let rows: [AppleLanguagePackReadinessRow]
    public let isPinned: Bool

    public var id: String {
        language.id
    }

    public init(
        language: TranslationLanguage,
        rows: [AppleLanguagePackReadinessRow],
        isPinned: Bool = false
    ) {
        self.language = language
        self.rows = rows
        self.isPinned = isPinned
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
        let groups = supportedLanguages.map { language in
            AppleLanguagePackGroup(
                language: language,
                rows: groupRows(
                    for: language,
                    supportedLanguages: supportedLanguages,
                    currentPair: currentPair
                ),
                isPinned: settings.pinnedAppleLanguagePackLanguageIDs.contains(language.id)
            )
        }
        return orderedGroups(
            groups,
            pinnedLanguageIDs: settings.pinnedAppleLanguagePackLanguageIDs
        )
    }

    private static func groupRows(
        for language: TranslationLanguage,
        supportedLanguages: [TranslationLanguage],
        currentPair: AppleLanguagePackPair?
    ) -> [AppleLanguagePackReadinessRow] {
        var rows = supportedLanguages
            .filter { $0 != language }
            .map { otherLanguage in
                let pairs = [
                    AppleLanguagePackPair(sourceLanguage: language, targetLanguage: otherLanguage),
                    AppleLanguagePackPair(sourceLanguage: otherLanguage, targetLanguage: language)
                ]
                return AppleLanguagePackReadinessRow(
                    language: language,
                    pairedLanguage: otherLanguage,
                    pairs: pairs,
                    readiness: .unknown,
                    isCurrentPair: currentPair.map { pairs.contains($0) } ?? false
                )
            }

        if let currentPair {
            if let currentPairIndex = rows.firstIndex(where: { $0.pairs.contains(currentPair) }) {
                let currentPairRow = rows.remove(at: currentPairIndex)
                rows.insert(currentPairRow, at: 0)
            }
        }

        return rows
    }

    private static func orderedGroups(
        _ groups: [AppleLanguagePackGroup],
        pinnedLanguageIDs: [String]
    ) -> [AppleLanguagePackGroup] {
        groups.enumerated()
            .sorted { lhs, rhs in
                let lhsPinIndex = pinnedLanguageIDs.firstIndex(of: lhs.element.id)
                let rhsPinIndex = pinnedLanguageIDs.firstIndex(of: rhs.element.id)
                switch (lhsPinIndex, rhsPinIndex) {
                case let (lhsIndex?, rhsIndex?):
                    return lhsIndex < rhsIndex
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}
