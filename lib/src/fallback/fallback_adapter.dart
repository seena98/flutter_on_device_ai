import 'dart:async';
import '../models/ai_response.dart';
import '../models/generation_config.dart';
import '../util.dart';

/// Contract for engines that take over when the OS has no usable model
/// (for example an Edge AI / LiteRT runner on an older phone, or a desktop).
///
/// Adapters are stateless: the package keeps the conversation and sends the
/// rendered transcript as [prompt] on each turn, so sessions, streaming, tool
/// calling and structured output all work through any adapter.
abstract class OnDeviceAiFallbackAdapter {
  /// Short label for diagnostics, e.g. `Edge AI (LiteRT-LM)`.
  String get name;

  /// Whether the engine is loaded and can answer right now.
  Future<bool> isReady();

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
