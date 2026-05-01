# TurtlePod Progress

## Current State

TurtlePod has been bootstrapped as a Swift package plus a generated Xcode iOS project for an iOS 18+ podcast MVP. The repo now contains a testable core library, a SwiftUI app shell, local persistence, OpenAI integration plumbing, offline download support, playback abstractions, deterministic tests, and an iOS Simulator-buildable app target.

This is an early MVP implementation. The main architecture and core flows are in place, and the `TurtlePod` scheme now builds, installs, and launches on the available iPhone simulator.

## Implemented

- Swift package structure with `TurtlePodCore`, `TurtlePodApp`, and `TurtlePodCoreTests`.
- XcodeGen project configuration in `project.yml`.
- Generated `TurtlePod.xcodeproj` with a `TurtlePod` iOS app target and `TurtlePodCore` framework target.
- SwiftUI screens for Library, Episode Detail, Downloads, Player, and Settings.
- RSS feed ingestion from a user-entered feed URL.
- RSS parsing for feed title, artwork, episode title, audio enclosure URL, duration, publish date, and description.
- Local JSON persistence for feeds, episodes, settings, skip events, transcript data, ad markers, and analysis state.
- Offline episode download service that stores audio in app-managed storage.
- AVFoundation-backed playback service for downloaded files.
- Settings for AI enablement, OpenAI API key entry, global auto-skip, and confidence threshold.
- OpenAI API key storage through iOS Keychain.
- AI provider abstraction with OpenAI as the first provider.
- OpenAI transcription request plumbing using `gpt-4o-mini-transcribe`.
- OpenAI transcript classification plumbing using a small text model.
- AVFoundation audio chunking before transcription so long downloads can be processed in bounded segments.
- Transcript and detected ad segment storage models.
- Ad segment merging for overlapping or adjacent ranges.
- Auto-skip controller that seeks over detected ad ranges during playback.
- Undo support for the most recent automatic skip.
- Timeline markers for detected ad segments in the player UI.
- Fixture-backed tests for RSS parsing, OpenAI response parsing, ad segment merging, and playback skip behavior.

## Current Functionality

The app code supports this intended flow:

1. Add a podcast by RSS feed URL.
2. Browse parsed episodes in the Library.
3. Download an episode for offline playback.
4. Enable AI analysis and save a user-provided OpenAI API key.
5. Analyze a downloaded episode.
6. Store transcript chunks and detected ad ranges locally.
7. Play the downloaded episode.
8. Auto-skip detected ad ranges above the configured confidence threshold.
9. Undo the most recent skip from the temporary banner.

## Verification

The local SwiftPM test suite passes:

```sh
swift test
```

The generated Xcode project builds for the available iPhone simulator:

```sh
xcodegen generate
xcrun simctl list devices available
xcodebuild -project TurtlePod.xcodeproj -scheme TurtlePod -sdk iphonesimulator -destination 'id=<available-simulator-id>' CODE_SIGNING_ALLOWED=NO build
```

The built app was also installed and launched with `simctl` using bundle id `com.turtlepod.app`.

Current coverage includes:

- RSS parser tests using a static XML fixture.
- OpenAI transcription and classification response parsing tests.
- Ad segment merge tests.
- Auto-skip tests for entering an ad range, disabled auto-skip, already-past ranges, and undo.

## Known Gaps

- In-app simulator smoke testing still needs to be completed for RSS entry, settings persistence, downloads, and playback.
- Download progress is modeled, but the current implementation reports completion rather than streaming granular progress updates.
- OpenAI network calls are implemented but not covered by live API tests.
- Background audio, Now Playing metadata, and remote command center controls are not implemented.
- Podcast search, subscriptions sync, accounts, recommendations, cross-device sync, and backend services are out of scope for this MVP.
- Apple Foundation Models support is not implemented yet; the provider abstraction leaves room for it later.
