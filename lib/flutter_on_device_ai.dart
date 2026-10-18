import 'dart:async';
import 'flutter_on_device_ai_platform_interface.dart';
import 'src/fallback/fallback_adapter.dart';
import 'src/models/ai_response.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';
import 'src/session/on_device_ai_session.dart';

export 'src/models/generation_config.dart';
export 'src/models/ai_response.dart';
export 'src/models/tool.dart';
export 'src/models/capabilities.dart';
export 'src/models/model_status.dart';
export 'src/models/gen_ui_spec.dart';
export 'src/session/on_device_ai_session.dart';
export 'src/fallback/fallback_adapter.dart';
export 'src/fallback/gemma_fallback_adapter.dart';

/// Primary interface for interacting with on-device AI models.
///
/// Automatically uses native OS-managed accelerators (Apple Foundation Models,
/// Android Gemini Nano, Chrome Prompt API, Windows AI Foundry) and gracefully
/// falls back to a provided [fallbackAdapter] (such as flutter_gemma) if the OS
/// lacks native AI support.
class FlutterOnDeviceAi {
  static final FlutterOnDeviceAi _singleton = FlutterOnDeviceAi._internal();

  /// Default singleton instance.
  factory FlutterOnDeviceAi() => _singleton;

  FlutterOnDeviceAi._internal();

  /// Creates an instance with a customized [fallbackAdapter].
  FlutterOnDeviceAi.withFallback({this.fallbackAdapter});

  /// Optional pluggable fallback engine (e.g. [GemmaFallbackAdapter])
  /// used automatically when the host device lacks OS-managed AI.
  OnDeviceAiFallbackAdapter? fallbackAdapter;

  FlutterOnDeviceAiPlatform get _platform => FlutterOnDeviceAiPlatform.instance;

  /// Probes whether local on-device AI is available on this device.
  Future<bool> isAvailable() async {
    final nativeAvailable = await _platform.isAvailable();
    if (nativeAvailable) return true;
    if (fallbackAdapter != null) {
      return await fallbackAdapter!.isReady();
    }
    return false;
  }

  /// Returns diagnostic information explaining why on-device AI is unavailable.
  Future<String> availabilityReason() async {
    final nativeAvailable = await _platform.isAvailable();
    if (!nativeAvailable && fallbackAdapter != null) {
      return 'Native OS model is unavailable; utilizing ${fallbackAdapter!.name} fallback.';
    }
    return await _platform.availabilityReason();
  }

  /// Initializes the default model session with instructions.
  Future<bool> initialize({String? instructions}) async {
    return await _platform.initialize(instructions: instructions);
  }

  /// Generates text with generation configurations.
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async {
    final nativeAvailable = await _platform.isAvailable();
    if (!nativeAvailable && fallbackAdapter != null) {
      return await fallbackAdapter!.generateText(
        prompt: prompt,
        config: config,
        instructions: instructions,
      );
    }
    return await _platform.generateText(
      prompt: prompt,
      config: config,
      instructions: instructions,
    );
  }

  /// Convenient helper to generate text and return just the text string.
  Future<String> generateTextSimple({
    required String prompt,
    int maxTokens = 100,
  }) async {
    final res = await generateText(
      prompt: prompt,
      config: GenerationConfig(maxTokens: maxTokens),
    );
    return res.text;
  }

  /// Streams generated text delta tokens as they decode.
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    if (fallbackAdapter != null) {
      // Check asynchronously and route
      final controller = StreamController<String>();
      _platform.isAvailable().then((nativeAvailable) {
        if (!nativeAvailable) {
          fallbackAdapter!.generateTextStream(
            prompt: prompt,
            config: config,
            instructions: instructions,
          ).listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
        } else {
          _platform.generateTextStream(
            prompt: prompt,
            config: config,
            instructions: instructions,
          ).listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
        }
      });
      return controller.stream;
    }
    return _platform.generateTextStream(
      prompt: prompt,
      config: config,
      instructions: instructions,
    );
  }

  /// Registers Dart tools the model can invoke during generation.
  Future<void> registerTools(List<OnDeviceAiTool> tools) async {
    await _platform.registerTools(tools);
  }

  /// Queries runtime platform backend and capabilities.
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() async {
    return await _platform.getPlatformInfo();
  }

  /// Queries model readiness / download status.
  Future<ModelFeatureStatus> getModelStatus() async {
    return await _platform.getModelStatus();
  }

  /// Requests the OS or browser to download model assets, reporting progress.
  Stream<ModelDownloadStatus> downloadModel() {
    return _platform.downloadModel();
  }

  /// Opens Google Play Store to install or update AICore (Android only).
  Future<bool> openAICorePlayStore() async {
    return await _platform.openAICorePlayStore();
  }

  /// Creates a multi-turn, stateful conversation session.
  Future<OnDeviceAiSession> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) async {
    final sessionId = await _platform.createSession(
      systemInstruction: systemInstruction,
      tools: tools,
      config: config,
    );
    return OnDeviceAiSession(
      sessionId: sessionId,
      systemInstruction: systemInstruction,
      tools: tools ?? const [],
      platform: _platform,
    );
  }

  /// Prepares the on-device model, starting download if required, and awaiting readiness.
  static Future<void> ensureReady({void Function(double progress)? onProgress}) async {
    final ai = FlutterOnDeviceAi();
    final status = await ai.getModelStatus();
    if (status == ModelFeatureStatus.available) {
      onProgress?.call(1.0);
      return;
    }

    final completer = Completer<void>();
    late StreamSubscription<ModelDownloadStatus> sub;
    sub = ai.downloadModel().listen((event) {
      if (event.progress != null) {
        onProgress?.call(event.progress!);
      }
      if (event.status == ModelFeatureStatus.available) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete();
      } else if (event.status == ModelFeatureStatus.unavailable) {
        sub.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Model download failed: ${event.errorMessage ?? "unavailable"}'),
          );
        }
      }
    });

    return completer.future;
  }
}
