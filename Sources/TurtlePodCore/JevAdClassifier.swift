import Foundation

public enum JevRoute: Equatable, Sendable {
    case typeSafe
    case openRouter

    var endpoint: URL {
        switch self {
        case .typeSafe: URL(string: "https://api.typesafe.ai/v1/systemone")!
        case .openRouter: URL(string: "https://openrouter.ai/api/alpha/decisions")!
        }
    }

    var model: String {
        switch self {
        case .typeSafe: "jev-1.13.0"
        case .openRouter: "typesafe/jev-1.13"
        }
    }

    var provider: String {
        switch self {
        case .typeSafe: "jev-typesafe"
        case .openRouter: "jev-openrouter"
        }
    }
}

public enum JevClassifierError: Error, LocalizedError {
    case missingKey(String)
    case http(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingKey(let route): "Add a \(route) API key in Settings before classifying ads."
        case .http(let status): "Jev classification failed (HTTP \(status))."
        case .invalidResponse: "Jev returned an incomplete classification response."
        }
    }
}

public final class JevAdClassifier: AdClassificationProvider {
    public let providerName: String
    public let classificationModel: String

    private let route: JevRoute
    private let session: URLSession
    private let endpoint: URL

    public init(route: JevRoute, session: URLSession = .shared, endpoint: URL? = nil) {
        self.route = route
        self.session = session
        self.endpoint = endpoint ?? route.endpoint
        providerName = route.provider
        classificationModel = route.model
    }

    public func classify(transcript: [TranscriptChunk], apiKey: String) async throws -> [AdSegment] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JevClassifierError.missingKey(route == .typeSafe ? "TypeSafe" : "OpenRouter")
        }
        let excerpts = Self.makeExcerpts(transcript)
        let coarseProbabilities = try await probabilities(for: excerpts, apiKey: apiKey)
        // The first pass finds likely ad passages. Only audio cues within those
        // passages become skip ranges, so a transition never skips the full passage.
        let cueExcerpts = zip(excerpts, coarseProbabilities).flatMap { excerpt, probability in
            probability >= 0.5 ? excerpt.chunks.map {
                Excerpt(start: $0.start, end: $0.end, text: $0.text,
                        context: excerpt.text, chunks: [$0])
            } : []
        }
        let cueProbabilities = try await probabilities(for: cueExcerpts, apiKey: apiKey)
        var ads: [AdSegment] = []
        for (cue, probability) in zip(cueExcerpts, cueProbabilities) where probability >= 0.5 {
            ads.append(AdSegment(start: cue.start, end: cue.end, confidence: probability,
                                 reason: "Jev identified this audio cue as advertising.",
                                 provider: providerName, model: classificationModel))
        }
        return AdSegmentMerger.merge(ads, gapTolerance: 2)
    }

    private func probabilities(for excerpts: [Excerpt], apiKey: String) async throws -> [Double] {
        var probabilities: [Double] = []
        for offset in stride(from: 0, to: excerpts.count, by: 12) {
            try Task.checkCancellation()
            let batch = Array(excerpts[offset..<min(offset + 12, excerpts.count)])
            let state = Dictionary(uniqueKeysWithValues: batch.enumerated().map {
                ("passage_\($0.offset)", ["target": $0.element.text, "context": $0.element.context])
            })
            let questions = Dictionary(uniqueKeysWithValues: batch.indices.map { index in
                ("ad_\(index)", [
                    "type": "noul",
                    "instructions": "Is `passage_\(index).target` itself a paid advertisement or sponsor message in a podcast? Use `passage_\(index).context` only to interpret the target. Count host-read sponsors, promo codes, and commercial calls to action. Do not count ordinary story, discussion, credits, or a noncommercial mention of the show.",
                    "criteria": ["true": "The spoken passage is advertising a product or service.", "false": "The spoken passage is normal podcast content."]
                ] as [String: Any])
            })
            let payload: [String: Any] = ["model": classificationModel, "state": state, "questions": questions]
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let data = try await send(request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let answers = root["answers"] as? [String: [String: Any]] else {
                throw JevClassifierError.invalidResponse
            }
            for index in batch.indices {
                guard let answer = answers["ad_\(index)"],
                      answer["type"] as? String == "noul",
                      let probability = answer["noul"] as? Double,
                      probability.isFinite, (0...1).contains(probability) else {
                    throw JevClassifierError.invalidResponse
                }
                probabilities.append(probability)
            }
        }
        return probabilities
    }

    private func send(_ request: URLRequest) async throws -> Data {
        for attempt in 0..<3 {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw JevClassifierError.invalidResponse }
            if (http.statusCode == 429 || http.statusCode == 529), attempt < 2 {
                try await Task.sleep(for: .seconds(Double(attempt + 1)))
                continue
            }
            guard (200...299).contains(http.statusCode) else { throw JevClassifierError.http(http.statusCode) }
            return data
        }
        throw JevClassifierError.invalidResponse
    }

    private struct Excerpt {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
        let context: String
        let chunks: [TranscriptChunk]
    }

    private static func makeExcerpts(_ transcript: [TranscriptChunk]) -> [Excerpt] {
        var excerpts: [Excerpt] = []
        var current: [TranscriptChunk] = []
        var characterCount = 0
        for chunk in transcript.sorted(by: { $0.start < $1.start }) where !chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let first = current.first, !current.isEmpty,
               (chunk.end - first.start > 24 || characterCount + chunk.text.count > 500) {
                excerpts.append(Excerpt(start: first.start, end: current.last!.end,
                                        text: current.map(\.text).joined(separator: " "), context: "",
                                        chunks: current))
                current.removeAll()
                characterCount = 0
            }
            current.append(chunk)
            characterCount += chunk.text.count
        }
        if let first = current.first, let last = current.last {
            excerpts.append(Excerpt(start: first.start, end: last.end,
                                    text: current.map(\.text).joined(separator: " "), context: "",
                                    chunks: current))
        }
        return excerpts
    }
}
