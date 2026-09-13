#!/usr/bin/env python3
"""Exercise production portable Swift code on Linux; does not validate Apple APIs/UI.
Requires Docker. Apple-only audio implementations are replaced by throwing stubs;
tests explicitly inject fake chunkers/transcribers where needed.
"""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sources = ["Models", "Protocols", "EpisodeDescriptionCleaner", "RSSPodcastFeedService",
           "ReferenceTranscript", "ReferenceTranscriptAlignment", "PodcastFeedMerger",
           "AIAnalysisPipeline", "AdSegmentUtilities", "JSONEpisodeStore"]
tests = ["ReferenceTranscriptTests", "ReferenceAlignmentTests", "ReferenceHTTPTests",
         "RSSFeedParserTests", "EpisodeDescriptionCleanerTests", "AppSettingsMigrationTests",
         "AdSegmentMergerTests", "AutoSkipControllerTests"]
with tempfile.TemporaryDirectory(prefix="turtlepod-swift-tests-") as directory:
    stage = Path(directory)
    code = stage / "Sources/TurtlePodCore"
    suite = stage / "Tests/TurtlePodCoreTests"
    code.mkdir(parents=True)
    suite.mkdir(parents=True)
    (stage / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TurtlePodPortable", targets: [
    .target(name: "TurtlePodCore"),
    .testTarget(name: "TurtlePodCoreTests", dependencies: ["TurtlePodCore"], resources: [.process("Fixtures")])
])
''')
    for name in sources:
        text = (root / f"Sources/TurtlePodCore/{name}.swift").read_text()
        imports = "import FoundationNetworking\nimport FoundationXML\n"
        (code / f"{name}.swift").write_text(imports + text)
    chunker = (root / "Sources/TurtlePodCore/AudioChunker.swift").read_text()
    chunker = chunker.split("public struct AVAssetAudioChunker:")[0].replace("import AVFoundation\n", "")
    (code / "PlatformStubs.swift").write_text(chunker + '''
public typealias OSStatus = Int32
public struct AVAssetAudioChunker: AudioChunker {
    public init() {}
    public func chunks(for audioFile: URL, maxDuration: TimeInterval) async throws -> [AudioChunk] {
        throw TurtlePodError.unsupportedResponse
    }
}
''')
    playback = (root / "Sources/TurtlePodCore/AVPlayerPlaybackService.swift").read_text()
    (code / "FakePlaybackService.swift").write_text("import Foundation\npublic actor FakePlaybackService:" + playback.split("public actor FakePlaybackService:")[1])
    for name in tests:
        (suite / f"{name}.swift").write_text((root / f"Tests/TurtlePodCoreTests/{name}.swift").read_text())
    import shutil
    shutil.copytree(root / "Tests/TurtlePodCoreTests/Fixtures", suite / "Fixtures")
    subprocess.run(["docker", "run", "--rm", "--network=none", "--user", f"{os.getuid()}:{os.getgid()}",
                    "-v", f"{stage}:/package", "-w", "/package", "swift:6.0", "swift", "test", "-j", "4"], check=True)
