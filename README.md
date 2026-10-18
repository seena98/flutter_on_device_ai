<p align="center">
  <img src="doc/assets/hero.png" alt="flutter_on_device_ai: generative AI that ships with the device" width="100%" />
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_on_device_ai"><img src="https://img.shields.io/pub/v/flutter_on_device_ai.svg" alt="pub version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20Android%20%7C%20Web%20%7C%20Windows%20%7C%20Linux-475569.svg" alt="platforms">
</p>

Your phone already contains a language model. Apple ships one with iOS and macOS 26, Google ships Gemini Nano through AICore on recent Android phones, and Chrome ships one in the browser. `flutter_on_device_ai` lets a Flutter app talk to **whichever one is present**, through a single API, and **hands over to a model you choose** (through `flutter_edge_ai`, for example) when the device has none.

* Nothing to bundle: **0 MB** added to your app, no API key, no server, works offline.
* One API for chat sessions, streaming, cancellation, tool calling, JSON-schema output and generated UI.
* **A feature the engine lacks is filled in for you.** Tool calling and schema-constrained JSON work on every backend, natively where the OS supports them and through a tested Dart layer everywhere else. `capabilities()` tells you which is which.
* **Real fallback, not a stub.** Older phone, desktop, unsupported region: the same session code runs on your fallback engine.
* **Typed errors** that tell the user what to do (turn Apple Intelligence on, install AICore, tap to download).
* **Test without a device** using the bundled `FakeOnDeviceAiPlatform`.

```dart
final ai = FlutterOnDeviceAi();

if (await ai.isAvailable()) {
  final reply = await ai.generateText(prompt: 'Name three uses for a paperclip.');
  print(reply.text);
}
```

<p align="center">
  <img src="doc/assets/demo.gif" alt="The example app: streaming chat, JSON extraction, tool calling and a generated screen" width="300" />
  <br />
  <sub><b>Illustrative demo.</b> This is the real example app and the real library code (streaming, schema validation, tool loop, generated UI). The model's replies are pre-written and fed in through <code>FakeOnDeviceAiPlatform</code>, so it shows the behaviour, not a device capture or real model speed. Regenerate with <code>doc/demo.md</code>.</sub>
</p>

## Contents

[Install](#install) · [Pick an engine](#how-a-request-finds-its-engine) · [What works where](#what-works-where) · [Guide](#guide) · [Platform setup](#platform-setup) · [Errors](#errors) · [Testing](#testing-your-app) · [API map](#api-map) · [Limits](#known-limits) · [AI agents](#for-ai-coding-agents)

## Install

```sh
flutter pub add flutter_on_device_ai
```

Requires Flutter 3.32+ (Dart 3.8+). Platform prerequisites are in [Platform setup](#platform-setup).

## How a request finds its engine

<p align="center"><img src="doc/assets/routing.png" alt="Routing: OS model if ready, else fallback adapter, else a typed exception" width="92%" /></p>

The decision is made per session, at the moment you create it, so a model that finishes downloading is picked up on the next session without restarting anything.

## What works where

`native` means the OS does it. `emulated` means this package does it on top of plain text generation, and it behaves the same everywhere. Ask the running device with `await ai.capabilities()` instead of testing for a platform name.

| | Apple (iOS / macOS 26+) | Android (API 26+) | Web (Chrome / Edge) | Fallback adapter | Windows / Linux |
|---|:---:|:---:|:---:|:---:|:---:|
| Text, streaming, cancel | native | native | native | via adapter | fallback only |
| Multi-turn sessions | native | kept in Dart | native | kept in Dart | fallback only |
| JSON-schema output | native | emulated, validated, auto-repaired | native | emulated | fallback only |
| Tool calling | native | emulated | emulated | emulated | fallback only |
| Image input | not yet | native | not yet | no | no |
| Token counting | estimate | exact | exact | estimate | estimate |
| Model download progress | OS-managed | yes | yes (needs a gesture) | your runner | your runner |

**Windows and Linux** have no OS-managed model this package can call, so they report `unavailable` and route to your fallback adapter. Native Windows AI support is on the roadmap.

> **Verification status.** The Dart layer is covered by unit tests, the web layer runs against a real browser engine with a stubbed `LanguageModel`, and the iOS, macOS and Android native code compiles against the real SDKs. Inference on a real Apple Intelligence or Gemini Nano device is exercised by `example/integration_test`, which you should run on your target hardware (see [Testing](#testing-your-app)).

## Guide

### Sessions: conversations with memory

```dart
final session = await ai.createSession(
  systemInstruction: 'You are a patient Dart tutor. Keep answers short.',
);

final first = await session.ask('What does `late` do?');
print(first.text);

final second = await session.ask('Show an example.'); // remembers the first turn
print(second.text);

print(await session.countTokens());
await session.close();
```

Open as many sessions as you like; they are isolated. A session answers one turn at a time and throws `OnDeviceAiSessionBusyException` if you touch it mid-generation.

A turn can be assembled from several parts before you ask for the answer:

```dart
await session.addQuery('Summarise this article:');
await session.addQuery(articleText);
final summary = await session.getResponse(config: const GenerationConfig(maxTokens: 200));
```

### Streaming and cancelling

```dart
final session = await ai.createSession();

final subscription = session.askStream('Write a long story.').listen(
  (delta) => setState(() => story += delta),
  onError: (e) => debugPrint('$e'),
);

// later, from a "Stop" button:
await session.stopGeneration();   // pending futures/streams fail with OnDeviceAiCancelledException
```

Cancelling is real: it stops the native generation, it does not just ignore the output.

### Structured output

Describe the shape you want with a JSON Schema. You always get either a value that satisfies it or an `OnDeviceAiStructuredOutputException`.

```dart
final res = await ai.generateText(
  prompt: 'Extract the person: "Ada Lovelace, mathematician, 36"',
  config: const GenerationConfig(
    responseFormat: ResponseFormat.json,
    schema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'age': {'type': 'integer', 'minimum': 0},
      },
      'required': ['name', 'age'],
    },
  ),
);

print(res.json!['age']); // 36
```

Where the OS enforces the schema (Apple, Chrome) it is used directly. Everywhere else the package asks for JSON, extracts it from the reply (fences, chatter and truncated output included), validates it against your schema and, if it does not fit, **tells the model what was wrong and asks again** (`GenerationConfig.maxRepairAttempts`, default 2).

Supported schema keywords: `type` (object, array, string, integer, number, boolean, null), `enum`, `properties`, `required`, `additionalProperties: false`, `items`, `minItems`/`maxItems`, `minLength`/`maxLength`, `minimum`/`maximum`, `pattern`. Anything else fails fast with `OnDeviceAiSchemaException`, before any model runs.

With a schema, streaming delivers the validated answer as one chunk.

### Tools: let the model call your Dart code

```dart
final session = await ai.createSession(
  systemInstruction: 'You control a smart home.',
  tools: [
    OnDeviceAiTool(
      name: 'setThermostat',
      description: 'Sets the target temperature in Celsius.',
      parameters: const [
        ToolParameter(name: 'celsius', type: ToolArgumentType.number, description: 'Target in °C'),
        ToolParameter(name: 'room', type: ToolArgumentType.string, description: 'Room name', optional: true),
      ],
      onCall: (args) async {
        await home.setTemperature(args['celsius'] as num, room: args['room'] as String?);
        return {'ok': true};
      },
    ),
  ],
);

final reply = await session.ask('It is chilly, warm the living room to 22.');
```

* Nested or constrained arguments: pass `parameterSchema:` (a JSON Schema) instead of `parameters:`.
* Refuse or report a problem by throwing `OnDeviceAiToolException('Door is locked')`. The message goes back to the model as data so it can recover or explain.
* On Apple the OS calls your tool natively. Elsewhere the package teaches the model a small JSON protocol, validates the arguments against your schema, runs your function and feeds the result back, for up to `maxToolRounds` round trips. The loop also works while streaming.
* Small on-device models are less reliable at deciding *when* to call a tool than large cloud models. Keep descriptions specific and the tool list short.

### Fallback: keep working on devices with no OS model

Give the facade an adapter and everything above (sessions, streaming, tools, schemas) runs on it whenever the OS model is not ready.

```dart
final ai = FlutterOnDeviceAi.withFallback(
  fallbackAdapter: EdgeAiFallbackAdapter(
    modelName: 'Edge AI',
    isModelReady: () async => model != null,
    onGenerateText: (prompt, {config, instructions}) async {
      final chat = await model!.createChat();
      await chat.addQueryChunk(Message.text(
        text: [if (instructions != null) instructions, prompt].join('\n\n'),
        isUser: true,
      ));
      final out = StringBuffer();
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is TextResponse) out.write(r.token);
      }
      return out.toString();
    },
  ),
);
```

`EdgeAiFallbackAdapter` is deliberately runner-agnostic: it takes your loaded model through callbacks, so *you* decide which model file to download and when, and the package adds no heavy dependency. `model` above is what `FlutterEdgeAi.getActiveModel()` returns in [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai); the snippet follows that package's documented `Message` / `generateChatResponseAsync` API. Adapt the body to whichever runner you use. The adapter is stateless: the package keeps the conversation and sends the rendered transcript on each turn.

Need another engine? Implement `OnDeviceAiFallbackAdapter` (four methods).

### Readiness, download and guidance

```dart
final state = await ai.availability();      // status + reason + a sentence for your UI
switch (state.reason) {
  case AvailabilityReason.ready:                 break;
  case AvailabilityReason.featureDisabled:       showHint('Turn on Apple Intelligence in Settings.');
  case AvailabilityReason.systemComponentMissing: await ai.openAICorePlayStore();
  case AvailabilityReason.modelNotReady:         await FlutterOnDeviceAi.ensureReady(onProgress: showProgress);
  default:                                       showHint(state.message);
}
```

`ensureReady` downloads the model when the platform allows it and reports progress from 0 to 1. **On the web call it from a click or tap**, otherwise the browser refuses and you get `OnDeviceAiUserActivationRequiredException`.

### Generated UI

Turn a goal into a typed, validated screen description and render it with your own widgets.

```dart
final generator = OnDeviceUiGenerator();
final module = await generator.generateModule(
  'A one-week plan to get ready for a 10K',
  language: 'English',
  principles: 'Calm, minimal, encouraging.',
);

if (module == null) {
  showHint(generator.lastError!);
} else {
  for (final block in module.blocks) { /* switch on block['type'] */ }
}
```

Block types: `stat`, `progress`, `checklist`, `list`, `steps`, `table`, `callout`, `note`. Blocks the model gets wrong are dropped, missing numbers get safe defaults, truncated JSON is repaired, and you only ever see blocks that are renderable. `module.toComponentMaps()` gives `{id, type, properties}` maps for component-based renderers. `GenUiBlockTypes.moduleSchema` and `OnDeviceUiGenerator.genUiInstructions` are public if you want to drive another engine. Pass `tools:` to let the model fetch data while it designs. The example app contains a complete block renderer.

## Platform setup

**Apple (iOS, macOS)**
The plugin builds down to iOS 13 / macOS 10.15 and reports `unavailable` on anything older than 26. Inference needs **iOS or macOS 26+**, a device that supports Apple Intelligence, Apple Intelligence switched on in Settings, and **Xcode 26+** to build. Image input and exact token counts need newer SDKs and are not enabled yet.

**Android**
`minSdk 26`. Needs a device with Google AICore and Gemini Nano support (for example recent Pixel and Galaxy flagships). If AICore is missing, `availability().reason` is `systemComponentMissing`; call `openAICorePlayStore()`. If the model is not yet on the device, `ensureReady()` downloads it. The ML Kit GenAI Prompt API dependency (`com.google.mlkit:genai-prompt`) is added by the plugin; do not pin an older version.

**Web**
Desktop Chrome or Edge with the built-in Prompt API available (enable `chrome://flags/#prompt-api-for-gemini-nano` where it is not on by default). The first download needs a user gesture and several GB of disk. No build configuration needed.

**Windows, Linux**
No OS model is called yet. Provide a `fallbackAdapter`.

## Errors

Everything extends `OnDeviceAiException` and carries a stable `code`.

| Exception | Code | When |
|---|---|---|
| `OnDeviceAiUnavailableException` | `UNAVAILABLE` | No usable model and no fallback |
| `OnDeviceAiUnsupportedException` | `UNSUPPORTED` | Feature not offered (e.g. images on this backend) |
| `OnDeviceAiUserActivationRequiredException` | `USER_ACTIVATION_REQUIRED` | Web download outside a gesture |
| `OnDeviceAiSessionBusyException` | `SESSION_BUSY` | Session touched while generating |
| `OnDeviceAiCancelledException` | `CANCELLED` | `stopGeneration()` or a cancelled stream |
| `OnDeviceAiStructuredOutputException` | `STRUCTURED_OUTPUT_INVALID` | Schema not satisfied after repairs (`errors`, `rawText`) |
| `OnDeviceAiSchemaException` | `INVALID_SCHEMA` | Unsupported schema construct |
| `OnDeviceAiGenerationException` | `GENERATION_FAILED` | The engine failed |

## Testing your app

Swap in the in-memory platform. It keeps real session state, streams words as chunks and honours cancellation.

```dart
import 'package:flutter_on_device_ai/testing.dart';

setUp(() {
  FlutterOnDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
    responder: (prompt, transcript) => 'Echo: $prompt',
    // availability: ..., info: ... to simulate other devices
  );
});
```

To check the *real* model on your hardware, run the bundled integration test on a device that has one. It skips itself, with a printed reason, on devices that do not:

```sh
cd example
flutter test integration_test -d <device-id>
```

## API map

| You want to | Use |
|---|---|
| One question, one answer | `ai.generateText`, `ai.generateTextSimple` |
| Stream an answer | `ai.generateTextStream`, `session.askStream` |
| A conversation | `ai.createSession` → `ask`, `addQuery`, `addImage`, `getResponse`, `getResponseAsync`, `countTokens`, `stopGeneration`, `close` |
| Check readiness | `ai.availability`, `ai.isAvailable`, `ai.capabilities`, `ai.getPlatformInfo` |
| Prepare the model | `FlutterOnDeviceAi.ensureReady`, `ai.prepare`, `ai.downloadModel`, `ai.openAICorePlayStore` |
| Tune generation | `GenerationConfig` (`maxTokens`, `temperature`, `topP`, `topK`, `responseFormat`, `schema`, `maxRepairAttempts`) |
| Let the model act | `OnDeviceAiTool`, `ToolParameter`, `OnDeviceAiToolException` |
| Run on other engines | `OnDeviceAiFallbackAdapter`, `EdgeAiFallbackAdapter` |
| Build screens | `OnDeviceUiGenerator`, `GenUiModuleSpec`, `GenUiBlockTypes` |
| Parse model output yourself | `JsonSchema.validate`, `JsonExtractor.extract` |
| Test | `package:flutter_on_device_ai/testing.dart` |

Full API docs are on [pub.dev](https://pub.dev/documentation/flutter_on_device_ai/latest/).

## Known limits

* On-device models are small. Expect shorter context windows, simpler reasoning and occasional tool-calling misses compared with cloud models. Design prompts accordingly.
* `maxTokens` is honoured on Apple and Android; Chrome's Prompt API has no such limit and ignores it.
* Android's Prompt API is stateless, so long conversations are re-sent every turn and count against the model's context window.
* Chrome fixes sampling parameters when a session's model is created, so `temperature`/`topK` apply from the session's first turn.
* Image input works on Android only for now; Apple's image input needs an SDK that is not yet enabled here.
* Windows AI Foundry (Phi Silica) is not implemented yet.

## For AI coding agents

If you are an LLM or an agent working with this package, read [`llms.txt`](llms.txt) (usage and pitfalls) or [`AGENTS.md`](AGENTS.md) (repository guide for contributors).

## Contributing

Issues and pull requests are welcome. Run `flutter analyze`, `flutter test` and `flutter test --platform chrome test/web_test.dart` before opening a PR; see [`AGENTS.md`](AGENTS.md) for the architecture and the rules that keep the native layers honest.

## License

MIT. See [LICENSE](LICENSE).
