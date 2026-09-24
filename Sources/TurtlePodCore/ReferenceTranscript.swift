import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TranscriptSource: Codable, Equatable, Sendable {
    public var url: URL
    public var type: String
    public var language: String?
    public var label: String

    public init(url: URL, type: String = "", language: String? = nil, label: String = "Imported") {
        self.url = url
        self.type = type
        self.language = language
        self.label = label
    }

    public func hasConflictingLanguage(with preferredLanguage: String) -> Bool {
        guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty else { return false }
        let preferred = preferredLanguage.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        let actual = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        return preferred != actual
    }

    /// VTT voice tags can be removed cleanly; some SRT publishers repeat speaker
    /// labels as ordinary words in every cue, weakening reference alignment.
    public static func preferredSources(from sources: [TranscriptSource], preferredLanguage: String? = nil) -> [TranscriptSource] {
        sources.enumerated().sorted { lhs, rhs in
            func isVTT(_ source: TranscriptSource) -> Bool {
                source.type.lowercased().hasPrefix("text/vtt") || source.url.pathExtension.lowercased() == "vtt"
            }
            func languageRank(_ source: TranscriptSource) -> Int {
                guard let preferredLanguage, !preferredLanguage.isEmpty else { return 0 }
                guard let language = source.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty else { return 1 }
                return source.hasConflictingLanguage(with: preferredLanguage) ? 2 : 0
            }
            let leftLanguage = languageRank(lhs.element)
            let rightLanguage = languageRank(rhs.element)
            if leftLanguage != rightLanguage { return leftLanguage < rightLanguage }
            let left = isVTT(lhs.element)
            let right = isVTT(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left
        }.map(\.element)
    }

    public static func isRemoteURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }
}

/// Reference timestamps belong to the publisher's audio, never directly to a download.
public struct ReferenceTranscript: Codable, Equatable, Sendable {
    public var source: TranscriptSource
    public var text: String
    public var fetchedAt: Date

    public init(source: TranscriptSource, text: String, fetchedAt: Date = Date()) {
        self.source = source
        self.text = text
        self.fetchedAt = fetchedAt
    }
}

public enum ReferenceTranscriptError: Error, LocalizedError {
    case invalidURL, tooLarge, empty, unsupported, accessDenied, http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a direct HTTP or HTTPS transcript URL."
        case .tooLarge: "The transcript exceeds the 8 MB limit."
        case .empty: "The file contains no usable transcript text."
        case .unsupported: "Use a VTT, SRT, Podcast Index JSON, HTML, or plain-text transcript."
        case .accessDenied: "The transcript server denied access. Import a transcript file you can export, or use a publisher transcript."
        case .http(let status): "The transcript server returned HTTP \(status)."
        }
    }
}

public enum ReferenceTranscriptParser {
    public static let maximumBytes = 8 * 1024 * 1024

    public static func parse(_ data: Data, source: TranscriptSource) throws -> ReferenceTranscript {
        guard data.count <= maximumBytes else { throw ReferenceTranscriptError.tooLarge }
        guard let raw = String(data: data, encoding: .utf8) else { throw ReferenceTranscriptError.unsupported }
        let input = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        let type = source.type.lowercased().split(separator: ";").first.map(String.init) ?? ""
        let ext = source.url.pathExtension.lowercased()
        // Omny serves extensionless SRT URLs as text/plain, including direct imports.
        let hasSubtitleTiming = input.range(
            of: #"(?m)^\s*(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3}\s+-->\s+"#,
            options: .regularExpression
        ) != nil
        let text: String
        if type.contains("json") || ext == "json" || input.hasPrefix("{") {
            struct Document: Decodable {
                struct Segment: Decodable { let body: String }
                let segments: [Segment]
            }
            guard let document = try? JSONDecoder().decode(Document.self, from: data) else {
                throw ReferenceTranscriptError.unsupported
            }
            text = document.segments.map(\.body).joined(separator: "\n")
        } else if input.hasPrefix("WEBVTT") || ["vtt", "srt"].contains(ext)
                    || type.contains("vtt") || type.contains("subrip")
                    || ["application/srt", "text/srt"].contains(type) || hasSubtitleTiming {
            text = input.components(separatedBy: "\n\n").compactMap { block -> String? in
                let lines = block.components(separatedBy: "\n")
                guard let timing = lines.firstIndex(where: { $0.contains("-->") }), timing + 1 < lines.count else { return nil }
                return lines.dropFirst(timing + 1).joined(separator: "\n")
            }.joined(separator: "\n")
        } else if type.contains("html") || ["html", "htm"].contains(ext) || input.hasPrefix("<") {
            text = input.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        } else if type.isEmpty || type == "text/plain" || ext == "txt" {
            text = input
        } else {
            throw ReferenceTranscriptError.unsupported
        }
        let cleaned = EpisodeDescriptionCleaner.clean(text)
        guard !cleaned.isEmpty else { throw ReferenceTranscriptError.empty }
        return ReferenceTranscript(source: source, text: cleaned)
    }
}

public protocol ReferenceTranscriptService: Sendable {
    func fetch(_ source: TranscriptSource) async throws -> ReferenceTranscript
}

public struct HTTPReferenceTranscriptService: ReferenceTranscriptService {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(_ source: TranscriptSource) async throws -> ReferenceTranscript {
        guard TranscriptSource.isRemoteURL(source.url) else { throw ReferenceTranscriptError.invalidURL }
        var request = URLRequest(url: source.url)
        request.timeoutInterval = 30
        request.setValue("text/vtt, application/srt, application/x-subrip, application/json, text/plain, text/html", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        #if canImport(FoundationNetworking)
        // FoundationNetworking does not expose URLSession.AsyncBytes.
        (data, response) = try await session.data(for: request)
        try validate(response)
        #else
        let (bytes, receivedResponse) = try await session.bytes(for: request)
        response = receivedResponse
        try validate(response)
        var buffer = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard buffer.count < ReferenceTranscriptParser.maximumBytes else { throw ReferenceTranscriptError.tooLarge }
            buffer.append(byte)
        }
        data = buffer
        #endif
        var resolvedSource = source
        // Keep an explicit RSS format; servers sometimes mislabel VTT as text/plain.
        if resolvedSource.type.isEmpty { resolvedSource.type = response.mimeType ?? "" }
        return try ReferenceTranscriptParser.parse(data, source: resolvedSource)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ReferenceTranscriptError.unsupported }
        guard TranscriptSource.isRemoteURL(http.url ?? URL(fileURLWithPath: "/")) else { throw ReferenceTranscriptError.invalidURL }
        if [401, 403].contains(http.statusCode) { throw ReferenceTranscriptError.accessDenied }
        guard (200..<300).contains(http.statusCode) else { throw ReferenceTranscriptError.http(http.statusCode) }
        guard response.expectedContentLength <= ReferenceTranscriptParser.maximumBytes else { throw ReferenceTranscriptError.tooLarge }
    }
}
