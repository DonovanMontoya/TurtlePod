import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public final class AppleFoundationModelsAdClassifier: AdClassificationProvider {
    public let providerName = "apple-foundation-models"
    public let classificationModel = "system-language-model"

    private let windowDuration: TimeInterval
    private let windowOverlap: TimeInterval

    public init(windowDuration: TimeInterval = 120, windowOverlap: TimeInterval = 10) {
        self.windowDuration = windowDuration
        self.windowOverlap = windowOverlap
    }

    public func classify(transcript: [TranscriptChunk], apiKey: String = "") async throws -> [AdSegment] {
        #if targetEnvironment(simulator)
        throw TurtlePodError.localModelUnavailable(Self.simulatorUnavailableMessage)
        #else
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return try await classifyWithFoundationModels(transcript: transcript)
        }
        #endif

        throw TurtlePodError.localModelUnavailable(Self.unavailableMessage)
        #endif
    }

    public static var availabilityStatusMessage: String {
        #if targetEnvironment(simulator)
        return simulatorUnavailableMessage
        #else
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return availabilityMessage(for: SystemLanguageModel.default.availability)
        }
        #endif

        return unavailableMessage
        #endif
    }

    public static func validateAvailability() throws {
        #if targetEnvironment(simulator)
        throw TurtlePodError.localModelUnavailable(simulatorUnavailableMessage)
        #else
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            guard availability == .available else {
                throw TurtlePodError.localModelUnavailable(availabilityMessage(for: availability))
            }
            return
        }
        #endif

        throw TurtlePodError.localModelUnavailable(unavailableMessage)
        #endif
    }

    public static func transcriptWindows(
        for transcript: [TranscriptChunk],
        windowDuration: TimeInterval = 300,
        overlap: TimeInterval = 15
    ) -> [TranscriptClassificationWindow] {
        guard !transcript.isEmpty, windowDuration > 0 else { return [] }

        let sortedTranscript = transcript.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }
        let firstStart = sortedTranscript.map(\.start).min() ?? 0
        let finalEnd = sortedTranscript.map(\.end).max() ?? firstStart
        guard finalEnd >= firstStart else { return [] }

        let step = max(windowDuration - max(overlap, 0), 1)
        var windows: [TranscriptClassificationWindow] = []
        var windowStart = firstStart

        while windowStart <= finalEnd {
            let windowEnd = min(windowStart + windowDuration, finalEnd)
            let chunks = sortedTranscript.filter { chunk in
                chunk.end >= windowStart && chunk.start <= windowEnd
            }

            if !chunks.isEmpty {
                windows.append(
                    TranscriptClassificationWindow(
                        start: windowStart,
                        end: windowEnd,
                        text: OpenAIProvider.transcriptWindowText(chunks)
                    )
                )
            }

            if windowEnd >= finalEnd { break }
            windowStart += step
        }

        return windows
    }

    private static let unavailableMessage = "Apple on-device ad detection requires iOS 26 or macOS 26, an Apple Intelligence-capable device, and Apple Intelligence enabled in Settings."
    private static let simulatorUnavailableMessage = "Apple on-device ad detection is not available in the iOS Simulator. Run on an Apple Intelligence-capable physical device with Apple Intelligence enabled."
}

public struct TranscriptClassificationWindow: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension AppleFoundationModelsAdClassifier {
    func classifyWithFoundationModels(transcript: [TranscriptChunk]) async throws -> [AdSegment] {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw TurtlePodError.localModelUnavailable(Self.availabilityMessage(for: model.availability))
        }

        let windows = Self.transcriptWindows(
            for: transcript,
            windowDuration: windowDuration,
            overlap: windowOverlap
        )

        var detectedSegments: [AdSegment] = []
        for window in windows {
            let session = LanguageModelSession(model: model, instructions: Self.instructions)
            let prompt = """
            Analyze this podcast transcript window for sponsorships, host-read ads, promo codes, and paid promotional interruptions.
            Do not mark normal show content.
            Use the transcript timestamps exactly. Return narrow ad boundaries to the nearest 0.1 second when possible.

            \(window.text)
            """

            do {
                detectedSegments.append(contentsOf: try await classifyWindowWithGuidedGeneration(
                    session: session,
                    prompt: prompt,
                    window: window
                ))
            } catch {
                detectedSegments.append(contentsOf: try await classifyWindowWithJSONFallback(
                    model: model,
                    transcriptWindow: window,
                    guidedGenerationError: error
                ))
            }
        }

        return detectedSegments
    }

    private func classifyWindowWithGuidedGeneration(
        session: LanguageModelSession,
        prompt: String,
        window: TranscriptClassificationWindow
    ) async throws -> [AdSegment] {
        let response = try await session.respond(
            to: prompt,
            generating: AppleAdClassificationResponse.self,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 2000)
        )

        return response.content.adSegments.compactMap { segment in
            normalizedAdSegment(
                start: segment.start,
                end: segment.end,
                confidence: segment.confidence,
                reason: segment.reason,
                window: window
            )
        }
    }

    private func classifyWindowWithJSONFallback(
        model: SystemLanguageModel,
        transcriptWindow window: TranscriptClassificationWindow,
        guidedGenerationError: Error
    ) async throws -> [AdSegment] {
        let fallbackSession = LanguageModelSession(model: model, instructions: Self.instructions)
        let prompt = """
        Analyze this podcast transcript window for sponsorships, host-read ads, promo codes, and paid promotional interruptions.
        Do not mark normal show content.
        Use the transcript timestamps exactly.
        Return only compact JSON with this shape and no Markdown:
        {"ad_segments":[{"start":0.0,"end":0.0,"confidence":0.0,"reason":"short reason"}]}

        \(window.text)
        """

        do {
            let response = try await fallbackSession.respond(
                to: prompt,
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 2000)
            )
            return try Self.parseJSONFallbackResponse(
                response.content,
                provider: providerName,
                model: classificationModel,
                window: window
            )
        } catch {
            let guidedMessage = Self.generationFailureMessage(for: guidedGenerationError)
            let fallbackMessage = Self.generationFailureMessage(for: error)
            throw TurtlePodError.localModelGenerationFailed(
                "\(guidedMessage) Plain JSON fallback also failed: \(fallbackMessage)"
            )
        }
    }

    private func normalizedAdSegment(
        start: Double,
        end: Double,
        confidence: Double,
        reason: String,
        window: TranscriptClassificationWindow
    ) -> AdSegment? {
        let start = max(start, window.start)
        let end = min(end, window.end)
        guard end > start else { return nil }

        return AdSegment(
            start: start,
            end: end,
            confidence: min(max(confidence, 0), 1),
            reason: reason,
            provider: providerName,
            model: classificationModel
        )
    }

    static func availabilityMessage(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Apple on-device model is available."
        case .unavailable(.deviceNotEligible):
            return "This device is not eligible for Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is off. Enable it in Settings to use on-device ad detection."
        case .unavailable(.modelNotReady):
            return "Apple on-device model is not ready yet. It may still be downloading."
        @unknown default:
            return unavailableMessage
        }
    }

    static func generationFailureMessage(for error: Error) -> String {
        let prefix = "Apple on-device ad detection could not classify this transcript."

        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .assetsUnavailable(let context):
                return "\(prefix) The local model assets are unavailable. \(context.debugDescription)"
            case .exceededContextWindowSize(let context):
                return "\(prefix) The transcript window was too large for the local model. \(context.debugDescription)"
            case .guardrailViolation(let context):
                return "\(prefix) Apple Intelligence blocked the transcript content. \(context.debugDescription)"
            case .unsupportedGuide(let context):
                return "\(prefix) The structured output guide is unsupported by this local model. \(context.debugDescription)"
            case .unsupportedLanguageOrLocale(let context):
                return "\(prefix) The transcript language or current locale is unsupported. \(context.debugDescription)"
            case .decodingFailure(let context):
                return "\(prefix) The local model returned data that could not be decoded. \(context.debugDescription)"
            case .rateLimited(let context):
                return "\(prefix) The local model is rate limited. Try again shortly. \(context.debugDescription)"
            case .concurrentRequests(let context):
                return "\(prefix) Another local model request is already running. Try again after it finishes. \(context.debugDescription)"
            case .refusal(_, let context):
                return "\(prefix) The local model refused the request. \(context.debugDescription)"
            @unknown default:
                return "\(prefix) \(generationError.localizedDescription)"
            }
        }

        let nsError = error as NSError
        return "\(prefix) \(error.localizedDescription) [domain: \(nsError.domain), code: \(nsError.code)]"
    }

    static func parseJSONFallbackResponse(
        _ text: String,
        provider: String,
        model: String,
        window: TranscriptClassificationWindow
    ) throws -> [AdSegment] {
        let jsonText = try extractJSONObjectText(from: text)
        guard let data = jsonText.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSegments = rawAdSegments(from: object) else {
            throw TurtlePodError.unsupportedResponse
        }

        return rawSegments.compactMap { segment in
            guard let start = numericValue(for: "start", in: segment),
                  let end = numericValue(for: "end", in: segment),
                  let confidence = numericValue(for: "confidence", in: segment) else {
                return nil
            }

            let clampedStart = max(start, window.start)
            let clampedEnd = min(end, window.end)
            guard clampedEnd > clampedStart else { return nil }

            return AdSegment(
                start: clampedStart,
                end: clampedEnd,
                confidence: min(max(confidence, 0), 1),
                reason: segment["reason"] as? String ?? "",
                provider: provider,
                model: model
            )
        }
    }

    private static func rawAdSegments(from object: [String: Any]) -> [[String: Any]]? {
        for key in ["ad_segments", "adSegments", "segments", "ads"] {
            if let segments = object[key] as? [[String: Any]] {
                return segments
            }
        }
        return nil
    }

    private static func numericValue(for key: String, in object: [String: Any]) -> Double? {
        if let value = object[key] as? Double {
            return value
        }
        if let value = object[key] as? Int {
            return Double(value)
        }
        if let value = object[key] as? NSNumber {
            return value.doubleValue
        }
        if let value = object[key] as? String {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func extractJSONObjectText(from text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startIndex = trimmed.firstIndex(of: "{") else {
            throw TurtlePodError.unsupportedResponse
        }

        var depth = 0
        var inString = false
        var escaped = false
        var endIndex: String.Index?

        for index in trimmed.indices[startIndex...] {
            let char = trimmed[index]
            if escaped { escaped = false; continue }
            if char == "\\" && inString { escaped = true; continue }
            if char == "\"" { inString.toggle(); continue }
            if inString { continue }
            if char == "{" { depth += 1 }
            else if char == "}" {
                depth -= 1
                if depth == 0 { endIndex = index; break }
            }
        }

        guard let end = endIndex else {
            throw TurtlePodError.unsupportedResponse
        }

        return String(trimmed[startIndex...end])
    }

    static let instructions = """
    You identify ad segments in podcast transcripts.
    Return only structured ad segment data.
    Mark sponsorships, host-read ads, promo codes, and paid promotional interruptions.
    Do not mark normal show content, editorial recommendations, guest introductions, credits, or unpaid announcements.
    """
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
private struct AppleAdClassificationResponse {
    @Guide(description: "Detected ad segments in this transcript window.", .maximumCount(20))
    var adSegments: [AppleAdSegmentResponse]
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
private struct AppleAdSegmentResponse {
    @Guide(description: "Start timestamp in seconds.", .minimum(0))
    var start: Double

    @Guide(description: "End timestamp in seconds.", .minimum(0))
    var end: Double

    @Guide(description: "Confidence from 0.0 to 1.0.", .range(0.0...1.0))
    var confidence: Double

    @Guide(description: "Short reason for the detected ad segment.")
    var reason: String
}
#endif
