# flutter_on_device_ai

A unified, production-grade Flutter plugin for running on-device Generative AI using native OS-managed accelerators across **iOS, macOS, Android, Windows, Web, and Linux** — featuring a **Smart Fallback Engine** for [`flutter_gemma`](https://pub.dev/packages/flutter_gemma) on older hardware.

---

## ✨ Unique Advantages

- **Zero-Checkpoint App Bundle**: Uses system-managed models directly through native operating system APIs. No multi-gigabyte models bundled inside your APK, IPA, or web build.
- **100% Private & Offline**: Zero server latency, zero cloud fees, and zero user data leaving the device.
- **Hardware NPU Acceleration**: Direct access to Apple Neural Engine (ANE), Google Tensor TPU / AICore, Copilot+ NPUs, and WebGPU.
- **Smart Fallback Engine (`flutter_gemma`)**: If the device runs an older OS (e.g. iOS 15–18 or Android phones without Google AICore), it transparently delegates to `flutter_gemma` without breaking your application code!
- **Dual Public API**: Choose between a simple one-shot facade (`generateText`, `generateTextStream`) and a full multi-turn stateful session API (`OnDeviceAiSession`).
- **Structured Outputs**: Enforce JSON schema constraints natively on supported platforms.
- **Bidirectional Tool Calling**: Define Dart functions and let the on-device model invoke them natively with typed arguments.
- **Generative UI (`genui`)**: Turn natural language goals into renderable typed-block UI specs (`GenUiModuleSpec`).

---

## 📱 Platform Matrix

| Platform | Native OS Model Engine | Fallback / Compatibility |
| :--- | :--- | :--- |
| **iOS** | Apple Foundation Models (iOS 26+) | `flutter_gemma` / LiteRT (iOS 13+) |
| **macOS** | Apple Foundation Models (macOS 26+) | `flutter_gemma` / Metal GGUF (macOS 12+) |
| **Android** | Google ML Kit GenAI / Gemini Nano (API 26+) | `flutter_gemma` / MediaPipe |
| **Windows** | Windows AI Foundry / WinRT (11 25H2+) | DirectML / ONNX Runtime |
| **Web** | Chrome Built-in AI (`window.ai` Prompt API) | WebLLM / Transformers.js |
| **Linux** | Local lightweight engine | `flutter_gemma` / GGUF |

---

## 🚀 Getting Started

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_on_device_ai: ^0.0.1
```

---

## 💡 Usage

### 1. Simple One-Shot Generation

```dart
import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';

final ai = FlutterOnDeviceAi();

// Check device readiness
if (!await ai.isAvailable()) {
  print(await ai.availabilityReason());
  return;
}

// Generate text
final response = await ai.generateText(
  prompt: 'Explain quantum computing in two sentences.',
  config: const GenerationConfig(maxTokens: 150, temperature: 0.7),
);
print(response.text);
```

### 2. Live Token Streaming

Stream decoded delta chunks directly into your UI:

```dart
final stream = ai.generateTextStream(
  prompt: 'Write a short motivational quote.',
);

await for (final token in stream) {
  stdout.write(token);
}
```

### 3. Stateful Multi-Turn Conversations

```dart
final session = await ai.createSession(
  systemInstruction: 'You are an intelligent code tutor.',
);

await session.addQuery('What is the difference between final and const in Dart?');
final reply1 = await session.getResponse();
print(reply1.text);

// Next turn (retains conversation context)
await session.addQuery('Give me an example of each.');
final reply2 = await session.getResponse();
print(reply2.text);

await session.close();
```

### 4. Schema-Constrained Structured Outputs (JSON Mode)

Constrain generation to valid JSON adhering to your JSON Schema:

```dart
final response = await ai.generateText(
  prompt: 'Extract profile: "John Doe, 29, Mobile Engineer at TechCorp"',
  config: const GenerationConfig(
    responseFormat: ResponseFormat.json,
    schema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'age': {'type': 'integer'},
        'role': {'type': 'string'},
        'company': {'type': 'string'},
      },
      'required': ['name', 'age', 'role'],
    },
  ),
);

// Access pre-decoded JSON map directly
final data = response.json;
print(data?['name']); // "John Doe"
print(data?['role']); // "Mobile Engineer"
```

### 5. Native Dart Tool Calling (Function Calling)

Register Dart functions that the on-device model can autonomously call:

```dart
await ai.registerTools([
  OnDeviceAiTool(
    name: 'setThermostat',
    description: 'Adjusts room temperature in Celsius.',
    parameters: const [
      ToolParameter(
        name: 'temperature',
        type: ToolArgumentType.number,
        description: 'Target temperature in Celsius',
      ),
    ],
    onCall: (args) async {
      final temp = args['temperature'];
      // Execute local hardware or app state change
      return {'status': 'success', 'appliedTemperature': temp};
    },
  ),
]);

// Prompting the model will invoke the tool when relevant:
final res = await ai.generateText(
  prompt: 'It is too warm in here, please set the thermostat to 21 degrees.',
);
```

### 6. Smart Fallback with `flutter_gemma`

Provide a `fallbackAdapter` for seamless execution on older iPhones or Android phones without Google AICore:

```dart
final ai = FlutterOnDeviceAi.withFallback(
  fallbackAdapter: GemmaFallbackAdapter(
    modelPath: 'assets/models/gemma-2b-it.bin',
    onGenerateText: (prompt, {config, instructions}) async {
      // Delegate to your loaded flutter_gemma model instance
      return await myGemmaModel.generate(prompt);
    },
  ),
);

// Transparently uses Apple Intelligence / Gemini Nano on modern devices,
// and automatically routes to flutter_gemma on older devices!
final res = await ai.generateText(prompt: 'Hello!');
```

### 7. Generative UI (`genui`) Module Generation

Transform natural language into renderable typed-block modules:

```dart
final spec = OnDeviceUiGenerator.parseModelOutput(rawText);
if (spec != null) {
  print(spec.title); // "10K Running Prep"
  print(spec.blocks); // [{"type": "stat", ...}, {"type": "progress", ...}]
  final componentMaps = spec.toComponentMaps(); // A2UI compatible component trees
}
```

---

## 🛠 Diagnostics & Model Readiness

```dart
// Query detected backend and capabilities
final info = await ai.getPlatformInfo();
print('Backend: ${info.backend}');
print('Supports tool calling: ${info.supportsToolCalling}');
print('Supports structured JSON: ${info.supportsStructuredOutput}');

// Await one-time system model preparation with progress tracking
await FlutterOnDeviceAi.ensureReady(
  onProgress: (progress) => print('Download: ${(progress * 100).toInt()}%'),
);
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
