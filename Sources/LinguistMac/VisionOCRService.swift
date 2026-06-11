import Foundation
import LinguistMacCore
import NaturalLanguage
import Vision

struct AppleVisionOCRService: OCRServicing {
    func recognizeText(in region: CapturedScreenRegion) async throws -> LinguistMacCore.RecognizedText {
        guard !region.imageData.isEmpty else {
            throw TranslationFailure.noTextRecognized
        }

        do {
            var request = RecognizeTextRequest(.revision3)
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = true

            let observations = try await request.perform(on: region.imageData)
            let lines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            let text = OCRTextPreprocessor.normalize(lines: lines)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationFailure.noTextRecognized
            }

            return LinguistMacCore.RecognizedText(
                text: text,
                language: detectedLanguage(from: observations) ?? detectedLanguage(in: text)
            )
        } catch let failure as TranslationFailure {
            throw failure
        } catch {
            throw TranslationFailure.providerFailed("OCR failed: \(error.localizedDescription)")
        }
    }

    private func detectedLanguage(from observations: [Vision.RecognizedTextObservation]) -> TranslationLanguage? {
        #if compiler(>=6.3)
            guard #available(macOS 26.0, *) else {
                return nil
            }

            return observations
                .lazy
                .flatMap(\.recognitionLanguages)
                .compactMap(TranslationLanguage.fromLocaleLanguage)
                .first
        #else
            _ = observations
            return nil
        #endif
    }

    private func detectedLanguage(in text: String) -> TranslationLanguage? {
        guard let dominantLanguage = NLLanguageRecognizer.dominantLanguage(for: text) else {
            return nil
        }

        return TranslationLanguageCatalog.language(forID: dominantLanguage.rawValue)
    }
}
