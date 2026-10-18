import 'dart:async';
import '../models/ai_response.dart';
import '../models/generation_config.dart';
import 'fallback_adapter.dart';

/// Handler signature for custom or flutter_gemma model inference calls.
typedef GemmaTextGenerator = Future<String> Function(
  String prompt, {
  GenerationConfig? config,
  String? instructions,
});

/// Handler signature for streaming responses from flutter_gemma / LiteRT.
typedef GemmaStreamGenerator = Stream<String> Function(
  String prompt, {
  GenerationConfig? config,
  String? instructions,
});

/// A ready-to-use adapter connecting [FlutterOnDeviceAi] to [flutter_gemma]
/// or any on-device LiteRT/Gemma model runner.
class GemmaFallbackAdapter implements OnDeviceAiFallbackAdapter {
  final String modelPath;
  final GemmaTextGenerator? onGenerateText;
  final GemmaStreamGenerator? onGenerateStream;
  bool _initialized = false;

  GemmaFallbackAdapter({
    required this.modelPath,
    this.onGenerateText,
    this.onGenerateStream,
  });

  @override
  String get name => 'flutter_gemma ($modelPath)';

  @override
  Future<bool> isReady() async {
    _initialized = true;
    return _initialized;
  }

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    if (onGenerateText != null) {
      final text = await onGenerateText!(
        prompt,
        config: config,
        instructions: instructions,
      );
      final duration = DateTime.now().millisecondsSinceEpoch - startTime;
      return AiResponse(
        text: text,
        generationTimeMs: duration,
      );
    }

    // Default simulation / fallback notification when raw runner is not linked
    return AiResponse(
      text: '[flutter_gemma fallback active for: "$prompt"]',
      generationTimeMs: 15,
    );
  }

  @override
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    if (onGenerateStream != null) {
      return onGenerateStream!(
        prompt,
        config: config,
        instructions: instructions,
      );
    }

    // Split simulated response into chunks if no streaming hook provided
    final controller = StreamController<String>();
    scheduleMicrotask(() async {
      final words = '[flutter_gemma fallback active for: $prompt]'.split(' ');
      for (final word in words) {
        await Future.delayed(const Duration(milliseconds: 40));
        controller.add('$word ');
      }
      await controller.close();
    });
    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}
