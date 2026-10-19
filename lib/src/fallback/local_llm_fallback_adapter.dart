import 'dart:async';

import 'package:llamadart/llamadart.dart';

import '../models/ai_response.dart';
import '../models/generation_config.dart';
import 'fallback_adapter.dart';

/// Fallback that runs a real open model locally with llama.cpp (through
/// [llamadart](https://pub.dev/packages/llamadart)) when the OS ships no model.
///
/// Works on Android, iOS, macOS, Windows, Linux and the web. The GGUF file is
/// downloaded once (from Hugging Face by default) and cached; after that
/// generation is fully offline.
///
/// ```dart
/// final ai = FlutterDeviceAi.withLocalModel();
/// await ai.prepare(onProgress: print); // downloads only if the OS has no model
/// final answer = await ai.generateText(prompt: 'Hello!');
/// ```
class LocalLlmFallbackAdapter extends OnDeviceAiFallbackAdapter {
  LocalLlmFallbackAdapter({
    this.model = defaultModel,
    this.contextSize = 4096,
    this.modelName = 'Local LLM (llama.cpp)',
  });

  /// Qwen2.5 0.5B Instruct, Q4_K_M (about 490 MB). Small enough for any phone;
  /// pass a larger GGUF for better answers.
  static const defaultModel =
      'hf://Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf';

  /// GGUF source: `hf://owner/repo/file.gguf`, an `https://` URL or a local
  /// file path.
  final String model;

  /// Context window in tokens (prompt, history and answer together).
  final int contextSize;

  /// Label used in diagnostics.
  final String modelName;

  LlamaEngine? _engine;
  Future<void>? _loading;

  @override
  String get name => modelName;

  @override
  Future<bool> isReady() async => _engine != null;

  @override
  Future<void> prepare({void Function(double progress)? onProgress}) {
    if (_engine != null) {
      onProgress?.call(1.0);
      return Future.value();
    }
    return _loading ??= _load(onProgress).whenComplete(() => _loading = null);
  }

  Future<void> _load(void Function(double progress)? onProgress) async {
    _engine = await LlamaEngine.load(
      LlamaModel(ModelSource.parse(model)),
      params: ModelParams(contextSize: contextSize),
      onProgress: (p) {
        final fraction = p.fraction;
        if (fraction != null) onProgress?.call(fraction);
      },
    );
    onProgress?.call(1.0);
  }

  LlamaEngine get _loaded {
    final engine = _engine;
    if (engine == null) {
      throw StateError('Call prepare() before using $name.');
    }
    return engine;
  }

  List<LlamaChatMessage> _messages(String prompt, String? instructions) => [
    if (instructions != null && instructions.isNotEmpty)
      LlamaChatMessage.fromText(role: LlamaChatRole.system, text: instructions),
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
  ];

  GenerationParams _params(GenerationConfig? config) {
    const base = GenerationParams();
    return GenerationParams(
      maxTokens: config?.maxTokens ?? base.maxTokens,
      temp: config?.temperature ?? base.temp,
      topK: config?.topK ?? base.topK,
      topP: config?.topP ?? base.topP,
    );
  }

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async {
    final watch = Stopwatch()..start();
    final text = await _loaded
        .create(_messages(prompt, instructions), params: _params(config))
        .text();
    return AiResponse(
      text: text.trim(),
      generationTimeMs: watch.elapsedMilliseconds,
    );
  }

  @override
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    final engine = _loaded;
    late StreamController<String> controller;
    StreamSubscription<String>? sub;
    controller = StreamController<String>(
      onListen: () {
        sub = engine
            .create(_messages(prompt, instructions), params: _params(config))
            .textDeltas()
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
      },
      onCancel: () async {
        engine.cancelGeneration();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<int> countTokens(String text) async {
    if (text.isEmpty) return 0;
    final engine = _engine;
    if (engine == null) return (text.length / 4).ceil();
    return engine.getTokenCount(text);
  }

  @override
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}
