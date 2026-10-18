/// Test doubles for apps that use `flutter_device_ai`.
///
/// ```dart
/// FlutterDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
///   responder: (prompt, history) => 'Echo: $prompt',
/// );
/// ```
library;

import 'dart:async';
import 'dart:typed_data';

import 'flutter_device_ai_platform_interface.dart';
import 'src/exceptions.dart';
import 'src/models/ai_response.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';
import 'src/util.dart';

/// Computes the model's reply from the latest user text and the transcript
/// (`User: ...` / `Assistant: ...` lines, oldest first).
typedef FakeResponder =
    FutureOr<String> Function(String prompt, List<String> transcript);

/// In-memory platform implementation for unit and widget tests.
///
/// It keeps real session state, streams words as chunks and honours
/// cancellation, so code written against the plugin behaves as on a device.
class FakeOnDeviceAiPlatform extends FlutterDeviceAiPlatform {
  FakeOnDeviceAiPlatform({
    this.responder,
    this.availability = const OnDeviceAiAvailability(
      status: ModelFeatureStatus.available,
      reason: AvailabilityReason.ready,
      message: 'Fake on-device model ready.',
    ),
    this.info = const OnDeviceAiPlatformInfo(
      backend: OnDeviceAiBackend.appleFoundationModels,
    ),
    this.chunkDelay = Duration.zero,
  });

  /// Produces replies; defaults to `Fake reply to: <prompt>`.
  FakeResponder? responder;

  /// State returned by [getAvailability].
  OnDeviceAiAvailability availability;

  /// Capabilities returned by [getPlatformInfo].
  OnDeviceAiPlatformInfo info;

  /// Pause between streamed chunks.
  Duration chunkDelay;

  /// Scripted download events for [downloadModel].
  List<ModelDownloadStatus> downloadEvents = const [
    ModelDownloadStatus(status: ModelFeatureStatus.available, progress: 1),
  ];

  /// Every session id ever created, in order.
  final List<String> createdSessions = [];

  /// Sessions that are currently open.
  final Map<String, FakeSession> sessions = {};

  int _counter = 0;

  @override
  Future<OnDeviceAiAvailability> getAvailability() async => availability;

  @override
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() async => info;

  @override
  Stream<ModelDownloadStatus> downloadModel() =>
      Stream.fromIterable(downloadEvents);

  @override
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) async {
    final id = 'fake_${++_counter}';
    createdSessions.add(id);
    sessions[id] = FakeSession(systemInstruction, tools);
    return id;
  }

  FakeSession _session(String id) {
    final s = sessions[id];
    if (s == null) {
      throw const OnDeviceAiException(
        'Unknown session',
        code: 'SESSION_NOT_FOUND',
      );
    }
    return s;
  }

  @override
  Future<void> sessionAddQuery(String sessionId, String text) async =>
      _session(sessionId).pending.add(text);

  @override
  Future<void> sessionAddImage(
    String sessionId,
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    if (!info.supportsVision) {
      throw const OnDeviceAiUnsupportedException('Fake backend has no vision.');
    }
    _session(sessionId).pending.add('[image $mimeType ${imageBytes.length}B]');
  }

  Future<String> _reply(FakeSession s) async {
    if (s.pending.isEmpty) {
      throw const OnDeviceAiException('Empty turn', code: 'EMPTY_TURN');
    }
    final prompt = s.pending.join('\n');
    s.pending.clear();
    s.transcript.add('User: $prompt');
    final reply =
        await (responder?.call(prompt, List.of(s.transcript)) ??
            'Fake reply to: $prompt');
    s.transcript.add('Assistant: $reply');
    return reply;
  }

  @override
  Future<AiResponse> sessionGetResponse(
    String sessionId, {
    GenerationConfig? config,
  }) async {
    final s = _session(sessionId);
    s.cancelled = false;
    final text = await _reply(s);
    if (s.cancelled) throw const OnDeviceAiCancelledException();
    return AiResponse(
      text: text,
      tokenCount: estimateTokens(text),
      generationTimeMs: 1,
    );
  }

  @override
  Stream<String> sessionGetResponseStream(
    String sessionId, {
    GenerationConfig? config,
  }) async* {
    final s = _session(sessionId);
    s.cancelled = false;
    final text = await _reply(s);
    final words = text.split(RegExp(r'(?<=\s)'));
    for (final w in words) {
      if (s.cancelled) throw const OnDeviceAiCancelledException();
      if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      yield w;
    }
  }

  @override
  Future<int> sessionCountTokens(String sessionId, {String? text}) async {
    final s = _session(sessionId);
    return estimateTokens(
      text ?? s.transcript.followedBy(s.pending).join('\n'),
    );
  }

  @override
  Future<void> sessionStopGeneration(String sessionId) async {
    sessions[sessionId]?.cancelled = true;
  }

  @override
  Future<void> sessionClose(String sessionId) async {
    sessions.remove(sessionId);
  }
}

/// State of one fake conversation.
class FakeSession {
  FakeSession(this.systemInstruction, this.tools);

  final String? systemInstruction;
  final List<OnDeviceAiTool>? tools;
  final List<String> pending = [];
  final List<String> transcript = [];
  bool cancelled = false;
}
