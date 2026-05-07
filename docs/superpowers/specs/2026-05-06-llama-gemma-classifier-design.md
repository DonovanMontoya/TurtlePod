# Llama/Gemma On-Device Ad Classifier

**Date:** 2026-05-06  
**Status:** Approved

## Summary

Add a third ad classification option — Gemma 3 1B running locally via llama.cpp — alongside the existing OpenAI and Apple Foundation Models classifiers. The Apple Foundation Models classifier has poor classification quality; this provides a capable, fully on-device alternative that works on iOS 18+ and macOS 15+ without Apple Intelligence.

## Architecture

### New SPM Dependency

Add `ggml-org/llama.cpp` to `Package.swift` as a dependency, linking the `llama` Swift target into `TurtlePodCore`. This is the same underlying GGML engine that WhisperKit uses for transcription, applied to the LLM side.

### New Files in TurtlePodCore

**`LlamaModelManager.swift`** — `public actor`, singleton (`shared`).

Responsibilities:
- Owns the llama.cpp model and context lifecycle (load, unload, memory management)
- Downloads the Gemma 3 1B Q4_K_M GGUF (~620 MB) from HuggingFace on demand via `URLSession`, writing atomically to cache
- Stores model at `Application Support/TurtlePod/LlamaModels/gemma-3-1b-it-q4_k_m.gguf`
- `ensureReady() async throws` — lazy-loads the model into memory, downloading first if needed
- `classify(windows: [TranscriptClassificationWindow]) async throws -> [AdSegment]` — core inference method
- `isModelDownloaded() -> Bool`
- `deleteModel() throws`

**`LlamaAdClassifier.swift`** — `public struct`, conforms to `AdClassificationProvider`.

Responsibilities:
- `providerName = "llama"`
- `classificationModel = "gemma-3-1b-it-q4_k_m"`
- Implements `classify(transcript:apiKey:)` by windowing the transcript (via the existing `AppleFoundationModelsAdClassifier.transcriptWindows(for:windowDuration:overlap:)` public static method) then calling `LlamaModelManager.shared.classify(windows:)`
- No API key required (`apiKey` parameter unused)

### Grammar-Constrained JSON Output

`LlamaModelManager` uses llama.cpp's GBNF grammar API to constrain sampling to valid JSON matching the ad segment schema. This makes malformed output structurally impossible, eliminating the need for a fallback path. The grammar enforces:

```
{"ad_segments": [{"start": <number>, "end": <number>, "confidence": <number>, "reason": <string>}, ...]}
```

### Modified Files

**`Models.swift`**
- Add `.llama` case to `AIClassificationProviderKind` enum

**`TurtlePodModel.swift`**
- Wire `LlamaAdClassifier` into pipeline construction when `aiClassificationProvider == .llama`
- Add `selectedGemmaModelIsDownloaded: Bool` computed property
- Add `refreshSelectedGemmaModelStatus() async` method (mirrors existing Whisper equivalents)

**`SettingsView.swift`**
- Add display name for `.llama` provider: `"Gemma 3 1B"`
- When `.llama` is selected, show a status row below the picker:
  - Not downloaded: amber download icon + "Downloads on first analysis" + "~620 MB"
  - Downloaded: teal checkmark + "Model downloaded" + "~620 MB"
  - Privacy note: "Fully local — no API key required."
- Driven by `model.selectedGemmaModelIsDownloaded`, refreshed via `.task` on provider selection change

## Data Flow

```
LlamaAdClassifier.classify(transcript:apiKey:)
  → AppleFoundationModelsAdClassifier.transcriptWindows(for:...) [reused, public static]
  → LlamaModelManager.shared.classify(windows:)
      → ensureReady() — download if needed, load into memory
      → for each window:
           build prompt with transcript text
           run llama.cpp inference with GBNF JSON grammar
           parse JSON → [AdSegment]
      → return merged [AdSegment]
  → DefaultAdDetectionService calls AdSegmentMerger.merge(...) [unchanged]
```

## Model Details

| Property | Value |
|---|---|
| Model | Gemma 3 1B Instruct |
| Format | GGUF Q4_K_M quantization |
| Download size | ~620 MB |
| Source | HuggingFace (bartowski/gemma-3-1b-it-GGUF) |
| Platforms | iOS 18+, macOS 15+ |
| GPU acceleration | Metal (via llama.cpp) |
| API key required | No |

## Out of Scope

- Model size picker (single model for v1)
- Background pre-download
- Progress reporting during download (beyond existing "downloads on first analysis" UX pattern)
