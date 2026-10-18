import 'dart:async';
import 'dart:typed_data';
import '../models/ai_response.dart';
import '../models/generation_config.dart';
import '../models/tool.dart';
import '../../flutter_on_device_ai_platform_interface.dart';

/// Represents an active, multi-turn conversation session with an on-device language model.
class OnDeviceAiSession {
  final String sessionId;
  final String? systemInstruction;
  final List<OnDeviceAiTool> tools;
  final FlutterOnDeviceAiPlatform _platform;
  bool _isClosed = false;

  OnDeviceAiSession({
    required this.sessionId,
    this.systemInstruction,
    this.tools = const [],
    FlutterOnDeviceAiPlatform? platform,
  }) : _platform = platform ?? FlutterOnDeviceAiPlatform.instance;

  /// Whether this session has been closed and can no longer receive requests.
  bool get isClosed => _isClosed;

  /// Appends a user query to the current session turn.
  Future<void> addQuery(String text) async {
    _ensureOpen();
    await _platform.sessionAddQuery(sessionId, text);
  }

  /// Appends image bytes for multimodal inference (where supported).
  Future<void> addImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    _ensureOpen();
    await _platform.sessionAddImage(sessionId, imageBytes, mimeType: mimeType);
  }

  /// Generates a complete response for the accumulated turn.
  Future<AiResponse> getResponse({GenerationConfig? config}) async {
    _ensureOpen();
    return await _platform.sessionGetResponse(sessionId, config: config);
  }

  /// Streams token chunks for the accumulated turn as the model decodes them.
  Stream<String> getResponseAsync({GenerationConfig? config}) {
    _ensureOpen();
    return _platform.sessionGetResponseStream(sessionId, config: config);
  }

  /// Measures exact token count for the active context or arbitrary text.
  Future<int> countTokens({String? text}) async {
    _ensureOpen();
    return await _platform.sessionCountTokens(sessionId, text: text);
  }

  /// Aborts any in-flight generation in this session.
  Future<void> stopGeneration() async {
    _ensureOpen();
    await _platform.sessionStopGeneration(sessionId);
  }

  /// Closes the session and releases native resources on the device.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _platform.sessionClose(sessionId);
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('OnDeviceAiSession "$sessionId" is already closed.');
    }
  }
}
