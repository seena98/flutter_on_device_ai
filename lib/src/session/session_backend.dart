import 'dart:async';
import 'dart:typed_data';

import '../../flutter_on_device_ai_platform_interface.dart';
import '../exceptions.dart';
import '../fallback/fallback_adapter.dart';
import '../models/ai_response.dart';
import '../models/generation_config.dart';

/// Where a session's turns are actually executed.
///
/// Two implementations exist: [PlatformSessionBackend] (the OS / browser) and
/// [FallbackSessionBackend] (a pluggable adapter such as an Edge AI runner).
abstract class SessionBackend {
  /// Whether the engine calls registered tools by itself.
  bool get nativeTools;

  /// Whether the engine enforces JSON Schemas by itself.
  bool get nativeStructuredOutput;

  /// Whether images can be attached.
  bool get supportsImages;

  /// Whether [countTokens] is exact.
  bool get exactTokenCounts;

  Future<void> addQuery(String text);
  Future<void> addImage(Uint8List bytes, String mimeType);
  Future<AiResponse> respond(GenerationConfig? config);
  Stream<String> respondStream(GenerationConfig? config);
  Future<int> countTokens(String? text);
  Future<void> stop();
  Future<void> close();
}

/// Session served by the platform implementation.
class PlatformSessionBackend implements SessionBackend {
  PlatformSessionBackend({
    required this.sessionId,
    required FlutterOnDeviceAiPlatform platform,
    required this.nativeTools,
    required this.nativeStructuredOutput,
    required this.supportsImages,
    required this.exactTokenCounts,
  }) : _platform = platform;

  final String sessionId;
  final FlutterOnDeviceAiPlatform _platform;

  @override
  final bool nativeTools;
  @override
  final bool nativeStructuredOutput;
  @override
  final bool supportsImages;
  @override
  final bool exactTokenCounts;

  @override
  Future<void> addQuery(String text) =>
      _platform.sessionAddQuery(sessionId, text);

  @override
  Future<void> addImage(Uint8List bytes, String mimeType) =>
      _platform.sessionAddImage(sessionId, bytes, mimeType: mimeType);

  @override
  Future<AiResponse> respond(GenerationConfig? config) =>
      _platform.sessionGetResponse(sessionId, config: config);

  @override
  Stream<String> respondStream(GenerationConfig? config) =>
      _platform.sessionGetResponseStream(sessionId, config: config);

  @override
  Future<int> countTokens(String? text) =>
      _platform.sessionCountTokens(sessionId, text: text);

  @override
  Future<void> stop() => _platform.sessionStopGeneration(sessionId);

  @override
  Future<void> close() => _platform.sessionClose(sessionId);
}

/// Conversation kept in Dart and replayed to a stateless
/// [OnDeviceAiFallbackAdapter] on every turn.
class FallbackSessionBackend implements SessionBackend {
  FallbackSessionBackend({
    required this.adapter,
    required this.systemInstruction,
  });

  final OnDeviceAiFallbackAdapter adapter;
  final String? systemInstruction;

  final List<_Turn> _history = [];
  final List<String> _pending = [];
  StreamSubscription<String>? _activeStream;
  bool _cancelled = false;

  @override
  bool get nativeTools => false;
  @override
  bool get nativeStructuredOutput => false;
  @override
  bool get supportsImages => false;
  @override
  bool get exactTokenCounts => false;

  @override
  Future<void> addQuery(String text) async => _pending.add(text);

  @override
  Future<void> addImage(Uint8List bytes, String mimeType) async {
    throw OnDeviceAiUnsupportedException(
      'The fallback adapter "${adapter.name}" does not accept images.',
    );
  }

  String _takePrompt() {
    if (_pending.isEmpty) {
      throw const OnDeviceAiException(
        'Nothing to answer: call addQuery() before requesting a response.',
        code: 'EMPTY_TURN',
      );
    }
    _history.add(_Turn('User', _pending.join('\n')));
    _pending.clear();
    return _render();
  }

  /// Renders the transcript as a plain chat prompt ending on the assistant cue.
  String _render() {
    final b = StringBuffer();
    for (final t in _history) {
      b.writeln('${t.role}: ${t.text}');
    }
    b.write('Assistant:');
    return b.toString();
  }

  @override
  Future<AiResponse> respond(GenerationConfig? config) async {
    _cancelled = false;
    final prompt = _takePrompt();
    final response = await adapter.generateText(
      prompt: prompt,
      config: config,
      instructions: systemInstruction,
    );
    if (_cancelled) throw const OnDeviceAiCancelledException();
    _history.add(_Turn('Assistant', response.text));
    return response;
  }

  @override
  Stream<String> respondStream(GenerationConfig? config) async* {
    _cancelled = false;
    final prompt = _takePrompt();
    final buffer = StringBuffer();
    final source = adapter.generateTextStream(
      prompt: prompt,
      config: config,
      instructions: systemInstruction,
    );
    final controller = StreamController<String>();
    _activeStream = source.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    try {
      await for (final chunk in controller.stream) {
        buffer.write(chunk);
        yield chunk;
      }
      if (_cancelled) throw const OnDeviceAiCancelledException();
      _history.add(_Turn('Assistant', buffer.toString()));
    } finally {
      await _activeStream?.cancel();
      _activeStream = null;
    }
  }

  @override
  Future<int> countTokens(String? text) async {
    final source =
        text ??
        [
          ?systemInstruction,
          ..._history.map((t) => t.text),
          ..._pending,
        ].join('\n');
    return adapter.countTokens(source);
  }

  @override
  Future<void> stop() async {
    _cancelled = true;
    await _activeStream?.cancel();
  }

  @override
  Future<void> close() async {
    await stop();
    _history.clear();
    _pending.clear();
  }
}

class _Turn {
  const _Turn(this.role, this.text);
  final String role;
  final String text;
}
