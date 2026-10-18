import 'dart:async';
import 'dart:typed_data';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_device_ai_method_channel.dart';
import 'src/models/ai_response.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';

/// The contract every platform implementation fulfils.
///
/// The surface is deliberately small: availability, model download and
/// *sessions*. One-shot generation, tool-call emulation, structured-output
/// repair and fallback routing are built on top of it in Dart, so they behave
/// identically everywhere.
abstract class FlutterDeviceAiPlatform extends PlatformInterface {
  FlutterDeviceAiPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterDeviceAiPlatform _instance = MethodChannelFlutterDeviceAi();

  /// The active platform-specific implementation.
  static FlutterDeviceAiPlatform get instance => _instance;

  static set instance(FlutterDeviceAiPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Current state of the native model, with a reason when it is not ready.
  Future<OnDeviceAiAvailability> getAvailability() {
    throw UnimplementedError('getAvailability() has not been implemented.');
  }

  /// What the native backend can do.
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() {
    throw UnimplementedError('getPlatformInfo() has not been implemented.');
  }

  /// Asks the OS / browser to download the model, reporting progress.
  ///
  /// The stream completes when the model is ready or the download failed.
  Stream<ModelDownloadStatus> downloadModel() {
    throw UnimplementedError('downloadModel() has not been implemented.');
  }

  /// Opens the Google AICore page in Play Store (Android only).
  Future<bool> openAICorePlayStore() async => false;

  // --- Sessions -------------------------------------------------------------

  /// Creates a conversation and returns its id.
  ///
  /// [tools] is non-null only when the backend reported native tool calling.
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) {
    throw UnimplementedError('createSession() has not been implemented.');
  }

  /// Adds a user text part to the pending turn.
  Future<void> sessionAddQuery(String sessionId, String text) {
    throw UnimplementedError('sessionAddQuery() has not been implemented.');
  }

  /// Adds a user image part to the pending turn.
  Future<void> sessionAddImage(
    String sessionId,
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) {
    throw UnimplementedError('sessionAddImage() has not been implemented.');
  }

  /// Answers the pending turn.
  Future<AiResponse> sessionGetResponse(
    String sessionId, {
    GenerationConfig? config,
  }) {
    throw UnimplementedError('sessionGetResponse() has not been implemented.');
  }

  /// Answers the pending turn as a stream of text deltas.
  Stream<String> sessionGetResponseStream(
    String sessionId, {
    GenerationConfig? config,
  }) {
    throw UnimplementedError(
      'sessionGetResponseStream() has not been implemented.',
    );
  }

  /// Token count of the whole conversation, or of [text] when given.
  Future<int> sessionCountTokens(String sessionId, {String? text}) {
    throw UnimplementedError('sessionCountTokens() has not been implemented.');
  }

  /// Cancels the generation in flight, if any.
  Future<void> sessionStopGeneration(String sessionId) {
    throw UnimplementedError(
      'sessionStopGeneration() has not been implemented.',
    );
  }

  /// Releases the session.
  Future<void> sessionClose(String sessionId) {
    throw UnimplementedError('sessionClose() has not been implemented.');
  }
}
