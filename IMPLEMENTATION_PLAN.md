# `flutter_on_device_ai` Implementation Plan

A comprehensive, production-grade Flutter plugin for OS-managed, on-device Generative AI across all platforms (**iOS, macOS, Android, Windows, Web, and Linux**).

---

## 1. Package Name & Architecture

**Package Name:** `flutter_on_device_ai`  
**Core Advantage:** Zero-checkpoint app bundle. Directly utilizes OS-managed and browser-native models with zero server costs, low latency, and 100% privacy.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   flutter_on_device_ai (Public API)                    │
│   • One-Shot Facade (generateText, stream, genUI)                      │
│   • Stateful Session API (Multi-turn, Tool Calls, Cancellation)        │
│   • Smart Fallback Engine (Seamless flutter_gemma integration)         │
│   • Capabilities & Diagnostic Doctor (Token Count, Hardware Probe)     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
               flutter_on_device_ai_platform_interface
        ┌───────────────────┬───────┴───────────┬───────────────────┐
        ▼                   ▼                   ▼                   ▼
   [ Android ]         [ Apple ]            [ Windows ]       [ Web (Chrome) ]
• ML Kit GenAI /     • Foundation Models   • Windows AI      • Prompt API
  Gemini Nano          (iOS/macOS 26+)       Foundry (WinRT)   (`window.ai`)
• AICore Resolver    • Tool Calling &      • Structured      • AbortController
  & Model Downloader   JSON Schema           JSON Output     • Streams & Quotas
        │                   │                   │                   │
        └───────────────────┼───────────────────┴───────────────────┘
                            ▼
              [ Pluggable Fallback Engine ]
        • flutter_gemma (MediaPipe / LiteRT-LM)
        • Bundled or dynamic downloaded models for older OSes (iOS < 26, older Android)
```

---

## 2. Smart Fallback Strategy (`flutter_gemma`)

If the host device lacks OS-managed AI (e.g., iOS 15–18, Android devices without Google AICore, or unsupported hardware):
1. **Zero-Configuration Detection**: `ai.isAvailable()` probes native OS capability.
2. **Transparent Delegation**: If OS support is absent and a `fallbackAdapter` is provided, requests (`generateText`, `generateTextStream`, `createSession`) execute through the fallback without breaking callers.
3. **Pluggable Adapter Interface**:
   ```dart
   abstract class OnDeviceAiFallbackAdapter {
     Future<bool> isReady();
     Future<AiResponse> generateText({required String prompt, GenerationConfig? config});
     Stream<String> generateTextStream({required String prompt, GenerationConfig? config});
     Future<OnDeviceAiSession> createSession({String? systemInstruction});
   }
   ```
4. **Official `GemmaFallbackAdapter`**: Implemented using `flutter_gemma` for running Gemma / LiteRT models on older hardware.

---

## 3. Feature Matrix & Platform Support

| Feature | iOS / macOS (26+) | Android (API 26+) | Windows (11 25H2+) | Web (Chromium) | Linux / Desktop Fallback |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Text Generation (Sync/Stream)** | ✅ Native | ✅ Native | ✅ WinRT | ✅ Prompt API | ✅ ONNX / LiteRT |
| **Multi-turn Sessions** | ✅ Native | ✅ Native | ✅ Native | ✅ Native | ✅ Stateful transcript |
| **Structured JSON Outputs** | ✅ Schema-enforced | ⚠️ Compile-time/Dart | ✅ Native WinRT | ✅ Native Schema | ✅ JSON schema mode |
| **Native Tool Calling (Dart)** | ✅ Bidirectional | ⚠️ Dart-mediated | ⚠️ Emulated | ⚠️ Experimental | ✅ Dart engine |
| **Multimodal (Image Input)** | ✅ iOS 27+ / Vision | ✅ AICore Vision | 🚧 Planned | 🚧 Spec Pending | ✅ Clip / Vision |
| **Generative UI (`genui`)** | ✅ Typed Blocks | ✅ Typed Blocks | ✅ Typed Blocks | ✅ Typed Blocks | ✅ Typed Blocks |
| **Model Download & Readiness** | ✅ OS-managed | ✅ Download Stream | ✅ System-managed | ✅ Browser Gesture | ✅ Model Downloader |
| **Exact Token Counter** | ✅ OS 26.4+ | ✅ Native | ⚠️ Estimator | ✅ `measureUsage` | ✅ Exact Tokenizer |
| **Request Cancellation** | ✅ Supported | ✅ Supported | ✅ WinRT Cancel | ✅ AbortController | ✅ CancellationToken |

---

## 3. Dual Public API Surface

### Surface A: Simple Facade API (Quick One-Shots)
```dart
import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';

final ai = FlutterOnDeviceAi();

// Check device eligibility & readiness
final available = await ai.isAvailable();

// Stream response with live tokens
await for (final token in ai.generateTextStream(prompt: 'Tell a story')) {
  stdout.write(token);
}

// Generate structured JSON
final response = await ai.generateText(
  prompt: 'Extract user profile from: "Alice, 30yo software dev"',
  config: GenerationConfig(
    responseFormat: ResponseFormat.json,
    schema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'age': {'type': 'integer'},
        'role': {'type': 'string'},
      },
      'required': ['name', 'age', 'role'],
    },
  ),
);
print(response.json?['role']); // "software dev"
```

### Surface B: Stateful Session API (Multi-turn & Tool Calling)
```dart
// 1. Ensure model is ready (starts download if needed)
await OnDeviceAi.ensureReady(onProgress: (p) => print('Download: $p%'));

// 2. Register native Dart tool callbacks
final session = await OnDeviceAiSession.create(
  systemInstruction: 'You are an intelligent smart home assistant.',
  tools: [
    OnDeviceAiTool(
      name: 'setThermostat',
      description: 'Sets thermostat temperature in Celsius.',
      parameters: [
        ToolParameter(name: 'temp', type: ToolType.number, description: 'Degrees C'),
      ],
      onCall: (args) async {
        final temp = args['temp'];
        return {'status': 'success', 'currentTemp': temp};
      },
    ),
  ],
);

// 3. Multi-turn execution
await session.addQuery('Set living room to 22 degrees');
await for (final chunk in session.getResponseAsync()) {
  stdout.write(chunk);
}
await session.close();
```

### Surface C: Generative UI (`genui` Integration)
```dart
final generator = OnDeviceUiGenerator(ai);
final GenUiModuleSpec? spec = await generator.generateModule(
  'Fitness goal tracker for running 5km',
  principles: 'Minimalist, clear metrics, motivating tone',
);
// Emits typed block specs directly renderable by genui:
// [stat block, progress block, checklist block]
```

---

## 4. Implementation Phases

- [ ] **Phase 1: Project Scaffolding & Core Interface**
  - Create package `flutter_on_device_ai`.
  - Define unified domain models: `GenerationConfig`, `ResponseFormat`, `AiResponse`, `OnDeviceAiTool`, `Capabilities`, `GenUiModuleSpec`.
  - Implement Dart platform interface and method/event channels.

- [ ] **Phase 2: Android Platform Implementation (Kotlin)**
  - Integrate Google ML Kit GenAI Prompt API (`com.google.mlkit:genai-prompt:1.0.0-beta4`).
  - Google AICore installation check and Play Store deep-linking.
  - Streaming channel and token counters.

- [ ] **Phase 3: Apple Platform Implementation (Swift - iOS & macOS)**
  - Integrate Apple `FoundationModels` framework for iOS 26+ and macOS 26+.
  - Dynamic JSON Schema compilation to native `GenerationSchema`.
  - Native bidirectional tool calling bridging back to Dart `onCall` closures.

- [ ] **Phase 4: Web Implementation (Dart JS Interop)**
  - Direct connection to Chrome's `window.ai` / `self.LanguageModel` Prompt API.
  - User-gesture download trigger (`ensureReady`) and streaming tokens.

- [ ] **Phase 5: Windows & Desktop Platform Implementation (C++/WinRT)**
  - Windows AI Foundry integration via Windows App SDK C++/WinRT projection.
  - Portable fallback support for Linux/Desktop via lightweight engine.

- [ ] **Phase 6: Generative UI (`genui`) Engine & Example Showcase**
  - Typed block schema parser with error recovery and truncation repair.
  - Complete multiplatform example app demonstrating chat, streaming, tool calling, and live Generative UI modules.
