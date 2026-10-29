import AVFoundation
import Foundation

public struct EpisodeChapter: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval?
    public var title: String
    public var imageURL: URL?
    public var linkURL: URL?

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval? = nil,
        title: String,
        imageURL: URL? = nil,
        linkURL: URL? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
        self.imageURL = imageURL
        self.linkURL = linkURL
    }
}

/// Podcasting 2.0 JSON chapters: https://github.com/Podcastindex-org/podcast-namespace/blob/main/chapters/jsonChapters.md
public enum PodcastChaptersParser {
    private struct Document: Decodable {
        var chapters: [Entry]
    }

    private struct Entry: Decodable {
        var startTime: FlexibleNumber?
        var endTime: FlexibleNumber?
        var title: String?
        var img: String?
        var url: String?
        var toc: Bool?
    }

    private struct FlexibleNumber: Decodable {
        var value: Double?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
            } else if let string = try? container.decode(String.self) {
                value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                value = nil
            }
        }
    }

    public static func parse(_ data: Data) throws -> [EpisodeChapter] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        let chapters = document.chapters.enumerated().compactMap { index, entry -> EpisodeChapter? in
            guard entry.toc != false, let start = entry.startTime?.value, start.isFinite, start >= 0 else { return nil }
            let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let end = entry.endTime?.value.flatMap { $0.isFinite && $0 > start ? $0 : nil }
            return EpisodeChapter(
                start: start,
                end: end,
                title: title.isEmpty ? "Chapter \(index + 1)" : title,
                imageURL: entry.img.flatMap(remoteURL),
                linkURL: entry.url.flatMap(remoteURL)
            )
        }
        return EpisodeChapterLoader.normalized(chapters)
    }

    private static func remoteURL(_ rawValue: String) -> URL? {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }
}

public enum EpisodeChapterLoader {
    /// Embedded chapters (ID3 CHAP / MP4 chapter track) via AVURLAsset.loadChapterMetadataGroups(bestMatchingPreferredLanguages:), works for local file or remote URL.
    public static func embeddedChapters(in url: URL) async -> [EpisodeChapter] {
        let asset = AVURLAsset(url: url)
        do {
            var groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)
            if groups.isEmpty {
                let locales = try await asset.load(.availableChapterLocales)
                let languages = locales.compactMap { $0.language.languageCode?.identifier ?? $0.identifier }
                if !languages.isEmpty {
                    groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages)
                }
            }

            var chapters: [EpisodeChapter] = []
            for (index, group) in groups.enumerated() {
                let start = group.timeRange.start.seconds
                guard start.isFinite, start >= 0 else { continue }
                let endSeconds = group.timeRange.end.seconds
                let titleItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first
                let title = (try? await titleItem?.load(.stringValue))??.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                chapters.append(EpisodeChapter(
                    start: start,
                    end: endSeconds.isFinite && endSeconds > start ? endSeconds : nil,
                    title: title.isEmpty ? "Chapter \(index + 1)" : title
                ))
            }
            return normalized(chapters)
        } catch {
            return []
        }
    }

    /// Fetch Podcasting 2.0 chapters JSON.
    public static func remoteChapters(from url: URL, session: URLSession = .shared) async throws -> [EpisodeChapter] {
        var request = URLRequest(url: url)
        request.setValue("TurtlePod/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json+chapters, application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try PodcastChaptersParser.parse(data)
    }

    /// Convenience: prefer chaptersURL JSON, fall back to embedded chapters in the audio (local file URL if given else remote audio URL). Never throws; returns [] on failure.
    public static func chapters(for episode: PodcastEpisode, preferLocalFile: URL?) async -> [EpisodeChapter] {
        if let chaptersURL = episode.chaptersURL,
           let remote = try? await remoteChapters(from: chaptersURL),
           !remote.isEmpty {
            return remote
        }
        guard !Task.isCancelled else { return [] }
        return await embeddedChapters(in: preferLocalFile ?? episode.audioURL)
    }

    public static func chapter(at time: TimeInterval, in chapters: [EpisodeChapter]) -> EpisodeChapter? {
        chapters.last { $0.start <= time }
    }

    /// Sorts by start and fills a missing `end` from the next chapter's start.
    static func normalized(_ chapters: [EpisodeChapter]) -> [EpisodeChapter] {
        var sorted = chapters.enumerated()
            .sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start }
            .map(\.element)
        for index in sorted.indices where sorted[index].end == nil && index + 1 < sorted.count {
            let nextStart = sorted[index + 1].start
            if nextStart > sorted[index].start {
                sorted[index].end = nextStart
            }
        }
        return sorted
    }
}
