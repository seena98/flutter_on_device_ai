import 'dart:async';

import 'flutter_device_ai_platform_interface.dart';
import 'src/exceptions.dart';
import 'src/fallback/fallback_adapter.dart';
import 'src/fallback/local_llm_fallback_adapter.dart';
import 'src/models/ai_response.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';
import 'src/session/on_device_ai_session.dart';
import 'src/session/session_backend.dart';
import 'src/session/tool_emulation.dart';

export 'flutter_device_ai_stub.dart' show FlutterDeviceAiDesktopStub;
export 'src/exceptions.dart';
export 'src/fallback/fallback_adapter.dart';
export 'src/fallback/callback_fallback_adapter.dart';
export 'src/fallback/local_llm_fallback_adapter.dart';
export 'src/genui/gen_ui_spec.dart';
export 'src/genui/on_device_ui_generator.dart';
export 'src/models/ai_response.dart';
export 'src/models/capabilities.dart';
export 'src/models/generation_config.dart';
export 'src/models/model_status.dart';
export 'src/models/tool.dart';
export 'src/schema/json_schema.dart' show JsonSchema, JsonExtractor;
export 'src/session/on_device_ai_session.dart';

/// Entry point for on-device generative AI.
///
/// Uses the model the operating system already ships (Apple Foundation Models,
/// Gemini Nano through Google AICore, Chrome's built-in Gemini Nano) and, when
/// none is usable, transparently routes to a [fallbackAdapter].
///
/// ```dart
/// final ai = FlutterDeviceAi();
/// if (await ai.isAvailable()) {
///   final answer = await ai.generateText(prompt: 'Hello!');
///   print(answer.text);
/// }
/// ```
class FlutterDeviceAi {
  static final FlutterDeviceAi _singleton = FlutterDeviceAi._internal();

  /// The shared default instance.
  factory FlutterDeviceAi() => _singleton;

  FlutterDeviceAi._internal();

  /// Creates an independent instance, optionally with a [fallbackAdapter].
  FlutterDeviceAi.withFallback({this.fallbackAdapter});

  /// Creates an independent instance that, when the OS has no usable model,
  /// runs an open GGUF model locally with llama.cpp ([LocalLlmFallbackAdapter]).
  /// Call [prepare] once to download it.
  FlutterDeviceAi.withLocalModel({
    String model = LocalLlmFallbackAdapter.defaultModel,
    int contextSize = 4096,
  }) : fallbackAdapter = LocalLlmFallbackAdapter(
         model: model,
         contextSize: contextSize,
       );

  /// Engine used whenever the native model is not ready.
  OnDeviceAiFallbackAdapter? fallbackAdapter;

  String? _defaultInstructions;
  List<OnDeviceAiTool> _tools = const [];

  FlutterDeviceAiPlatform get _platform => FlutterDeviceAiPlatform.instance;

  // --- Availability ---------------------------------------------------------

  /// Detailed state of the *native* model (ignores the fallback).
  Future<OnDeviceAiAvailability> availability() => _platform.getAvailability();

  /// Whether a request made now will be answered: by the native model or by a
  /// ready fallback.
  Future<bool> isAvailable() async {
    if ((await availability()).isReady) return true;
    return await _fallbackReady();
  }

  /// Why the native model is unavailable, in a sentence fit for the UI.
  Future<String> availabilityReason() async {
    final native = await availability();
    if (!native.isReady && await _fallbackReady()) {
      return '${native.message} Using the ${fallbackAdapter!.name} fallback.';
    }
    return native.message;
  }

  /// Native model readiness (`available`, `downloadable`, ...).
  Future<ModelFeatureStatus> getModelStatus() async =>
      (await availability()).status;

  /// What the native backend supports (ignores emulation and fallback).
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() =>
      _platform.getPlatformInfo();

  /// What your app can use *right now*, including this package's emulation
  /// layers and the fallback. Prefer this over checking the platform.
  Future<OnDeviceAiCapabilities> capabilities() async {
    final native = (await availability()).isReady;
    if (!native && await _fallbackReady()) {
      return const OnDeviceAiCapabilities(
        backend: OnDeviceAiBackend.fallback,
        toolCalling: CapabilitySupport.emulated,
        structuredOutput: CapabilitySupport.emulated,
      );
    }
    final info = await _platform.getPlatformInfo();
    return OnDeviceAiCapabilities(
      backend: native ? info.backend : OnDeviceAiBackend.unsupported,
      toolCalling: !native
          ? CapabilitySupport.unsupported
          : info.supportsToolCalling
          ? CapabilitySupport.native
          : CapabilitySupport.emulated,
      structuredOutput: !native
          ? CapabilitySupport.unsupported
          : info.supportsStructuredOutput
          ? CapabilitySupport.native
          : CapabilitySupport.emulated,
      imageInput: native && info.supportsVision,
      exactTokenCounts: native && info.supportsExactTokenCounts,
      modelDownload: info.supportsModelDownload,
    );
  }

  Future<bool> _fallbackReady() async {
    final adapter = fallbackAdapter;
    if (adapter == null) return false;
    try {
      return await adapter.isReady();
    } catch (_) {
      return false;
    }
  }

  // --- Model download -------------------------------------------------------

  /// Asks the OS / browser to download the model and reports progress.
  Stream<ModelDownloadStatus> downloadModel() => _platform.downloadModel();

  /// Opens Google AICore in the Play Store (Android only).
  Future<bool> openAICorePlayStore() => _platform.openAICorePlayStore();

  /// Makes sure the native model is ready, downloading it if needed.
  ///
  /// On the web call this from a user gesture (click / tap), otherwise
  /// [OnDeviceAiUserActivationRequiredException] is thrown. Throws
  /// [OnDeviceAiUnavailableException] when the device cannot run the model.
  static Future<void> ensureReady({
    void Function(double progress)? onProgress,
  }) => FlutterDeviceAi().prepare(onProgress: onProgress);

  /// Instance form of [ensureReady].
  Future<void> prepare({void Function(double progress)? onProgress}) async {
    final state = await availability();
    if (state.isReady) {
      onProgress?.call(1.0);
      return;
    }
    if (state.status == ModelFeatureStatus.unavailable) {
      final adapter = fallbackAdapter;
      if (adapter == null) throw OnDeviceAiUnavailableException(state.message);
      await adapter.prepare(onProgress: onProgress);
      return;
    }

    String? failure;
    var ready = false;
    await for (final event in _platform.downloadModel()) {
      final p = event.progress;
      if (p != null) onProgress?.call(p.clamp(0.0, 1.0));
      if (event.status == ModelFeatureStatus.available) {
        ready = true;
      } else if (event.status == ModelFeatureStatus.unavailable) {
        failure = event.errorMessage ?? 'unavailable';
      }
    }
    if (failure != null) {
      throw OnDeviceAiUnavailableException('Model download failed: $failure');
    }
    if (!ready && !(await availability()).isReady) {
      throw const OnDeviceAiUnavailableException(
        'The model download ended before the model became ready.',
      );
    }
    onProgress?.call(1.0);
  }

  // --- One-shot API ---------------------------------------------------------

  /// Sets default [instructions] for one-shot calls.
  Future<bool> initialize({String? instructions}) async {
    _defaultInstructions = instructions;
    return isAvailable();
  }

  /// Registers [tools] for one-shot calls ([generateText] and friends).
  /// Sessions take their own tools in [createSession].
  Future<void> registerTools(List<OnDeviceAiTool> tools) async {
    _tools = List.unmodifiable(tools);
  }

  /// Generates a complete answer to [prompt] in a throw-away session.
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async {
    final session = await createSession(
      systemInstruction: instructions,
      tools: _tools,
      config: config,
    );
    try {
      return await session.ask(prompt);
    } finally {
      await session.close();
    }
  }

  /// Streams the answer to [prompt] as text deltas.
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async* {
    final session = await createSession(
      systemInstruction: instructions,
      tools: _tools,
      config: config,
    );
    try {
      yield* session.askStream(prompt);
    } finally {
      await session.close();
    }
  }

  /// Shortcut returning only the text.
  Future<String> generateTextSimple({
    required String prompt,
    int maxTokens = 256,
  }) async {
    final res = await generateText(
      prompt: prompt,
      config: GenerationConfig(maxTokens: maxTokens),
    );
    return res.text;
  }

  // --- Sessions -------------------------------------------------------------

  /// Opens a multi-turn conversation.
  ///
  /// Tools are called natively where the OS supports it and through a
  /// prompt-based loop elsewhere ([OnDeviceAiCapabilities.toolCalling] tells
  /// which). If the native model is not ready and a fallback adapter exists,
  /// the session runs on the fallback.
  Future<OnDeviceAiSession> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
    int maxToolRounds = 5,
  }) async {
    final instruction = systemInstruction ?? _defaultInstructions;
    final toolList = tools ?? const <OnDeviceAiTool>[];

    final native = await availability();
    if (!native.isReady) {
      final adapter = fallbackAdapter;
      if (adapter != null && await _fallbackReady()) {
        final composed = _withToolPrompt(instruction, toolList);
        return OnDeviceAiSession.fromBackend(
          sessionId: 'fallback_${DateTime.now().microsecondsSinceEpoch}',
          backend: FallbackSessionBackend(
            adapter: adapter,
            systemInstruction: composed,
          ),
          systemInstruction: instruction,
          tools: toolList,
          config: config,
          maxToolRounds: maxToolRounds,
        );
      }
      throw OnDeviceAiUnavailableException(native.message);
    }

    final info = await _platform.getPlatformInfo();
    final nativeTools = info.supportsToolCalling;
    final sessionId = await _platform.createSession(
      systemInstruction: nativeTools
          ? instruction
          : _withToolPrompt(instruction, toolList),
      tools: nativeTools && toolList.isNotEmpty ? toolList : null,
      config: config,
    );
    final platformBackend = PlatformSessionBackend(
      sessionId: sessionId,
      platform: _platform,
      nativeTools: nativeTools,
      nativeStructuredOutput: info.supportsStructuredOutput,
      supportsImages: info.supportsVision,
      exactTokenCounts: info.supportsExactTokenCounts,
    );
    final adapter = fallbackAdapter;
    return OnDeviceAiSession.fromBackend(
      sessionId: sessionId,
      // If the OS model fails with "unavailable" mid-use, carry on with the
      // fallback instead of surfacing the error.
      backend: adapter == null
          ? platformBackend
          : FailoverSessionBackend(
              primary: platformBackend,
              adapter: adapter,
              fallbackInstruction: _withToolPrompt(instruction, toolList),
            ),
      systemInstruction: instruction,
      tools: toolList,
      config: config,
      maxToolRounds: maxToolRounds,
    );
  }

  String? _withToolPrompt(String? instruction, List<OnDeviceAiTool> tools) {
    if (tools.isEmpty) return instruction;
    final block = emulatedToolInstruction(tools);
    return instruction == null || instruction.isEmpty
        ? block
        : '$instruction\n\n$block';
  }
}

/// Former name of [FlutterDeviceAi].
@Deprecated('Use FlutterDeviceAi')
typedef FlutterOnDeviceAi = FlutterDeviceAi;
