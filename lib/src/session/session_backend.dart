import 'dart:async';
import 'dart:typed_data';

import '../../flutter_device_ai_platform_interface.dart';
import '../exceptions.dart';
import '../fallback/fallback_adapter.dart';
import '../models/ai_response.dart';
import '../models/generation_config.dart';

/// Where a session's turns are actually executed.
///
/// Two implementations exist: [PlatformSessionBackend] (the OS / browser) and
/// [FallbackSessionBackend] (a pluggable adapter such as a local llama.cpp model).
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
    required FlutterDeviceAiPlatform platform,
    required this.nativeTools,
    required this.nativeStructuredOutput,
    required this.supportsImages,
    required this.exactTokenCounts,
  }) : _platform = platform;

  final String sessionId;
  final FlutterDeviceAiPlatform _platform;

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
    List<FallbackMessage> history = const [],
  }) {
    _history.addAll(history);
  }

  final OnDeviceAiFallbackAdapter adapter;
  final String? systemInstruction;

  final List<FallbackMessage> _history = [];
  final List<String> _pending = [];
  final List<FallbackImage> _pendingImages = [];
  StreamSubscription<String>? _activeStream;
  bool _cancelled = false;

  @override
  bool get nativeTools => false;
  @override
  bool get nativeStructuredOutput => false;
  @override
  bool get supportsImages => adapter.supportsImages;
  @override
  bool get exactTokenCounts => false;

  @override
  Future<void> addQuery(String text) async => _pending.add(text);

  @override
  Future<void> addImage(Uint8List bytes, String mimeType) async {
    if (!adapter.supportsImages) {
      throw OnDeviceAiUnsupportedException(
        'The fallback adapter "${adapter.name}" does not accept images. '
        'Pass a vision model (LocalLlmFallbackAdapter.projector) to enable '
        'image input.',
      );
    }
    _pendingImages.add(FallbackImage(bytes, mimeType: mimeType));
  }

  List<FallbackMessage> _takeMessages() {
    if (_pending.isEmpty) {
      throw const OnDeviceAiException(
        'Nothing to answer: call addQuery() before requesting a response.',
        code: 'EMPTY_TURN',
      );
    }
    _history.add(
      FallbackMessage.user(
        _pending.join('\n'),
        images: List.unmodifiable(_pendingImages),
      ),
    );
    _pending.clear();
    _pendingImages.clear();
    return List.of(_history);
  }

  @override
  Future<AiResponse> respond(GenerationConfig? config) async {
    _cancelled = false;
    final messages = _takeMessages();
    try {
      final response = await adapter.generateChat(
        messages: messages,
        config: config,
        instructions: systemInstruction,
      );
      if (_cancelled) throw const OnDeviceAiCancelledException();
      _history.add(FallbackMessage.assistant(response.text));
      return response;
    } catch (_) {
      _history.removeLast();
      rethrow;
    }
  }

  @override
  Stream<String> respondStream(GenerationConfig? config) async* {
    _cancelled = false;
    final messages = _takeMessages();
    final buffer = StringBuffer();
    final source = adapter.generateChatStream(
      messages: messages,
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
      _history.add(FallbackMessage.assistant(buffer.toString()));
    } catch (_) {
      if (_history.isNotEmpty && _history.last.isUser) _history.removeLast();
      rethrow;
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
    _pendingImages.clear();
  }
}

/// Runs a session on the OS model and, if that model turns out to be
/// unusable (for example Apple's model assets are missing on a simulator),
/// moves the conversation to the fallback adapter and answers the turn there.
class FailoverSessionBackend implements SessionBackend {
  FailoverSessionBackend({
    required this.primary,
    required this.adapter,
    required this.fallbackInstruction,
  });

  final SessionBackend primary;
  final OnDeviceAiFallbackAdapter adapter;

  /// System instruction (with the emulated tool prompt) used after failover.
  final String? fallbackInstruction;

  final List<FallbackMessage> _history = [];
  final List<String> _pending = [];
  SessionBackend? _fallback;

  SessionBackend get _active => _fallback ?? primary;

  @override
  bool get nativeTools => _active.nativeTools;
  @override
  bool get nativeStructuredOutput => _active.nativeStructuredOutput;
  @override
  bool get supportsImages => _active.supportsImages;
  @override
  bool get exactTokenCounts => _active.exactTokenCounts;

  @override
  Future<void> addQuery(String text) async {
    _pending.add(text);
    await _active.addQuery(text);
  }

  @override
  Future<void> addImage(Uint8List bytes, String mimeType) =>
      _active.addImage(bytes, mimeType);

  Future<bool> _failOver(Object error) async {
    if (_fallback != null || error is! OnDeviceAiUnavailableException) {
      return false;
    }
    bool ready;
    try {
      ready = await adapter.isReady();
    } catch (_) {
      ready = false;
    }
    if (!ready) return false;
    final next = FallbackSessionBackend(
      adapter: adapter,
      systemInstruction: fallbackInstruction,
      history: _history,
    );
    for (final text in _pending) {
      await next.addQuery(text);
    }
    _fallback = next;
    return true;
  }

  void _commit(String answer) {
    _history
      ..add(FallbackMessage.user(_pending.join('\n')))
      ..add(FallbackMessage.assistant(answer));
    _pending.clear();
  }

  @override
  Future<AiResponse> respond(GenerationConfig? config) async {
    if (_fallback != null) return _fallback!.respond(config);
    try {
      final response = await primary.respond(config);
      _commit(response.text);
      return response;
    } catch (e) {
      if (!await _failOver(e)) rethrow;
      return _fallback!.respond(config);
    }
  }

  @override
  Stream<String> respondStream(GenerationConfig? config) async* {
    if (_fallback != null) {
      yield* _fallback!.respondStream(config);
      return;
    }
    final buffer = StringBuffer();
    var started = false;
    try {
      await for (final chunk in primary.respondStream(config)) {
        started = true;
        buffer.write(chunk);
        yield chunk;
      }
      _commit(buffer.toString());
    } catch (e) {
      if (started || !await _failOver(e)) rethrow;
      yield* _fallback!.respondStream(config);
    }
  }

  @override
  Future<int> countTokens(String? text) => _active.countTokens(text);

  @override
  Future<void> stop() => _active.stop();

  @override
  Future<void> close() async {
    await primary.close();
    await _fallback?.close();
  }
}
