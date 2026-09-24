import Foundation

public enum PodcastFeedMerger {
    /// Refresh metadata without orphaning downloads, analysis, or imported transcripts.
    public static func merge(_ incoming: PodcastFeed, into saved: PodcastFeed) -> PodcastFeed {
        var result = incoming
        result.id = saved.id
        var remaining = saved.episodes
        result.episodes = incoming.episodes.map { fresh in
            var episode = fresh
            episode.feedID = saved.id
            let match = remaining.firstIndex {
                if let guid = fresh.guid, !guid.isEmpty, $0.guid == guid { return true }
                return $0.audioURL == fresh.audioURL
            }
            if let match {
                let old = remaining.remove(at: match)
                episode.id = old.id
                episode.download = old.download
                episode.analysis = old.analysis
                episode.autoSkipEnabled = old.autoSkipEnabled
                episode.referenceTranscript = old.referenceTranscript
            }
            return episode
        }
        result.episodes += remaining
        return result
    }
}
