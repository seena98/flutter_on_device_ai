import 'dart:async';
import 'dart:typed_data';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_on_device_ai_method_channel.dart';
import 'src/models/ai_response.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';

/// The platform interface that all platform-specific implementations of
/// `flutter_on_device_ai` must implement.
abstract class FlutterOnDeviceAiPlatform extends PlatformInterface {
  FlutterOnDeviceAiPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterOnDeviceAiPlatform _instance = MethodChannelFlutterOnDeviceAi();

  /// The active platform-specific implementation.
  static FlutterOnDeviceAiPlatform get instance => _instance;

  static set instance(FlutterOnDeviceAiPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Check whether an on-device AI model is available on this device.
  Future<bool> isAvailable() {
    throw UnimplementedError('isAvailable() has not been implemented.');
  }

  /// Returns a human-readable explanation when AI is not ready or unavailable.
  Future<String> availabilityReason() {
    throw UnimplementedError('availabilityReason() has not been implemented.');
  }

  /// Initializes the default model session with optional system instructions.
  Future<bool> initialize({String? instructions}) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Generates text synchronously using the active or throwaway session.
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    throw UnimplementedError('generateText() has not been implemented.');
  }

  /// Streams generated text delta chunks.
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    throw UnimplementedError('generateTextStream() has not been implemented.');
  }

  /// Registers Dart-defined tools for native function calling.
  Future<void> registerTools(List<OnDeviceAiTool> tools) {
    throw UnimplementedError('registerTools() has not been implemented.');
  }

  /// Queries runtime capabilities of the detected backend.
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() {
    throw UnimplementedError('getPlatformInfo() has not been implemented.');
  }

  /// Returns the model installation/download readiness status.
  Future<ModelFeatureStatus> getModelStatus() {
    throw UnimplementedError('getModelStatus() has not been implemented.');
  }

  /// Requests the OS or browser to download the required on-device model weights.
  Stream<ModelDownloadStatus> downloadModel() {
    throw UnimplementedError('downloadModel() has not been implemented.');
  }

  /// Opens Google Play Store to install or update Google AICore (Android only).
  Future<bool> openAICorePlayStore() {
    throw UnimplementedError('openAICorePlayStore() has not been implemented.');
  }

  // --- Session Management ---

  /// Creates a new isolated conversation session.
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) {
    throw UnimplementedError('createSession() has not been implemented.');
  }

  /// Appends a query to an active session.
  Future<void> sessionAddQuery(String sessionId, String text) {
    throw UnimplementedError('sessionAddQuery() has not been implemented.');
  }

  /// Appends an image for multimodal input.
  Future<void> sessionAddImage(String sessionId, Uint8List imageBytes, {String mimeType = 'image/jpeg'}) {
    throw UnimplementedError('sessionAddImage() has not been implemented.');
  }

  /// Generates the next response for a session.
  Future<AiResponse> sessionGetResponse(String sessionId, {GenerationConfig? config}) {
    throw UnimplementedError('sessionGetResponse() has not been implemented.');
  }

  /// Streams the next response for a session.
  Stream<String> sessionGetResponseStream(String sessionId, {GenerationConfig? config}) {
    throw UnimplementedError('sessionGetResponseStream() has not been implemented.');
  }

  /// Measures exact or approximate token count for a session.
  Future<int> sessionCountTokens(String sessionId, {String? text}) {
    throw UnimplementedError('sessionCountTokens() has not been implemented.');
  }

  /// Aborts generation in a session.
  Future<void> sessionStopGeneration(String sessionId) {
    throw UnimplementedError('sessionStopGeneration() has not been implemented.');
  }

  /// Closes an active session.
  Future<void> sessionClose(String sessionId) {
    throw UnimplementedError('sessionClose() has not been implemented.');
  }
}
