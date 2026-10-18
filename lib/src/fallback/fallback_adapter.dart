import 'dart:async';
import '../models/ai_response.dart';
import '../models/generation_config.dart';

/// Contract for pluggable fallback engines (e.g. flutter_gemma or custom ONNX models)
/// when the host device lacks OS-managed AI capabilities.
abstract class OnDeviceAiFallbackAdapter {
  /// Name or description of the fallback model.
  String get name;

  /// Check whether the fallback engine is loaded and ready for inference.
  Future<bool> isReady();

  /// Execute a one-shot non-streaming text generation prompt.
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  });

  /// Execute a streaming prompt yielding chunks of text as decoded.
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  });

  /// Release native resources held by the fallback engine.
  Future<void> dispose();
}
