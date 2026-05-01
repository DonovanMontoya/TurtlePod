# TurtlePod

TurtlePod is a greenfield iOS 18+ podcast MVP focused on RSS podcast ingestion, offline downloads, local playback, and ad auto-skip for downloaded episodes after user-enabled AI analysis.

The current implementation is a Swift package with:

- SwiftUI app shell for library, episode detail, downloads, player, and settings.
- Protocol-driven core services for feeds, downloads, playback, transcript generation, ad detection, and AI providers.
- Keychain-backed OpenAI API key storage.
- Fixture-backed unit tests for RSS parsing, ad range merging, AI response parsing, and playback auto-skip behavior.

Project docs:

- [DESIGN_PLAN.md](DESIGN_PLAN.md): product intent, architecture, current path layout, and implementation trajectory.
- [PROGRESS.md](PROGRESS.md): current checkpoint, implemented features, verification, and known gaps.

Run tests:

```sh
swift test
```

Open the package in Xcode for code browsing and tests. A dedicated iOS `.xcodeproj` app target still needs to be added before the app can be launched directly in the iOS Simulator.
