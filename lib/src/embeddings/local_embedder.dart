import 'dart:async';

import 'package:llamadart/llamadart.dart';

import '../exceptions.dart';
import 'embedder.dart';

/// An embedding model offered to users.
class LocalEmbeddingPreset {
  const LocalEmbeddingPreset(
    this.label,
    this.source,
    this.sizeMb, {
    this.queryPrefix = '',
    this.documentPrefix = '',
    this.contextSize = 512,
  });

  final String label;

  /// `hf://owner/repo/file.gguf`.
  final String source;

  /// Download size in megabytes.
  final int sizeMb;

  /// Text the model expects in front of search queries.
  final String queryPrefix;

  /// Text the model expects in front of stored passages.
  final String documentPrefix;

  /// Longest input the model accepts, in tokens.
  final int contextSize;
}

/// Embeddings from a GGUF embedding model run locally with llama.cpp (through
/// [llamadart](https://pub.dev/packages/llamadart)).
///
/// ```dart
/// final embedder = LocalEmbedder();
/// await embedder.prepare(onProgress: print); // one-time ~35 MB download
/// final index = RagIndex(embedder: embedder);
/// ```
class LocalEmbedder extends OnDeviceAiEmbedder {
  LocalEmbedder({
    this.model = defaultModel,
    this.contextSize = 512,
    this.queryPrefix =
        'Represent this sentence for searching relevant '
        'passages: ',
    this.documentPrefix = '',
    this.sha256,
    this.modelName = 'Local embedder (llama.cpp)',
  });

  /// Builds an embedder from a [preset].
  LocalEmbedder.fromPreset(
    LocalEmbeddingPreset preset, {
    this.sha256,
    this.modelName = 'Local embedder (llama.cpp)',
  }) : model = preset.source,
       contextSize = preset.contextSize,
       queryPrefix = preset.queryPrefix,
       documentPrefix = preset.documentPrefix;

  /// BGE small English v1.5, Q8_0 (about 36 MB, 384 dimensions).
  static const defaultModel =
      'hf://ggml-org/bge-small-en-v1.5-Q8_0-GGUF/bge-small-en-v1.5-q8_0.gguf';

  /// Embedding models that work well, smallest first. Any GGUF embedding
  /// model works; match the prefixes to what its card asks for.
  static const presets = <LocalEmbeddingPreset>[
    LocalEmbeddingPreset(
      'BGE small en v1.5',
      defaultModel,
      36,
      queryPrefix: 'Represent this sentence for searching relevant passages: ',
    ),
  ];

  /// GGUF source: `hf://owner/repo/file.gguf`, an `https://` URL or a local
  /// file path.
  final String model;

  /// Longest input in tokens. Longer text throws; chunk it first.
  final int contextSize;

  /// Prepended to queries by [embedQuery].
  final String queryPrefix;

  /// Prepended to passages by [embed].
  final String documentPrefix;

  /// Expected SHA-256 of the file.
  final String? sha256;

  /// Label used in diagnostics.
  final String modelName;

  LlamaEngine? _engine;
  Future<void>? _loading;
  ModelDownloadCancelToken? _cancel;

  @override
  String get name => modelName;

  @override
  Future<bool> isReady() async => _engine != null || await isDownloaded();

  /// Whether the model file is already on this device.
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

  /// Aborts a running download started by [prepare].
  void cancelPrepare() => _cancel?.cancel();

  @override
  Future<void> prepare({void Function(double progress)? onProgress}) {
    if (_engine != null) {
      onProgress?.call(1.0);
      return Future.value();
    }
    return _loading ??= _load(onProgress).whenComplete(() => _loading = null);
  }

  Future<void> _load(void Function(double progress)? onProgress) async {
    final token = _cancel = ModelDownloadCancelToken();
    try {
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.parse(model)),
        params: ModelParams(contextSize: contextSize),
        download: ModelLoadOptions(sha256: sha256, cancelToken: token),
        onProgress: (p) {
          final fraction = p.fraction;
          if (fraction != null) onProgress?.call(fraction);
        },
      );
      if (!engine.supportsEmbeddings) {
        await engine.dispose();
        throw const OnDeviceAiUnsupportedException(
          'The model cannot produce embeddings. Use a GGUF embedding model '
          'such as bge-small.',
        );
      }
      _engine = engine;
      onProgress?.call(1.0);
    } on OnDeviceAiException {
      rethrow;
    } catch (e) {
      throw OnDeviceAiUnavailableException(
        token.isCancelled
            ? 'The embedding model download was cancelled.'
            : 'Could not download or load the embedding model: $e. Check '
                  'the network connection and free disk space.',
      );
    } finally {
      _cancel = null;
    }
  }

  Future<LlamaEngine> _acquire() async {
    if (_engine == null) await prepare();
    return _engine!;
  }

  Future<List<double>> _embed(String text) async {
    final engine = await _acquire();
    try {
      return await engine.embed(text);
    } on LlamaEmbeddingInputTooLongException catch (e) {
      throw OnDeviceAiException(
        'Text is longer than the embedding model accepts '
        '($contextSize tokens): $e. Split it into smaller chunks.',
        code: 'INPUT_TOO_LONG',
      );
    }
  }

  @override
  Future<List<double>> embed(String text) => _embed('$documentPrefix$text');

  @override
  Future<List<double>> embedQuery(String text) => _embed('$queryPrefix$text');

  @override
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}
