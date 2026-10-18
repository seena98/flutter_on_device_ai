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
* **Fallback adapters** for devices without an OS model: `OnDeviceAiFallbackAdapter` and a runner-agnostic (built for `flutter_edge_ai`) `EdgeAiFallbackAdapter`. Fallback works for sessions, streaming, tools and schemas, not only one-shot calls.
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
