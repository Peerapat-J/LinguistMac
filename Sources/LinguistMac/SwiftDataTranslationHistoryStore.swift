import Foundation
import LinguistMacCore
import SwiftData

@Model
final class TranslationHistoryRecord {
    var id: UUID
    var originalText: String
    var translatedText: String
    var wordTranslationsJSON: String?
    var shownWordCardsJSON: String? = nil
    var sourceLanguageID: String
    var sourceLanguageDisplayName: String
    var sourceLanguageSupportsAutoDetect: Bool
    var targetLanguageID: String
    var targetLanguageDisplayName: String
    var targetLanguageSupportsAutoDetect: Bool
    var inputModeRawValue: String
    var providerIDRawValue: String
    var createdAt: Date

    init(result: TranslationResult) {
        id = result.id
        originalText = result.originalText
        translatedText = result.translatedText
        wordTranslationsJSON = Self.encodedWordTranslations(result.wordTranslations)
        shownWordCardsJSON = Self.encodedShownWordCards(result.shownWordCards)
        sourceLanguageID = result.request.sourceLanguage.id
        sourceLanguageDisplayName = result.request.sourceLanguage.displayName
        sourceLanguageSupportsAutoDetect = result.request.sourceLanguage.supportsAutoDetect
        targetLanguageID = result.request.targetLanguage.id
        targetLanguageDisplayName = result.request.targetLanguage.displayName
        targetLanguageSupportsAutoDetect = result.request.targetLanguage.supportsAutoDetect
        inputModeRawValue = result.request.inputMode.rawValue
        providerIDRawValue = result.request.providerID.rawValue
        createdAt = result.createdAt
    }

    func update(with result: TranslationResult) {
        originalText = result.originalText
        translatedText = result.translatedText
        wordTranslationsJSON = Self.encodedWordTranslations(result.wordTranslations)
        shownWordCardsJSON = Self.encodedShownWordCards(result.shownWordCards)
        sourceLanguageID = result.request.sourceLanguage.id
        sourceLanguageDisplayName = result.request.sourceLanguage.displayName
        sourceLanguageSupportsAutoDetect = result.request.sourceLanguage.supportsAutoDetect
        targetLanguageID = result.request.targetLanguage.id
        targetLanguageDisplayName = result.request.targetLanguage.displayName
        targetLanguageSupportsAutoDetect = result.request.targetLanguage.supportsAutoDetect
        inputModeRawValue = result.request.inputMode.rawValue
        providerIDRawValue = result.request.providerID.rawValue
        createdAt = result.createdAt
    }

    var result: TranslationResult? {
        guard let inputMode = TranslationInputMode(rawValue: inputModeRawValue) else {
            return nil
        }

        let request = TranslationRequest(
            text: originalText,
            sourceLanguage: TranslationLanguage(
                id: sourceLanguageID,
                displayName: sourceLanguageDisplayName,
                supportsAutoDetect: sourceLanguageSupportsAutoDetect
            ),
            targetLanguage: TranslationLanguage(
                id: targetLanguageID,
                displayName: targetLanguageDisplayName,
                supportsAutoDetect: targetLanguageSupportsAutoDetect
            ),
            inputMode: inputMode,
            providerID: TranslationProviderID(rawValue: providerIDRawValue)
        )

        return TranslationResult(
            id: id,
            request: request,
            translatedText: translatedText,
            originalText: originalText,
            wordTranslations: Self.decodedWordTranslations(from: wordTranslationsJSON),
            shownWordCards: Self.decodedShownWordCards(from: shownWordCardsJSON),
            createdAt: createdAt
        )
    }

    private static func encodedWordTranslations(_ wordTranslations: [WordTranslation]) -> String? {
        guard !wordTranslations.isEmpty,
              let data = try? JSONEncoder().encode(wordTranslations)
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func decodedWordTranslations(from json: String?) -> [WordTranslation] {
        guard let json,
              let data = json.data(using: .utf8),
              let wordTranslations = try? JSONDecoder().decode([WordTranslation].self, from: data)
        else {
            return []
        }

        return wordTranslations
    }

    private static func encodedShownWordCards(_ shownWordCards: [ShownWordCardContent]) -> String? {
        guard !shownWordCards.isEmpty,
              let data = try? JSONEncoder().encode(shownWordCards)
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func decodedShownWordCards(from json: String?) -> [ShownWordCardContent] {
        guard let json,
              let data = json.data(using: .utf8),
              let shownWordCards = try? JSONDecoder().decode([ShownWordCardContent].self, from: data)
        else {
            return []
        }

        return shownWordCards
    }
}

actor SwiftDataTranslationHistoryStore: TranslationHistoryStoring {
    private let container: ModelContainer
    private let trimLimit: Int

    init(
        container: ModelContainer,
        trimLimit: Int = TranslationHistoryPolicy.defaultLimit
    ) {
        self.container = container
        self.trimLimit = trimLimit
    }

    static func make(
        trimLimit: Int = TranslationHistoryPolicy.defaultLimit
    ) throws -> any TranslationHistoryStoring {
        do {
            let configuration = ModelConfiguration(
                "LinguistMacTranslationHistory",
                isStoredInMemoryOnly: false
            )
            let container = try ModelContainer(
                for: TranslationHistoryRecord.self,
                configurations: configuration
            )
            return SwiftDataTranslationHistoryStore(container: container, trimLimit: trimLimit)
        } catch {
            NSLog(
                "SwiftData translation history initialization failed: %@",
                error.localizedDescription
            )
            throw error
        }
    }

    func save(_ result: TranslationResult) async throws {
        let context = ModelContext(container)
        let matchingRecords = try existingRecords(matching: result.id, in: context)
        if let record = matchingRecords.first {
            record.update(with: result)
            for duplicate in matchingRecords.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            context.insert(TranslationHistoryRecord(result: result))
        }
        try trim(in: context)
        try context.save()
    }

    func recent(limit: Int) async throws -> [TranslationResult] {
        guard limit > 0 else {
            return []
        }

        let context = ModelContext(container)
        var descriptor = FetchDescriptor<TranslationHistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).compactMap(\.result)
    }

    private func existingRecords(
        matching id: UUID,
        in context: ModelContext
    ) throws -> [TranslationHistoryRecord] {
        let descriptor = FetchDescriptor<TranslationHistoryRecord>(
            predicate: #Predicate { record in
                record.id == id
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func trim(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<TranslationHistoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)
        for record in records.dropFirst(trimLimit) {
            context.delete(record)
        }
    }
}
