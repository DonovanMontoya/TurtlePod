import Foundation

public final class OpenAIProvider: AIProvider {
    public let providerName = "openai"
    public let transcriptionModel: String
    public let classificationModel: String

    private let session: URLSession
    private let baseURL: URL

    public init(
        transcriptionModel: String = "gpt-4o-mini-transcribe",
        classificationModel: String = "gpt-4.1-mini",
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!
    ) {
        self.transcriptionModel = transcriptionModel
        self.classificationModel = classificationModel
        self.session = session
        self.baseURL = baseURL
    }

    public func transcribe(audioFile: URL, apiKey: String) async throws -> [TranscriptChunk] {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "audio/transcriptions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioFile)
        request.httpBody = MultipartFormData(boundary: boundary)
            .addField(name: "model", value: transcriptionModel)
            .addField(name: "response_format", value: Self.transcriptionResponseFormat(for: transcriptionModel))
            .addFile(name: "file", filename: audioFile.lastPathComponent, contentType: Self.audioContentType(for: audioFile), data: audioData)
            .body

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try Self.parseTranscriptionResponse(data)
    }

    public func classify(transcript: [TranscriptChunk], apiKey: String) async throws -> [AdSegment] {
        let windows = transcript.map { chunk in
            "[\(chunk.start)-\(chunk.end)] \(chunk.text)"
        }.joined(separator: "\n")

        let schemaInstruction = """
        Return only JSON with this shape:
        {"ad_segments":[{"start":0.0,"end":0.0,"confidence":0.0,"reason":"short reason"}]}
        Identify sponsorship, host-read ads, promo codes, and paid promotional interruptions. Do not mark normal show content.
        """

        let payload: [String: Any] = [
            "model": classificationModel,
            "input": [
                [
                    "role": "system",
                    "content": schemaInstruction
                ],
                [
                    "role": "user",
                    "content": windows
                ]
            ],
            "temperature": 0
        ]

        var request = URLRequest(url: baseURL.appending(path: "responses"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try Self.parseClassificationResponse(data, provider: providerName, model: classificationModel)
    }

    public static func parseTranscriptionResponse(_ data: Data) throws -> [TranscriptChunk] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw TurtlePodError.unsupportedResponse
        }

        if let segments = dictionary["segments"] as? [[String: Any]] {
            return segments.compactMap { segment in
                guard let start = segment["start"] as? Double,
                      let end = segment["end"] as? Double,
                      let text = segment["text"] as? String else {
                    return nil
                }
                return TranscriptChunk(start: start, end: end, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if let text = dictionary["text"] as? String {
            return [TranscriptChunk(start: 0, end: 0, text: text)]
        }

        throw TurtlePodError.unsupportedResponse
    }

    public static func transcriptionResponseFormat(for model: String) -> String {
        model == "whisper-1" ? "verbose_json" : "json"
    }

    public static func audioContentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a":
            "audio/mp4"
        case "mp4":
            "audio/mp4"
        case "mpga":
            "audio/mpeg"
        case "wav":
            "audio/wav"
        case "webm":
            "audio/webm"
        default:
            "audio/mpeg"
        }
    }

    public static func parseClassificationResponse(_ data: Data, provider: String, model: String) throws -> [AdSegment] {
        let object = try JSONSerialization.jsonObject(with: data)

        if let direct = object as? [String: Any], let adSegments = direct["ad_segments"] as? [[String: Any]] {
            return parseAdSegments(adSegments, provider: provider, model: model)
        }

        guard let dictionary = object as? [String: Any] else {
            throw TurtlePodError.unsupportedResponse
        }

        if let outputText = dictionary["output_text"] as? String {
            return try parseClassificationJSONText(outputText, provider: provider, model: model)
        }

        if let output = dictionary["output"] as? [[String: Any]] {
            let text = output
                .compactMap { item in item["content"] as? [[String: Any]] }
                .flatMap { $0 }
                .compactMap { content -> String? in
                    if content["type"] as? String == "output_text" {
                        return content["text"] as? String
                    }
                    return nil
                }
                .joined()
            if !text.isEmpty {
                return try parseClassificationJSONText(text, provider: provider, model: model)
            }
        }

        throw TurtlePodError.unsupportedResponse
    }

    private static func parseClassificationJSONText(_ text: String, provider: String, model: String) throws -> [AdSegment] {
        guard let data = text.data(using: .utf8) else {
            throw TurtlePodError.unsupportedResponse
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let adSegments = dictionary["ad_segments"] as? [[String: Any]] else {
            throw TurtlePodError.unsupportedResponse
        }
        return parseAdSegments(adSegments, provider: provider, model: model)
    }

    private static func parseAdSegments(_ rawSegments: [[String: Any]], provider: String, model: String) -> [AdSegment] {
        rawSegments.compactMap { segment in
            guard let start = segment["start"] as? Double,
                  let end = segment["end"] as? Double,
                  let confidence = segment["confidence"] as? Double else {
                return nil
            }

            return AdSegment(
                start: start,
                end: end,
                confidence: confidence,
                reason: segment["reason"] as? String ?? "",
                provider: provider,
                model: model
            )
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.parseOpenAIErrorMessage(data) ?? String(data: data, encoding: .utf8) ?? "OpenAI request failed."
            throw NSError(domain: "OpenAIProvider", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func parseOpenAIErrorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let error = dictionary["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}

private struct MultipartFormData {
    let boundary: String
    private(set) var body = Data()

    func addField(name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.body.appendString("--\(boundary)\r\n")
        copy.body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.body.appendString("\(value)\r\n")
        return copy
    }

    func addFile(name: String, filename: String, contentType: String, data: Data) -> MultipartFormData {
        var copy = self
        copy.body.appendString("--\(boundary)\r\n")
        copy.body.appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        copy.body.appendString("Content-Type: \(contentType)\r\n\r\n")
        copy.body.append(data)
        copy.body.appendString("\r\n")
        copy.body.appendString("--\(boundary)--\r\n")
        return copy
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
