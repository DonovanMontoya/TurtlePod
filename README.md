# TurtlePod

TurtlePod is a greenfield iOS 18+ podcast MVP focused on RSS podcast ingestion, offline downloads, local playback, and ad auto-skip for downloaded episodes after user-enabled AI analysis.

The current implementation is a Swift package with:

- SwiftUI app shell for library, episode detail, downloads, player, and settings.
- Protocol-driven core services for feeds, downloads, playback, transcript generation, ad detection, and AI providers.
- Separate Keychain-backed API keys for OpenAI, TypeSafe, and OpenRouter.
- Fixture-backed unit tests for RSS parsing, ad range merging, AI response parsing, and playback auto-skip behavior.

Project docs:

- [DESIGN_PLAN.md](DESIGN_PLAN.md): product intent, architecture, current path layout, and implementation trajectory.
- [PROGRESS.md](PROGRESS.md): current checkpoint, implemented features, verification, and known gaps.

Run tests:

```sh
swift test
```

Generate and open the iOS project:

```sh
xcodegen generate
open TurtlePod.xcodeproj
```

Then run the `TurtlePod` scheme on an iOS Simulator.

Reference transcripts:

- Episode details now has **Reference Transcript** controls to find a publisher transcript, fetch a direct transcript URL, or import a file exported from another app.
- Supports UTF-8 VTT, SRT, Podcast Index JSON, HTML, and TXT, up to 8 MB. Saved references are available offline.
- Analysis automatically checks RSS transcript links when no reference has been imported. Existing saved feeds get their metadata refreshed without losing downloads.
- **Analyze Download** transcribes the actual audio and compares its words with the reference. **Re-analyze Ads** reuses the existing audio transcript, including after importing a reference.
- Possible inserted sections are shown separately from confirmed ads. Classification checks all content, including host-read sponsors present in the reference. Skip times always come from the downloaded audio.

This implementation still transcribes the full download. It uses text alignment, not Pocket Casts' audio fingerprint service. Pocket Casts generated-transcript access returned HTTP 403 in a live check; automatic access to that service is not implemented. Exported transcripts and accessible publisher URLs work independently. See [transcript implementation notes](docs/reference-transcripts.md). My Favorite Murder works through public publisher transcripts; [MFM Minisode 504 was tested against a full audio download](docs/mfm-transcript-test.md).

Ad detection can use OpenAI, Apple On-Device, or Jev 1.13 through TypeSafe or OpenRouter. Set **Local Whisper** for transcription and a **Jev** route for classification to keep hosted model costs to Jev only. Each Jev route requires its own API key in Settings. Jev sees transcript text; the app computes skip times from audio transcription cues and refines candidate passages cue by cue. The MFM Minisode 504 audio transcript exercises both routing and timestamp handling with a mocked Jev response in the portable tests. Live Jev accuracy and end-to-end cost still need a service key and a labeled evaluation set.

On Linux, run the portable core checks with Docker:

```sh
python3 scripts/test-portable-core.py
```

That harness tests production parsing, fetching, alignment, classification, persistence models, and skip logic with Apple audio APIs stubbed. Full `swift test` and the iOS build require macOS/Xcode; the GitHub Actions workflow runs both on macOS.
