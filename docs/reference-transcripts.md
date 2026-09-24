# Reference transcripts

## Sources and Pocket Casts investigation

Pocket Casts displays publisher transcripts from the RSS `podcast:transcript` tag and generates its own transcripts for selected shows. Generated transcripts are a Plus/Patron feature. Its app can export transcript text through Share. See [Pocket Casts transcript support](https://support.pocketcasts.com/knowledge-base/episode-transcripts/) and the [Podcast Namespace specification](https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/1.0.md#transcript).

The open-source iOS client at commit `00dbbabe5033d118757b191d3ac9569f0c66ea27` constructs generated transcript URLs at `https://shownotes.pocketcasts.com/generated_transcripts/{podcastUUID}/{episodeUUID}.vtt`, then fetches them with URLSession. It also fetches reference audio fingerprints to map playback time onto a reference timeline:

- [Transcript URL construction](https://github.com/Automattic/pocket-casts-ios/blob/00dbbabe5033d118757b191d3ac9569f0c66ea27/podcasts/Episode%20Info%20Coordinator/ShowInfoCoordinator.swift)
- [Transcript downloader](https://github.com/Automattic/pocket-casts-ios/blob/00dbbabe5033d118757b191d3ac9569f0c66ea27/podcasts/TranscriptsDataRetriever.swift)
- [Fingerprint timing manager](https://github.com/Automattic/pocket-casts-ios/blob/00dbbabe5033d118757b191d3ac9569f0c66ea27/podcasts/Fingerprint/FingerprintTimingManager.swift)

Live check on September 7, 2026: Pocket Casts' metadata endpoint returned The Vergecast episode “AGI is whatever you want it to be,” episode UUID `de1789c1-2b2d-4734-afbd-75a581be7c16`, marked as having a generated transcript. Its generated VTT endpoint returned HTTP 403. This establishes an access failure for that request, not universal unavailability or a supported third-party API. [Pocket Casts says it has no public API](https://support.pocketcasts.com/knowledge-base/pocket-casts-api/).

A separate live check fetched the publisher transcript linked from `https://changelog.com/podcast/feed` for “All the Claw things (News)” at `https://changelog.com/news/181/transcript`: HTTP 200, 7,636 bytes of HTML. The production Swift parser successfully extracted its text in a smoke check. This checks retrieval/parsing, not ad-detection accuracy on real audio.

TurtlePod does not scrape episode sharing pages or bypass access checks. Direct transcript URLs are fetched normally and 401/403 errors are displayed. Publisher transcripts and user-imported exports provide independent sources. No Pocket Casts implementation code or transcript content was copied into this repository.

The requested My Favorite Murder check succeeded through publisher sources. **MFM Minisode 504** exposes public SRT, VTT, and TXT transcripts. Fetching/parsing all three and comparing them with a local transcription of the full downloaded audio succeeded. The test also led to SRT MIME/content detection fixes and a preference for VTT. See [full episode test results](mfm-transcript-test.md).

## Implemented flow

1. Discover RSS transcript URLs and preserve episode GUIDs. Refreshing a feed merges metadata while retaining episode IDs, downloaded audio, analysis, and imported references. Matching uses GUID or exact enclosure URL, not episode title.
2. Fetch a publisher reference automatically during analysis, or let the user select a direct URL/file in episode details. Persist cleaned text with its source and fetch date. Failed reference retrieval leaves audio analysis available.
3. Transcribe the downloaded audio using the configured provider. Reference timestamps are deliberately discarded; they cannot safely describe a dynamically stitched download.
4. Align unique five-word phrases in order between actual audio transcription and reference text. Require at least 30 matched words and 45% word coverage on both sides. Cues with under 20% matched words and at least five words become possible insertions only when that global check succeeds.
5. Classify the full actual-audio transcript in roughly five-minute/12,000-character windows with one cue of overlap. Windows overlapping reference candidates are checked first. No matching content is exempted: a host-read sponsor can occur in both versions. Bounds are at cue granularity, so individual long cues can exceed the nominal window budget.
6. Only classifier-confirmed, finite ranges within a window's downloaded-audio timestamps become skip markers. Reference candidates remain informational. Reject untimed audio transcripts instead of creating unsafe skip markers.

The first pass still transcribes all audio and classifies all text. This is not an implementation of sparse transcription, forced audio alignment, or fingerprint-based ad detection, and makes no transcription-cost reduction claim. Text mismatches can also be corrections, omitted editorial material, or recognition errors. The comparison does not prove that a reference is ad-free or that a gap is an ad.

## Related reliability fixes

- Preserve saved state on feed refresh and upgrade legacy feeds with transcript metadata.
- Prevent conflicting download, analysis, deletion, and import operations for one episode.
- Reset interrupted work to a retryable state at app launch.
- Clear old analysis before a fresh download because inserted ads may change.
- Use the recovered local audio path when starting analysis.
- Read current library ad markers and auto-skip settings during playback, and unload a deleted playing episode.
- Remove all exported audio chunks after transcription failure/cancellation; use unique filenames and clean partial exports.
- Report transcription progress after each chunk finishes.

## Verification

`python3 scripts/test-portable-core.py` runs production portable core sources under Swift 6.0 in Docker with explicit stubs for Apple-only audio APIs. Tests cover fetching and access errors, format parsing, namespace aliases, old JSON compatibility, feed merging, shifted audio timelines, wrong references, repeated text, reference gaps that are not ads, complete classifier coverage, invalid ranges, and temporary-file cleanup.

macOS `swift test` and an iOS simulator build are configured in `.github/workflows/swift.yml`. They were not run in this Linux workspace. The checked-in Xcode project includes the new source files; XcodeGen can also regenerate it from `project.yml`.
