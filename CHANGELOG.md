## 0.3.0

* **Embeddings and RAG, fully on device.** `OnDeviceAiEmbedder` contract, `LocalEmbedder` (GGUF embedding model through llama.cpp, default BGE small, about 36 MB, with `presets`), `InMemoryVectorStore` (cosine search, JSON save/load), `RagIndex` (`addDocument`, `search`, `contextFor`, `toJson`/`fromJson`) and `chunkText`. `RagIndex.asTool()` lets a session retrieve on its own.
* **Image input on the local fallback.** `LocalLlmFallbackAdapter(projector: ...)` / `FlutterDeviceAi.withLocalModel(projector: ...)` load a vision GGUF with its mmproj; `session.addImage` works and `capabilities().imageInput` reports it. `LocalLlmFallbackAdapter.visionPresets` lists SmolVLM 500M. `OnDeviceAiFallbackAdapter.supportsImages` and `FallbackMessage.images` added for custom adapters.
* **Offline speech-to-text.** `LocalSpeechToText` runs Qwen3-ASR locally (`transcribeFile`, `transcribeBytes`, `presets`).
* `FakeOnDeviceAiEmbedder` in `testing.dart`.
* Example app: new Docs tab (search your own notes, then answer from the best matches); `ExampleApp(embedder:)` is injectable. The demo GIF now includes it.
* Example integration test downloads the embedding model and checks semantic search.

## 0.2.0

* **Built-in local fallback model.** `FlutterDeviceAi.withLocalModel()` / `LocalLlmFallbackAdapter` run a real open GGUF (or `.litertlm`) model with llama.cpp through `llamadart` when the OS has no model. `prepare()` downloads it. `OnDeviceAiFallbackAdapter.prepare()` added.
* **Breaking:** `EdgeAiFallbackAdapter` is now `CallbackFallbackAdapter`; `OnDeviceAiBackend.fallbackEdgeAi` is now `OnDeviceAiBackend.fallback`. The plugin no longer refers to `flutter_edge_ai`.
* **Breaking:** minimums raised to Flutter 3.38 / Dart 3.10.7, iOS 16.4, macOS 14 (llama.cpp). Apps need Swift Package Manager enabled on iOS and macOS (the llama.cpp companion is SwiftPM-only), so CocoaPods-only apps must migrate. The plugin manifest declares `INTERNET` on Android.
* Local fallback quality: conversations use the model's own chat template through structured `FallbackMessage`s (`OnDeviceAiFallbackAdapter.generateChat` / `generateChatStream`, default renders a transcript), and JSON-schema answers are grammar-constrained. The emulated tool prompt now includes a worked example.
* Local fallback downloads and storage: resumable downloads with retries, optional `sha256`, `allowDownload` hook (for example Wi-Fi only), `cancelPrepare()`, typed errors for network and disk failures, `status` stream (`idle`, `downloading`, `loading`, `ready`, `unloaded`), `isDownloaded()`, `deleteModel()`, `presets` and `recommendedFor(ramGb)`.
* Local fallback memory: `idleUnloadAfter` and `unload()` release the model from RAM; the next request reloads it from disk without downloading.
* Failover: a session on the OS model that reports `unavailable` mid-use moves to the fallback and answers the turn there.
* Android: ML Kit `GenAiException` codes map to `CANCELLED`, `SESSION_BUSY`, `UNAVAILABLE`, `UNSUPPORTED`.
* Generated UI: table rows from small models are padded or trimmed to the header width, fixing a `DataTable` assertion.
* Example app: local model picker (presets or any GGUF), live download/load status, cancel and delete buttons, 5-minute idle unload, the real fallback instead of the echo stub, macOS network entitlement, and an integration test that downloads and runs a real local model.
* Docs: README, `llms.txt` and the routing diagram describe the local fallback.
* Apple: availability now probes the model once with a tiny generation, so a missing or unusable model (for example the iOS simulator on a Mac without Apple Intelligence, ModelManager error 1026) is reported as unavailable and routes to the fallback adapter. ModelManager errors map to `UNAVAILABLE`.

## 0.1.1

* Swift Package Manager support on iOS and macOS (CocoaPods still works). Sources now live in `ios|macos/flutter_device_ai/Sources/flutter_device_ai`.
* Shorter pubspec description for pub.dev search.

## 0.1.0

Package renamed to `flutter_device_ai` (pub.dev rejected `flutter_on_device_ai` as too similar to an existing package). Import `package:flutter_device_ai/flutter_device_ai.dart`; the facade class is `FlutterDeviceAi`.

First public release.

### Engines
* **Apple Foundation Models** on iOS and macOS 26+: text, streaming, cancellation, native tool calling, schema-constrained output.
* **Gemini Nano on Android** through the ML Kit GenAI Prompt API: text, streaming, cancellation, image input, exact token counts, model download with progress, Play Store redirect for Google AICore.
* **Chrome / Edge built-in AI** on the web through the Prompt API: text, streaming, cancellation, native `responseConstraint` schemas, exact token counts, download with progress and user-gesture detection.
* **Fallback adapters** for devices without an OS model: `OnDeviceAiFallbackAdapter` and `EdgeAiFallbackAdapter` (later renamed `CallbackFallbackAdapter`). Fallback works for sessions, streaming, tools and schemas, not only one-shot calls.
* Windows and Linux report `unavailable` and route to the fallback adapter.

### API
* `FlutterDeviceAi`: `generateText`, `generateTextStream`, `generateTextSimple`, `createSession`, `availability`, `isAvailable`, `capabilities`, `getPlatformInfo`, `prepare` / `ensureReady`, `downloadModel`, `openAICorePlayStore`, `initialize`, `registerTools`.
* `OnDeviceAiSession`: concurrent isolated sessions, multi-part turns, `ask` / `askStream`, `countTokens`, real `stopGeneration`, busy detection.
* **Emulated tool calling** for backends without native tools, with argument validation and a bounded round-trip loop (also while streaming).
* **Structured output** with a built-in JSON Schema validator, lenient JSON extraction (fences, prose, truncation) and automatic validate-and-repair.
* `OnDeviceAiCapabilities` reports each feature as native, emulated or unavailable.
* `OnDeviceAiAvailability` carries a status, a machine-readable reason and a UI-ready message.
* Typed exception hierarchy under `OnDeviceAiException`.
* Generative UI: `OnDeviceUiGenerator`, `GenUiModuleSpec` with eight validated block types (`stat`, `progress`, `checklist`, `list`, `steps`, `table`, `callout`, `note`), localisation, streaming progress and tool support.
* `package:flutter_on_device_ai/testing.dart` with `FakeOnDeviceAiPlatform`.

### Tooling
* 60+ unit tests, a browser test suite for the web backend, and a device integration test that exercises the real model and skips itself where none exists.
* CI builds Android, iOS, macOS, web, Linux and Windows example apps.
* `llms.txt` and `AGENTS.md` for AI assistants.

### Not yet
* Windows AI Foundry (Phi Silica) backend.
* Image input on Apple platforms and on the web.
* Exact token counts on Apple platforms.
