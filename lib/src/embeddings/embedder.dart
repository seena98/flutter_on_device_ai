import 'dart:async';

/// Turns text into vectors for semantic search.
///
/// Vectors are L2-normalised, so cosine similarity is a dot product. The
/// built-in implementation is [LocalEmbedder] (llama.cpp); implement this to
/// plug in any other engine.
abstract class OnDeviceAiEmbedder {
  /// Short label for diagnostics.
  String get name;

  /// Whether the model is loaded and can embed right now.
  Future<bool> isReady();

  /// Downloads / loads the model so [isReady] becomes true.
  Future<void> prepare({void Function(double progress)? onProgress}) async {
    onProgress?.call(1.0);
  }

  /// Embeds a passage that will be stored and searched.
  Future<List<double>> embed(String text);

  /// Embeds a search query. Models trained with a query instruction override
  /// this; the default is [embed].
  Future<List<double>> embedQuery(String text) => embed(text);

  /// Embeds [texts] in order. The default calls [embed] one by one.
  Future<List<List<double>>> embedBatch(List<String> texts) async => [
    for (final t in texts) await embed(t),
  ];

  /// Releases native resources.
  Future<void> dispose();
}
