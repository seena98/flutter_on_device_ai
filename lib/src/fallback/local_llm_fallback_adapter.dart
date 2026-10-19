import 'dart:async';

import 'package:llamadart/llamadart.dart';

import '../exceptions.dart';
import '../models/ai_response.dart';
import '../models/generation_config.dart';
import 'fallback_adapter.dart';

/// What a [LocalLlmFallbackAdapter] is doing right now.
enum LocalLlmPhase {
  /// Nothing loaded and nothing in progress.
  idle,

  /// The model file is being downloaded.
  downloading,

  /// The model file is being loaded into memory.
  loading,

  /// Loaded and ready to answer.
  ready,

  /// Downloaded, but released from memory (idle timeout or [LocalLlmFallbackAdapter.unload]).
  /// The next request reloads it without downloading again.
  unloaded,
}

/// A snapshot of [LocalLlmFallbackAdapter.status].
class LocalLlmStatus {
  const LocalLlmStatus(this.phase, {this.progress});

  final LocalLlmPhase phase;

  /// Download or load progress in `0..1` while [phase] is `downloading` or
  /// `loading`, when known.
  final double? progress;

  @override
  String toString() => 'LocalLlmStatus($phase, $progress)';
}

/// A model offered to users, with a rough idea of what it needs.
class LocalLlmPreset {
  const LocalLlmPreset(this.label, this.source, this.sizeMb, this.minRamGb);

  final String label;

  /// `hf://owner/repo/file.gguf`.
  final String source;

  /// Download size in megabytes.
  final int sizeMb;

  /// Device memory below which this model is likely to be killed by the OS.
  final int minRamGb;
}

/// Fallback that runs a real open model locally with llama.cpp (through
/// [llamadart](https://pub.dev/packages/llamadart)) when the OS ships no model.
///
/// Works on Android, iOS, macOS, Windows, Linux and the web. The GGUF file is
/// downloaded once (from Hugging Face by default, resumable, with retries) and
/// cached; after that generation is fully offline. Conversations use the
/// model's own chat template, and JSON-schema answers are grammar-constrained.
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
    this.sha256,
    this.idleUnloadAfter,
    this.allowDownload,
  });

  /// Qwen2.5 0.5B Instruct, Q4_K_M (about 490 MB). Small enough for any phone;
  /// pass a larger GGUF for better answers.
  static const defaultModel =
      'hf://Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf';

  /// Models that work well, smallest first. Any GGUF works, these are checked.
  static const presets = <LocalLlmPreset>[
    LocalLlmPreset(
      'SmolLM2 360M',
      'hf://bartowski/SmolLM2-360M-Instruct-GGUF/SmolLM2-360M-Instruct-Q4_K_M.gguf',
      270,
      2,
    ),
    LocalLlmPreset('Qwen2.5 0.5B', defaultModel, 490, 3),
    LocalLlmPreset(
      'Llama 3.2 1B',
      'hf://bartowski/Llama-3.2-1B-Instruct-GGUF/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      810,
      4,
    ),
    LocalLlmPreset(
      'Qwen2.5 1.5B',
      'hf://Qwen/Qwen2.5-1.5B-Instruct-GGUF/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      1100,
      4,
    ),
    LocalLlmPreset(
      'Gemma 2 2B',
      'hf://bartowski/gemma-2-2b-it-GGUF/gemma-2-2b-it-Q4_K_M.gguf',
      1700,
      6,
    ),
    LocalLlmPreset(
      'Qwen2.5 3B',
      'hf://Qwen/Qwen2.5-3B-Instruct-GGUF/qwen2.5-3b-instruct-q4_k_m.gguf',
      2100,
      8,
    ),
  ];

  /// The largest [presets] entry that fits in [ramGb] of device memory, or the
  /// smallest one when nothing does.
  static LocalLlmPreset recommendedFor(int ramGb) => presets.lastWhere(
    (p) => p.minRamGb <= ramGb,
    orElse: () => presets.first,
  );

  /// GGUF source: `hf://owner/repo/file.gguf`, an `https://` URL or a local
  /// file path.
  final String model;

  /// Context window in tokens (prompt, history and answer together).
  final int contextSize;

  /// Label used in diagnostics.
  final String modelName;

  /// Expected SHA-256 of the file. The download is rejected when it differs.
  final String? sha256;

  /// Releases the model from memory after this much inactivity. The next
  /// request reloads it from disk (no download). Null keeps it loaded.
  final Duration? idleUnloadAfter;

  /// Asked before a network download starts. Return `false` to refuse, for
  /// example when the device is not on Wi-Fi.
  final Future<bool> Function()? allowDownload;

  LlamaEngine? _engine;
  Future<void>? _loading;
  ModelDownloadCancelToken? _cancel;
  Timer? _idleTimer;
  int _active = 0;
  bool _disposed = false;
  bool _wasLoaded = false;
  final _status = StreamController<LocalLlmStatus>.broadcast();
  LocalLlmStatus _last = const LocalLlmStatus(LocalLlmPhase.idle);

  /// Phase changes, including download and load progress.
  Stream<LocalLlmStatus> get status => _status.stream;

  /// The latest phase.
  LocalLlmStatus get currentStatus => _last;

  void _emit(LocalLlmPhase phase, [double? progress]) {
    _last = LocalLlmStatus(phase, progress: progress);
    if (!_status.isClosed) _status.add(_last);
  }

  @override
  String get name => modelName;

  @override
  Future<bool> isReady() async {
    if (_engine != null) return true;
    return _wasLoaded || await isDownloaded();
  }

  /// Whether the model file is already on this device (no download needed).
  Future<bool> isDownloaded() async {
    try {
      await DefaultModelDownloadManager().ensureModel(
        ModelSource.parse(model),
        options: ModelLoadOptions(
          cachePolicy: ModelCachePolicy.cacheOnly,
          sha256: sha256,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the model if needed and loads it. Safe to call repeatedly.
  @override
  Future<void> prepare({void Function(double progress)? onProgress}) {
    if (_engine != null) {
      onProgress?.call(1.0);
      return Future.value();
    }
    return _loading ??= _load(onProgress).whenComplete(() => _loading = null);
  }

  /// Aborts a running download started by [prepare].
  void cancelPrepare() => _cancel?.cancel();

  Future<void> _load(void Function(double progress)? onProgress) async {
    if (_disposed) throw StateError('$name was disposed.');
    final token = _cancel = ModelDownloadCancelToken();
    try {
      final cached = await isDownloaded();
      if (!cached && allowDownload != null && !await allowDownload!()) {
        throw const OnDeviceAiUnavailableException(
          'The local model is not downloaded and downloading is not allowed '
          'right now (for example, no Wi-Fi).',
        );
      }
      _emit(cached ? LocalLlmPhase.loading : LocalLlmPhase.downloading, 0);
      _engine = await LlamaEngine.load(
        LlamaModel(ModelSource.parse(model)),
        params: ModelParams(contextSize: contextSize),
        download: ModelLoadOptions(sha256: sha256, cancelToken: token),
        onProgress: (p) {
          final fraction = p.fraction;
          if (fraction == null) return;
          _emit(
            cached ? LocalLlmPhase.loading : LocalLlmPhase.downloading,
            fraction,
          );
          onProgress?.call(fraction);
        },
      );
      _wasLoaded = true;
      _emit(LocalLlmPhase.ready, 1);
      onProgress?.call(1.0);
    } on OnDeviceAiException {
      _emit(_wasLoaded ? LocalLlmPhase.unloaded : LocalLlmPhase.idle);
      rethrow;
    } catch (e) {
      _emit(_wasLoaded ? LocalLlmPhase.unloaded : LocalLlmPhase.idle);
      throw OnDeviceAiUnavailableException(
        token.isCancelled
            ? 'The model download was cancelled.'
            : 'Could not download or load the local model: $e. Check the '
                  'network connection and free disk space.',
      );
    } finally {
      _cancel = null;
    }
  }

  /// Releases the model from memory but keeps the file. The next request
  /// reloads it.
  Future<void> unload() async {
    _idleTimer?.cancel();
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await engine.dispose();
      _emit(LocalLlmPhase.unloaded);
    }
  }

  /// Unloads the model and deletes its file from the cache. Local-path models
  /// are not touched.
  Future<void> deleteModel() async {
    await unload();
    _wasLoaded = false;
    final source = ModelSource.parse(model);
    if (source.isLocal) return;
    final manager = DefaultModelDownloadManager();
    try {
      final entry = await manager.ensureModel(
        source,
        options: ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly),
      );
      await manager.remove(entry.cacheKey);
    } catch (_) {
      // Not cached: nothing to delete.
    }
    _emit(LocalLlmPhase.idle);
  }

  Future<LlamaEngine> _acquire() async {
    _idleTimer?.cancel();
    if (_engine == null) {
      if (!await isDownloaded() && !_wasLoaded) {
        throw StateError('Call prepare() before using $name.');
      }
      await prepare();
    }
    _active++;
    return _engine!;
  }

  void _release() {
    if (_active > 0) _active--;
    final after = idleUnloadAfter;
    if (after != null && _active == 0) {
      _idleTimer?.cancel();
      _idleTimer = Timer(after, unload);
    }
  }

  GenerationParams _params(GenerationConfig? config) {
    const base = GenerationParams();
    return GenerationParams(
      maxTokens: config?.maxTokens ?? base.maxTokens,
      temp: config?.temperature ?? base.temp,
      topK: config?.topK ?? base.topK,
      topP: config?.topP ?? base.topP,
    );
  }

  /// A session seeded with every message but the last, plus the last user text.
  (ChatSession, String) _session(
    LlamaEngine engine,
    List<FallbackMessage> messages,
    String? instructions,
  ) {
    final session = ChatSession(
      engine,
      maxContextTokens: contextSize,
      systemPrompt: instructions,
    );
    for (final m in messages.take(messages.length - 1)) {
      session.addMessage(
        LlamaChatMessage.fromText(
          role: m.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
          text: m.text,
        ),
      );
    }
    return (session, messages.last.text);
  }

  Map<String, dynamic>? _format(GenerationConfig? config) {
    final schema = config?.schema;
    if (config?.responseFormat != ResponseFormat.json || schema == null) {
      return null;
    }
    return {
      'type': 'json_schema',
      'json_schema': {'schema': schema},
    };
  }

  Stream<String> _stream(
    LlamaEngine engine,
    List<FallbackMessage> messages,
    GenerationConfig? config,
    String? instructions, {
    bool constrained = true,
  }) {
    final (session, text) = _session(engine, messages, instructions);
    return session
        .create(
          [LlamaTextContent(text)],
          params: _params(config),
          responseFormat: constrained ? _format(config) : null,
        )
        .textDeltas();
  }

  @override
  Future<AiResponse> generateChat({
    required List<FallbackMessage> messages,
    GenerationConfig? config,
    String? instructions,
  }) async {
    final watch = Stopwatch()..start();
    final engine = await _acquire();
    try {
      String text;
      try {
        text = await _stream(engine, messages, config, instructions).join();
      } on LlamaException {
        // Grammar rejected the schema: fall back to unconstrained text, the
        // caller still validates and repairs.
        if (_format(config) == null) rethrow;
        text = await _stream(
          engine,
          messages,
          config,
          instructions,
          constrained: false,
        ).join();
      }
      return AiResponse(
        text: text.trim(),
        generationTimeMs: watch.elapsedMilliseconds,
      );
    } finally {
      _release();
    }
  }

  @override
  Stream<String> generateChatStream({
    required List<FallbackMessage> messages,
    GenerationConfig? config,
    String? instructions,
  }) {
    late StreamController<String> controller;
    StreamSubscription<String>? sub;
    LlamaEngine? engine;
    var released = false;
    void release() {
      if (!released && engine != null) {
        released = true;
        _release();
      }
    }

    controller = StreamController<String>(
      onListen: () async {
        try {
          engine = await _acquire();
          sub = _stream(engine!, messages, config, instructions).listen(
            controller.add,
            onError: controller.addError,
            onDone: () {
              release();
              controller.close();
            },
          );
        } catch (e, st) {
          controller.addError(e, st);
          await controller.close();
        }
      },
      onCancel: () async {
        engine?.cancelGeneration();
        await sub?.cancel();
        release();
      },
    );
    return controller.stream;
  }

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) => generateChat(
    messages: [FallbackMessage.user(prompt)],
    config: config,
    instructions: instructions,
  );

  @override
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) => generateChatStream(
    messages: [FallbackMessage.user(prompt)],
    config: config,
    instructions: instructions,
  );

  @override
  Future<int> countTokens(String text) async {
    if (text.isEmpty) return 0;
    final engine = _engine;
    if (engine == null) return (text.length / 4).ceil();
    return engine.getTokenCount(text);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _idleTimer?.cancel();
    await unload();
    await _status.close();
  }
}
