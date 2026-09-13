# My Favorite Murder transcript check

Tested September 7, 2026 using **MFM Minisode 504**, published that day.

## Source identification

- [Publisher RSS feed](https://www.omnycontent.com/d/playlist/e73c998e-6e60-432f-8610-ae210140c5b1/bdde8bb3-169d-43b1-91d3-b24c0047969c/f450d41f-16bc-4ecd-8f6c-b24c004796e2/podcast.rss)
- RSS episode GUID: `bbd10e19-040e-4d30-9961-b4bb010b225e`
- Pocket Casts podcast UUID: `56c11920-9d5d-0133-2dcb-6dc413d6d41d`
- Pocket Casts episode UUID: `fec204ab-832c-47b0-93c7-7737a050edbd`
- Pocket Casts episode metadata has `has_generated_transcript: false`. Its separate show-notes retrieval returned 403, so the exact transcript selection in that app was not independently confirmed.

The RSS feed returned HTTP 200 and contained 1,214 episodes. This episode has three public publisher transcript URLs; all returned HTTP 200, without Pocket Casts credentials.

| RSS format | Response type | Download size | Parsed words |
| --- | --- | ---: | ---: |
| `application/srt` | `text/plain` | 55,545 bytes | 6,306 |
| `text/vtt` | `text/vtt` | 53,232 bytes | 5,080 |
| `text/plain` | `text/plain` | 32,327 bytes | 5,776 |

The variants contain different amounts of speaker labels/timestamp text, so word counts differ. These counts do not measure transcription quality.

Direct VTT source: [Omny publisher transcript](https://api.omny.fm/orgs/e73c998e-6e60-432f-8610-ae210140c5b1/clips/bbd10e19-040e-4d30-9961-b4bb010b225e/transcript?format=WebVTT&t=1788554481).

## Fix and parsing verification

The live source exposed a parser compatibility issue: extensionless SRT URLs with RSS MIME type `application/srt` were unsupported. Direct URL imports were also served as `text/plain`, leaving subtitle timing lines in the text.

The parser now recognizes `application/srt` and `text/srt`, and recognizes subtitle timing lines when the response MIME type is misleading. A committed synthetic regression test reproduces Omny's URL/format behavior without storing copyrighted episode text.

The production Swift RSS parser and transcript parser were run on the full downloaded feed and all three actual transcript files in a temporary test harness: 33 tests passed (32 portable tests plus one real-data parsing test).

## Audio timeline

The enclosure download returned HTTP 200, 34,733,709 bytes. `ffprobe` measured **2,168.659592 seconds (36:09)**. SHA-256 for this particular download:

`6ef7fc617578e15193823d1315964629471c82341437b47dce67e7f3a3bd6204`

The VTT contains 613 cues, beginning at 16.550 seconds and ending at **1,660.680 seconds (27:41)**. The feed and Pocket Casts metadata describe approximately 1,666 seconds. The transcript's last cue is about 508 seconds before this download ends. That discrepancy alone does not identify which intervals are ads; it establishes that copying source timestamps into skip markers would be unsafe.

Raw episode audio and transcript content were kept under `/tmp/turtlepod-mfm`, not added to the repository. Subsequent downloads may have different inserted content and hashes.

## Actual-audio comparison

The full downloaded MP3 was transcribed locally with `faster-whisper` / `tiny.en`, CPU `int8`, four threads, beam size 1, and voice activity detection. It produced 779 timestamped segments in approximately 61 seconds. This was an independent Linux test transcriber, not the app's Apple/WhisperKit execution path.

The production `ReferenceTranscriptAlignment` implementation compared those actual-audio segments with the fetched references:

| Reference | Actual transcript words matched | Comparison accepted | Candidate intervals |
| --- | ---: | --- | ---: |
| SRT | 62.18% | Yes | 43 |
| VTT | 68.82% | Yes | 29 |

These percentages are lexical match coverage, not ad-detector accuracy. VTT avoids the repeated speaker-label words in SRT. TurtlePod now prefers VTT when available and retains other sources as fallbacks.

Inspection of the local ASR text in four long groups of unmatched intervals found promotional material for Southern New Hampshire University, Squarespace, Article, and SimpliSafe, roughly around 0:07–2:20, 12:36–14:31, 20:50–22:51, and 34:12–36:06. These are approximate inspection windows, **not validated skip boundaries**. Some shorter candidates were ordinary dialogue/recognition differences, including around 2:42. The existing policy—classify all actual-audio text and never automatically skip a reference gap—remains necessary.

The production `HTTPReferenceTranscriptService` was also run directly against the live Omny SRT URL in Swift and successfully returned 6,306 parsed words with subtitle timing removed.

Final test run: **35 passing tests** in the temporary live harness: 33 portable regression tests, one actual-feed/three-transcript parsing test, and one full-audio reference comparison test. Raw live content and ASR output remain in `/tmp/turtlepod-mfm`; only synthetic regression data is committed. No iOS simulator, Apple transcription/classification model, or end-to-end playback skip accuracy was tested here.
