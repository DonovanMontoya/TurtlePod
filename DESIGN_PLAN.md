# TurtlePod Design Plan

## Product Intent

TurtlePod is an iOS 18+ podcast app MVP for users who want RSS-based podcast playback, offline episode downloads, and automatic ad skipping for downloaded episodes.

The app starts intentionally small:

- Users add podcasts by RSS feed URL.
- Episodes are downloaded before AI analysis.
- AI analysis is opt-in and uses the user's own OpenAI API key.
- Transcripts and detected ad ranges are cached locally.
- Playback automatically skips detected ad segments and offers undo.
- No backend, accounts, podcast search, sync, or recommendation system is included in v1.

The project should move from a private prototype toward a TestFlight-ready beta without changing the core architecture. The current code is a Swift package that establishes the domain model, service boundaries, SwiftUI shell, and local tests. The next major milestone is keeping the generated iOS app target healthy and verifying the core flows in the iOS Simulator.

## Current Repository Layout

```text
TurtlePod/
  Package.swift
  project.yml
  README.md
  PROGRESS.md
  DESIGN_PLAN.md
  Sources/
    TurtlePodApp/
      TurtlePodApp.swift
      TurtlePodModel.swift
      RootView.swift
      LibraryView.swift
      EpisodeDetailView.swift
      DownloadsView.swift
      PlayerView.swift
      SettingsView.swift
      TextInputStyles.swift
    TurtlePodCore/
      Models.swift
      Protocols.swift
      RSSPodcastFeedService.swift
      FileEpisodeDownloadService.swift
      AVPlayerPlaybackService.swift
      JSONEpisodeStore.swift
      KeychainOpenAIKeyStore.swift
      OpenAIProvider.swift
      AIAnalysisPipeline.swift
      AudioChunker.swift
      AdSegmentUtilities.swift
      Resources/
  Tests/
    TurtlePodCoreTests/
      Fixtures/
      RSSFeedParserTests.swift
      OpenAIProviderParsingTests.swift
      AdSegmentMergerTests.swift
      AutoSkipControllerTests.swift
```

## Architecture

TurtlePod uses a protocol-driven SwiftUI architecture so the core app behavior can be tested independently from real network, file, AI, and playback systems.

Primary service boundaries:

- `PodcastFeedService`: fetches and parses RSS feeds.
- `EpisodeDownloadService`: downloads episode audio into app-managed storage.
- `PlaybackService`: wraps playback, current episode, current time, play, pause, and seek.
- `TranscriptService`: creates timestamped transcripts from downloaded audio.
- `AdDetectionService`: classifies transcript windows into ad or non-ad ranges.
- `AIProvider`: abstracts OpenAI now and future providers later.
- `EpisodeStore`: persists feeds, episodes, settings, transcript chunks, ad segments, and skip events.
- `APIKeyStore`: stores the OpenAI API key outside normal app persistence.

Current concrete implementations:

- `RSSPodcastFeedService`
- `FileEpisodeDownloadService`
- `AVPlayerPlaybackService`
- `JSONEpisodeStore`
- `KeychainOpenAIKeyStore`
- `OpenAIProvider`
- `DefaultTranscriptService`
- `DefaultAdDetectionService`
- `EpisodeAnalysisPipeline`
- `AutoSkipController`

## Persistence Model

Local persistence should keep AI results as deterministic stored artifacts so repeated playback does not reprocess the same episode.

Stored episode analysis data includes:

- Episode id.
- Transcript chunks with start and end timestamps.
- Detected ad ranges with start, end, confidence, reason, provider, and model.
- Provider metadata.
- Analysis status.
- Error state.

Current storage is JSON through `JSONEpisodeStore`. This is acceptable for the prototype. A future beta may move to SwiftData or SQLite behind the same `EpisodeStore` boundary if query complexity grows.

## User Flow

The intended MVP flow:

1. Open the Library.
2. Add a podcast by RSS feed URL.
3. Browse parsed episodes.
4. Download an episode.
5. Enable AI analysis in Settings.
6. Save a user-provided OpenAI API key in Keychain.
7. Analyze the downloaded episode.
8. Store transcript chunks and detected ad ranges locally.
9. Play the downloaded episode.
10. Auto-skip detected ad ranges during playback.
11. Use the undo banner to return to the skipped position if needed.

## Playback And Auto-Skip

Playback is intentionally based on downloaded files for the MVP. AI analysis is restricted to downloaded episodes.

Auto-skip behavior:

- Observe playback time.
- Check whether the current time is inside a detected ad segment.
- Require the segment confidence to meet the configured threshold.
- Respect the global auto-skip setting.
- Respect the per-episode auto-skip setting.
- Seek to the segment end.
- Store a local skip event.
- Show a temporary undo affordance.
- Undo seeks back to the skipped-from time.

The player UI should keep visible timeline markers for detected ad ranges so auto-skip is inspectable and not invisible behavior.

## AI Flow

OpenAI is the first AI provider.

MVP rules:

- Never send audio until the user enables AI analysis and provides an API key.
- Store the API key only in Keychain.
- Analyze only downloaded episodes.
- Chunk downloaded audio into bounded segments before transcription.
- Transcribe audio chunks with timestamp support.
- Offset chunk-local transcript timestamps back to episode-level time.
- Classify transcript windows into ad ranges.
- Merge adjacent or overlapping ad ranges.
- Cache all transcripts and ad markers locally.

Current default provider choices:

- Transcription: `gpt-4o-mini-transcribe`
- Classification: small OpenAI text model behind the `AIProvider` abstraction.

Future Apple path:

- Add `AppleFoundationModelsProvider` behind `AIProvider`.
- Use Apple Foundation Models for transcript-based classification where available.
- Keep OpenAI or manual markers as fallback when Apple Intelligence is unavailable, disabled, or unsupported.
- Do not assume Apple Foundation Models can replace speech-to-text unless Apple ships an appropriate local audio transcription path.

## UI Scope

Current SwiftUI shell:

- `LibraryView`: RSS feed entry and parsed episodes.
- `EpisodeDetailView`: episode metadata, download controls, analysis controls, ad markers, per-episode auto-skip.
- `DownloadsView`: downloaded episodes.
- `PlayerView`: offline playback controls, elapsed time, ad timeline markers, skip evaluation loop.
- `SettingsView`: AI enablement, OpenAI key entry, global auto-skip, confidence threshold.

The first screen should remain the usable app experience, not a landing page.

## Testing Strategy

Prioritize local deterministic tests over live network or live AI tests.

Current tests cover:

- RSS parser behavior using a static XML fixture.
- OpenAI transcription response parsing.
- OpenAI classification response parsing.
- Ad segment merging.
- Auto-skip when entering an ad range.
- Auto-skip disabled.
- Already-past ad ranges.
- Undo after skip.

Planned next tests:

- Download service tests with mocked `URLProtocol` responses.
- Transcript service tests with a fake `AIProvider` and fake `AudioChunker`.
- Store migration/round-trip tests.
- App model tests for add feed, download, analyze, and settings persistence.
- Integration test with a local sample audio file and canned transcript.

## Trajectory

### Phase 1: Simulator-Ready App

Goal: make TurtlePod launchable in the iOS Simulator through Xcode.

Status: implemented. The repo includes `project.yml`, generated Info.plists, and `TurtlePod.xcodeproj`. The `TurtlePod` scheme builds for the available iPhone simulator, and the app has been installed and launched with `simctl`.

Completed work:

- Add a dedicated iOS `.xcodeproj` or app target.
- Wire bundle id, app icon placeholders, Info.plist settings, and signing defaults.
- Ensure `TurtlePodApp` runs as a real iOS app target.

Remaining work:

- Verify RSS add, settings persistence, download controls, and local UI navigation inside the running simulator.

### Phase 2: Core Podcast Flow

Goal: make the non-AI podcast experience reliable.

Work:

- Improve RSS compatibility across common podcast feeds.
- Add granular download progress.
- Add download cancellation and deletion polish.
- Improve local file naming and storage cleanup.
- Add basic playback queue behavior.
- Add Now Playing metadata and remote command center controls.
- Add background audio mode.

### Phase 3: AI Analysis Flow

Goal: make ad detection usable and inspectable for private beta testing.

Work:

- Harden audio chunk export across common podcast formats.
- Add retry and failure states for transcription/classification.
- Add visible transcript/ad marker inspection.
- Add manual correction controls for false positives and missed ads.
- Add cost and privacy warnings before first analysis.
- Add live API smoke testing guarded by developer-only configuration.

### Phase 4: Auto-Skip Beta

Goal: make auto-skip behavior trustworthy.

Work:

- Improve confidence threshold tuning.
- Add per-show or per-feed auto-skip defaults.
- Persist skip history for debugging.
- Add better undo timing and repeated-skip handling.
- Add safeguards around very short segments and episode intros/outros.

### Phase 5: Provider Expansion

Goal: support local or alternate AI providers without rewriting the app.

Work:

- Add `AppleFoundationModelsProvider` for transcript classification where supported.
- Add provider availability checks.
- Add fallback provider selection.
- Keep transcription, classification, and marker storage provider-neutral.

### Phase 6: Product Expansion

Goal: add features only after the RSS/download/playback/skip loop is stable.

Possible work:

- Podcast search.
- Subscriptions.
- Import/export OPML.
- Cross-device sync.
- Accounts.
- Recommendations.
- Backend-backed sync.

These remain out of scope for v1.

## App Store And Privacy Considerations

Before broader distribution:

- Add clear disclosure that audio/transcripts may be sent to OpenAI only when AI analysis is enabled.
- Explain that the user supplies their own OpenAI API key.
- Provide controls to delete transcripts and ad analysis data.
- Provide controls to delete downloaded audio.
- Add privacy manifest and permission strings as needed.
- Validate background audio behavior against App Store requirements.

## References

- Apple Foundation Models framework: https://developer.apple.com/documentation/FoundationModels
- Apple Foundation Models overview: https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models
- OpenAI speech-to-text guide: https://platform.openai.com/docs/guides/speech-to-text
- OpenAI audio overview: https://platform.openai.com/docs/guides/audio/quickstart
- OpenAI models: https://developers.openai.com/api/docs/models
