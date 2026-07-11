@testable import LinguistMac
@testable import LinguistMacCore
import SwiftData
import XCTest

@MainActor
final class SwiftDataTranslationHistoryStoreTests: XCTestCase {
    func testSwiftDataHistoryStoreDeduplicatesSavedResultID() async throws {
        let id = UUID()
        let (store, _) = try makeSwiftDataHistoryStore(trimLimit: 10)
        let original = makeResult(id: id, text: "original", createdAt: Date(timeIntervalSince1970: 1))
        let wordTranslations = [
            WordTranslation(sourceText: "hello", translatedText: "สวัสดี"),
            WordTranslation(sourceText: "world", translatedText: "โลก")
        ]
        let updated = makeResult(
            id: id,
            text: "updated",
            wordTranslations: wordTranslations,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        try await store.save(original)
        try await store.save(updated)

        let recent = try await store.recent(limit: 10)
        XCTAssertEqual(recent, [updated])
        XCTAssertEqual(recent.first?.wordTranslations, wordTranslations)
    }

    func testSwiftDataHistoryStorePreservesShownWordCards() async throws {
        let wordTranslation = WordTranslation(sourceText: "bank", translatedText: "ธนาคาร")
        let shownWordCard = ShownWordCardContent(
            wordTranslation: wordTranslation,
            wordIndex: 0,
            translatedText: "ริมฝั่งแม่น้ำ",
            sentenceContext: "The boat reached the river bank.",
            definition: "The side of a river.",
            example: "The boat reached the bank."
        )
        let result = makeResult(
            text: "The boat reached the river bank.",
            wordTranslations: [wordTranslation],
            shownWordCards: [shownWordCard]
        )
        let (store, _) = try makeSwiftDataHistoryStore(trimLimit: 10)

        try await store.save(result)

        let recent = try await store.recent(limit: 10)
        XCTAssertEqual(recent, [result])
        XCTAssertEqual(recent.first?.shownWordCards, [shownWordCard])
    }

    func testSwiftDataHistoryStorePreservesOptionalReadings() async throws {
        let result = makeResult(
            text: "こんにちは",
            sourceReading: "Kon'nichiwa",
            translatedReading: "sawatdi"
        )
        let (store, _) = try makeSwiftDataHistoryStore(trimLimit: 10)

        try await store.save(result)

        let recent = try await store.recent(limit: 10)
        XCTAssertEqual(recent.first?.sourceReading, "Kon'nichiwa")
        XCTAssertEqual(recent.first?.translatedReading, "sawatdi")
    }

    func testSwiftDataHistoryStoreFallsBackWhenShownWordCardJSONCannotDecode() async throws {
        let wordTranslation = WordTranslation(sourceText: "bank", translatedText: "ธนาคาร")
        let result = makeResult(
            text: "The boat reached the river bank.",
            wordTranslations: [wordTranslation]
        )
        let (store, container) = try makeSwiftDataHistoryStore(trimLimit: 10)
        let context = ModelContext(container)
        let record = TranslationHistoryRecord(result: result)
        record.shownWordCardsJSON = "{not valid json"
        context.insert(record)
        try context.save()

        let recent = try await store.recent(limit: 10)
        XCTAssertEqual(recent, [result])
        XCTAssertEqual(recent.first?.wordTranslations, [wordTranslation])
        XCTAssertEqual(recent.first?.shownWordCards, [])
    }

    func testSwiftDataHistoryStoreTrimsAllOverflowRows() async throws {
        let (store, container) = try makeSwiftDataHistoryStore(trimLimit: 3)
        let existing = (0 ..< 40).map { index in
            makeResult(text: "old-\(index)", createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        let context = ModelContext(container)
        for result in existing {
            context.insert(TranslationHistoryRecord(result: result))
        }
        try context.save()
        let newest = makeResult(text: "newest", createdAt: Date(timeIntervalSince1970: 100))

        try await store.save(newest)

        let recent = try await store.recent(limit: 100)
        XCTAssertEqual(recent, [newest, existing[39], existing[38]])
    }

    private func makeSwiftDataHistoryStore(
        trimLimit: Int
    ) throws -> (SwiftDataTranslationHistoryStore, ModelContainer) {
        let configuration = ModelConfiguration(
            "TestHistory-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: TranslationHistoryRecord.self,
            configurations: configuration
        )
        return (
            SwiftDataTranslationHistoryStore(container: container, trimLimit: trimLimit),
            container
        )
    }

    private func makeResult(
        id: UUID = UUID(),
        text: String,
        sourceReading: String? = nil,
        translatedReading: String? = nil,
        wordTranslations: [WordTranslation] = [],
        shownWordCards: [ShownWordCardContent] = [],
        createdAt: Date = Date(timeIntervalSince1970: 1)
    ) -> TranslationResult {
        let request = TranslationRequest(
            text: text,
            sourceLanguage: .english,
            targetLanguage: .thai,
            inputMode: .quickTranslate,
            providerID: .apple
        )
        return TranslationResult(
            id: id,
            request: request,
            translatedText: text,
            sourceReading: sourceReading,
            translatedReading: translatedReading,
            wordTranslations: wordTranslations,
            shownWordCards: shownWordCards,
            createdAt: createdAt
        )
    }
}
