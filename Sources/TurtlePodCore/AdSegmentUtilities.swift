import Foundation

public enum AdSegmentMerger {
    public static func merge(_ segments: [AdSegment], gapTolerance: TimeInterval = 2) -> [AdSegment] {
        let sorted = segments
            .filter { $0.end > $0.start }
            .sorted { lhs, rhs in
                if lhs.start == rhs.start { return lhs.end < rhs.end }
                return lhs.start < rhs.start
            }

        return sorted.reduce(into: []) { merged, segment in
            guard var last = merged.last else {
                merged.append(segment)
                return
            }

            if segment.start <= last.end + gapTolerance {
                last.end = max(last.end, segment.end)
                last.confidence = max(last.confidence, segment.confidence)
                if !segment.reason.isEmpty, !last.reason.contains(segment.reason) {
                    last.reason = [last.reason, segment.reason].filter { !$0.isEmpty }.joined(separator: " ")
                }
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
    }
}

public actor AutoSkipController {
    private let playback: PlaybackService
    private let store: EpisodeStore?
    private var skippedSegmentIDs: Set<UUID> = []
    private var lastSkip: SkipEvent?

    public init(playback: PlaybackService, store: EpisodeStore? = nil) {
        self.playback = playback
        self.store = store
    }

    public func resetForNewEpisode() {
        skippedSegmentIDs.removeAll()
        lastSkip = nil
    }

    @discardableResult
    public func evaluate(
        episode: PodcastEpisode,
        currentTime: TimeInterval,
        globalAutoSkipEnabled: Bool,
        confidenceThreshold: Double
    ) async throws -> SkipEvent? {
        guard globalAutoSkipEnabled, episode.autoSkipEnabled else { return nil }

        guard let segment = episode.analysis.adSegments.first(where: { segment in
            segment.confidence >= confidenceThreshold
                && !skippedSegmentIDs.contains(segment.id)
                && currentTime >= segment.start
                && currentTime < segment.end
        }) else {
            return nil
        }

        await playback.seek(to: segment.end)
        skippedSegmentIDs.insert(segment.id)

        let event = SkipEvent(
            episodeID: episode.id,
            skippedFrom: currentTime,
            skippedTo: segment.end,
            segmentID: segment.id
        )
        lastSkip = event
        try await store?.appendSkipEvent(event)
        return event
    }

    public func undoLastSkip() async {
        guard let lastSkip else { return }
        await playback.seek(to: lastSkip.skippedFrom)
        self.lastSkip = nil
    }
}
