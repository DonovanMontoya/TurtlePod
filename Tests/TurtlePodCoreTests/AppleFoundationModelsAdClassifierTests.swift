import Foundation
import XCTest
@testable import TurtlePodCore

#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppleFoundationModelsAdClassifierTests: XCTestCase {
    func testBuildsOverlappingTranscriptWindows() {
        let transcript = [
            TranscriptChunk(start: 0, end: 10, text: "Intro."),
            TranscriptChunk(start: 290, end: 305, text: "Use code TURTLE."),
            TranscriptChunk(start: 580, end: 590, text: "Sponsor continues."),
            TranscriptChunk(start: 601, end: 610, text: "Back to the show.")
        ]

        let windows = AppleFoundationModelsAdClassifier.transcriptWindows(
            for: transcript,
            windowDuration: 300,
            overlap: 15
        )

        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(windows.map(\.start), [0, 285, 570])
        XCTAssertEqual(windows.map(\.end), [300, 585, 610])
        XCTAssertTrue(windows[0].text.contains("Use code TURTLE."))
        XCTAssertTrue(windows[1].text.contains("Use code TURTLE."))
        XCTAssertTrue(windows[1].text.contains("Sponsor continues."))
        XCTAssertTrue(windows[2].text.contains("Sponsor continues."))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    func testMapsAppleAvailabilityReasonsToUserFacingMessages() {
        XCTAssertEqual(
            AppleFoundationModelsAdClassifier.availabilityMessage(for: .available),
            "Apple on-device model is available."
        )
        XCTAssertEqual(
            AppleFoundationModelsAdClassifier.availabilityMessage(for: .unavailable(.deviceNotEligible)),
            "This device is not eligible for Apple Intelligence."
        )
        XCTAssertEqual(
            AppleFoundationModelsAdClassifier.availabilityMessage(for: .unavailable(.appleIntelligenceNotEnabled)),
            "Apple Intelligence is off. Enable it in Settings to use on-device ad detection."
        )
        XCTAssertEqual(
            AppleFoundationModelsAdClassifier.availabilityMessage(for: .unavailable(.modelNotReady)),
            "Apple on-device model is not ready yet. It may still be downloading."
        )
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    func testMapsGenerationErrorsToUsefulMessages() {
        let message = AppleFoundationModelsAdClassifier.generationFailureMessage(
            for: LanguageModelSession.GenerationError.assetsUnavailable(.init(debugDescription: "fixture details"))
        )

        XCTAssertTrue(message.contains("Apple on-device ad detection could not classify this transcript."))
        XCTAssertTrue(message.contains("local model assets are unavailable"))
        XCTAssertTrue(message.contains("fixture details"))
        XCTAssertFalse(message.contains("FoundationModels.LanguageModelSession.GenerationError error -1"))
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    func testIncludesNSErrorDomainAndCodeForUntypedFoundationModelErrors() {
        let error = NSError(
            domain: "FoundationModels.LanguageModelSession.GenerationError",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn't be completed."]
        )

        let message = AppleFoundationModelsAdClassifier.generationFailureMessage(for: error)

        XCTAssertTrue(message.contains("domain: FoundationModels.LanguageModelSession.GenerationError"))
        XCTAssertTrue(message.contains("code: -1"))
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    func testParsesPlainJSONFallbackSegments() throws {
        let segments = try AppleFoundationModelsAdClassifier.parseJSONFallbackResponse(
            """
            ```json
            {"ad_segments":[{"start":95.0,"end":130.0,"confidence":1.2,"reason":"sponsor read"}]}
            ```
            """,
            provider: "apple-foundation-models",
            model: "system-language-model",
            window: TranscriptClassificationWindow(start: 100, end: 125, text: "")
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, 100)
        XCTAssertEqual(segments[0].end, 125)
        XCTAssertEqual(segments[0].confidence, 1)
        XCTAssertEqual(segments[0].reason, "sponsor read")
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    func testParsesLocalModelJSONVariants() throws {
        let segments = try AppleFoundationModelsAdClassifier.parseJSONFallbackResponse(
            """
            {"adSegments":[{"start":"101.5","end":124,"confidence":"0.82","reason":"promo code"}]}
            """,
            provider: "apple-foundation-models",
            model: "system-language-model",
            window: TranscriptClassificationWindow(start: 100, end: 125, text: "")
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, 101.5)
        XCTAssertEqual(segments[0].end, 124)
        XCTAssertEqual(segments[0].confidence, 0.82)
        XCTAssertEqual(segments[0].reason, "promo code")
    }
    #endif
}
