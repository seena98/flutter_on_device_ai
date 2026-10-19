import 'dart:async';
import '../models/ai_response.dart';
import '../models/generation_config.dart';
import '../util.dart';

/// Contract for engines that take over when the OS has no usable model
/// (for example a local llama.cpp model on an older phone, or a desktop).
///
/// Adapters are stateless: the package keeps the conversation and sends the
/// rendered transcript as [prompt] on each turn, so sessions, streaming, tool
/// calling and structured output all work through any adapter.
abstract class OnDeviceAiFallbackAdapter {
  /// Short label for diagnostics, e.g. `Local LLM (llama.cpp)`.
  String get name;

  /// Whether the engine is loaded and can answer right now.
  Future<bool> isReady();

  /// Downloads / loads the engine so [isReady] becomes true. Adapters that are
  /// always ready can leave this as is.
  Future<void> prepare({void Function(double progress)? onProgress}) async {
    onProgress?.call(1.0);
  }

  /// Single-shot, non-streaming generation.
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  });

  /// Streaming generation yielding text deltas.
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  });

  /// Token count for [text]. Defaults to a ~4 characters per token estimate.
  Future<int> countTokens(String text) async => estimateTokens(text);

  /// Releases native resources.
  Future<void> dispose();
}
