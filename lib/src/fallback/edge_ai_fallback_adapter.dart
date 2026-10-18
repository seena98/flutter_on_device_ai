import 'dart:async';

import '../models/ai_response.dart';
import '../models/generation_config.dart';
import 'fallback_adapter.dart';

/// Runs a prompt through your on-device runner and returns the full answer.
typedef EdgeAiTextGenerator =
    Future<String> Function(
      String prompt, {
      GenerationConfig? config,
      String? instructions,
    });

/// Runs a prompt through your on-device runner, yielding text deltas.
typedef EdgeAiStreamGenerator =
    Stream<String> Function(
      String prompt, {
      GenerationConfig? config,
      String? instructions,
    });

/// Fallback adapter for on-device runners such as `flutter_edge_ai`
/// (LiteRT-LM and friends), MediaPipe or anything else that can generate text.
///
/// This package does not depend on a particular runner: you wire your own
/// loaded model in through the callbacks, so you control which model file is
/// downloaded and when. See the README for a complete example.
class EdgeAiFallbackAdapter implements OnDeviceAiFallbackAdapter {
  EdgeAiFallbackAdapter({
    required this.onGenerateText,
    this.onGenerateStream,
    this.isModelReady,
    this.onDispose,
    this.modelName = 'Edge AI',
  });

  /// Produces a complete answer.
  final EdgeAiTextGenerator onGenerateText;

  /// Produces a streamed answer. When omitted, [onGenerateText] is used and
  /// the answer arrives as one chunk.
  final EdgeAiStreamGenerator? onGenerateStream;

  /// Reports whether the model is loaded. Defaults to always ready.
  final FutureOr<bool> Function()? isModelReady;

  /// Called by [dispose] to close the underlying runner.
  final FutureOr<void> Function()? onDispose;

  /// Label used in diagnostics.
  final String modelName;

  @override
  String get name => modelName;

  @override
  Future<bool> isReady() async => await (isModelReady?.call() ?? true);

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async {
    final watch = Stopwatch()..start();
    final text = await onGenerateText(
      prompt,
      config: config,
      instructions: instructions,
    );
    return AiResponse(text: text, generationTimeMs: watch.elapsedMilliseconds);
  }

  @override
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    final streaming = onGenerateStream;
    if (streaming != null) {
      return streaming(prompt, config: config, instructions: instructions);
    }
    return Stream.fromFuture(
      onGenerateText(prompt, config: config, instructions: instructions),
    );
  }

  @override
  Future<int> countTokens(String text) async =>
      text.isEmpty ? 0 : (text.length / 4).ceil();

  @override
  Future<void> dispose() async => await onDispose?.call();
}
