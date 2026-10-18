# AGENTS.md

Guide for AI coding agents (and humans) changing this repository. Usage docs for *consumers* of the package are in `llms.txt` and `README.md`.

## What this is
`flutter_device_ai` is a Flutter plugin. Native code only does what the OS can do; everything else lives in Dart so it behaves the same on every platform.

## Layout
```
lib/flutter_device_ai.dart            public facade + exports (FlutterDeviceAi)
lib/flutter_device_ai_platform_interface.dart   small platform contract (availability, download, sessions)
lib/flutter_device_ai_method_channel.dart       Android/iOS/macOS transport; event multiplexing; tool callbacks
lib/flutter_device_ai_web.dart        Chrome Prompt API via dart:js_interop
lib/flutter_device_ai_stub.dart       Windows/Linux: reports unavailable (dartPluginClass)
lib/testing.dart                         FakeOnDeviceAiPlatform for consumers' tests
lib/src/session/                         OnDeviceAiSession (tool loop, schema repair), SessionBackend, tool_emulation
lib/src/schema/json_schema.dart          JsonSchema validator + JsonExtractor (lenient JSON recovery)
lib/src/fallback/                        adapter contract + EdgeAiFallbackAdapter
lib/src/genui/                           generated-UI spec + generator
ios|macos/flutter_device_ai/Sources/flutter_device_ai   identical Swift (SwiftPM + CocoaPods) (FoundationModels); keep the two files in sync
android/src/main/kotlin/dev/flutter_device_ai   Kotlin (ML Kit GenAI Prompt API)
example/                                 demo app + integration_test (real device)
```

## Wire protocol (native <-> Dart)
* MethodChannel `flutter_device_ai`: `getAvailability`, `getPlatformInfo`, `openAICorePlayStore`, `createSession{sessionId,systemInstruction,tools,config}`, `sessionAddQuery`, `sessionAddImage`, `sessionGetResponse`, `sessionStartStream`, `sessionCountTokens`, `sessionStopGeneration`, `sessionClose`. Native -> Dart: `onToolCall{sessionId,name,arguments}` returning `{result}` or `{error}`.
* EventChannel `flutter_device_ai/events`: one stream, events `{sessionId, type: chunk|done|error, text|code|message}`; Dart demultiplexes by `sessionId`.
* EventChannel `flutter_device_ai/download`: `{status, progress, bytesDownloaded, totalBytes, errorMessage}`, ends when finished.
* Error codes: UNAVAILABLE, UNSUPPORTED, CANCELLED, SESSION_BUSY, SESSION_NOT_FOUND, EMPTY_TURN, GENERATION_FAILED. Dart maps them in `mapPlatformException`.
* Session ids are generated in Dart.

## Rules
1. **Never ship simulated output.** If a backend cannot do something, report it in `getPlatformInfo`/`getAvailability` and throw a typed error. No canned strings, no "simulation" paths. (An earlier version had these; they were removed.)
2. A native backend reports `supportsToolCalling` / `supportsStructuredOutput` truthfully; Dart emulates what is false.
3. Platform interface changes must update: method channel, web, stub, `testing.dart`, the native layers, and tests.
4. Public API changes need a CHANGELOG entry, README update and `llms.txt` update.
5. Keep `ios/flutter_device_ai/Sources/flutter_device_ai/FlutterDeviceAiPlugin.swift` and the macos copy byte-identical.
6. FoundationModels code must stay inside `#if canImport(FoundationModels)` and `@available(iOS 26.0, macOS 26.0, *)`.

## Verify before finishing
```sh
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter test --platform chrome test/web_test.dart
cd example && flutter test && flutter build web && flutter build apk --debug \
  && flutter build macos --debug && flutter build ios --simulator --no-codesign
```
Real-model check (needs a capable device): `cd example && flutter test integration_test -d <device>`.

## Publishing
`flutter pub publish --dry-run` must report 0 warnings. Bump `pubspec.yaml`, both podspecs and `CHANGELOG.md` together.

## Demo GIF
`doc/assets/demo.gif` is a labelled *scripted* demo (see `doc/demo.md`). Never present it as a device capture. To make a real-device capture instead:
* iOS simulator / device: `xcrun simctl io booted recordVideo demo.mov` (simulators have no Apple Intelligence model; use a real iPhone 15 Pro+ with iOS 26 and QuickTime/`xcrun devicectl`).
* Android: `adb shell screenrecord /sdcard/demo.mp4 && adb pull /sdcard/demo.mp4` on a Gemini Nano device.
* Convert: `ffmpeg -i demo.mp4 -vf "fps=12,scale=360:-1" -loop 0 doc/assets/demo.gif` (or `gifski`). Keep it under ~5 MB and reference it from the README.
