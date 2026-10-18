import 'flutter_device_ai_platform_interface.dart';
import 'src/exceptions.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';

/// Implementation for Windows and Linux, which have no OS-managed language
/// model this package can call yet.
///
/// It reports `unavailable`, so `FlutterDeviceAi` routes everything through
/// the configured fallback adapter (for example a flutter_edge_ai runner). Without a
/// fallback, calls throw [OnDeviceAiUnavailableException].
class FlutterDeviceAiDesktopStub extends FlutterDeviceAiPlatform {
  FlutterDeviceAiDesktopStub();

  /// Called by the Flutter tool on Windows and Linux.
  static void registerWith() {
    FlutterDeviceAiPlatform.instance = FlutterDeviceAiDesktopStub();
  }

  static const _message =
      'This platform has no OS-managed language model. Configure a '
      'fallbackAdapter (for example EdgeAiFallbackAdapter) to run on it.';

  @override
  Future<OnDeviceAiAvailability> getAvailability() async =>
      const OnDeviceAiAvailability(
        status: ModelFeatureStatus.unavailable,
        reason: AvailabilityReason.platformUnsupported,
        message: _message,
      );

  @override
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() async =>
      const OnDeviceAiPlatformInfo(
        backend: OnDeviceAiBackend.unsupported,
        diagnosticNotes: _message,
      );

  @override
  Stream<ModelDownloadStatus> downloadModel() => Stream.value(
    const ModelDownloadStatus(
      status: ModelFeatureStatus.unavailable,
      errorMessage: _message,
    ),
  );

  @override
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) => throw const OnDeviceAiUnavailableException(_message);
}
