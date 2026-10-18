import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'flutter_on_device_ai_platform_interface.dart';
import 'src/models/ai_response.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';

@JS('eval')
external JSAny? _jsEval(String code);

/// Web implementation of [FlutterOnDeviceAiPlatform] interacting with
/// Chrome's built-in Prompt API (`window.ai` / `window.LanguageModel`).
class FlutterOnDeviceAiWeb extends FlutterOnDeviceAiPlatform {
  FlutterOnDeviceAiWeb();

  static void registerWith(Registrar registrar) {
    FlutterOnDeviceAiPlatform.instance = FlutterOnDeviceAiWeb();
  }

  final Map<String, dynamic> _sessions = {};
  String? _globalInstructions;

  bool _hasChromeBuiltInAi() {
    try {
      final res = _jsEval(
        '(typeof window !== "undefined" && (Boolean(window.ai?.languageModel) || Boolean(window.LanguageModel)))',
      );
      return res?.dartify() == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (!_hasChromeBuiltInAi()) return false;
    try {
      final res = _jsEval('''
        (async () => {
          if (window.ai?.languageModel) {
            const caps = await window.ai.languageModel.capabilities();
            return caps.available !== 'no';
          }
          if (window.LanguageModel) {
            const avail = await window.LanguageModel.availability();
            return avail !== 'unavailable';
          }
          return false;
        })()
      ''');
      if (res != null) {
        final promise = res as JSPromise<JSAny?>;
        final val = await promise.toDart;
        return val?.dartify() == true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Future<String> availabilityReason() async {
    if (!_hasChromeBuiltInAi()) {
      return 'Chrome Prompt API is not detected. Requires Chromium with chrome://flags/#prompt-api-for-gemini-nano enabled.';
    }
    return 'Prompt API detected and ready.';
  }

  @override
  Future<bool> initialize({String? instructions}) async {
    _globalInstructions = instructions;
    return await isAvailable();
  }

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final instr = instructions ?? _globalInstructions ?? '';

    if (!_hasChromeBuiltInAi()) {
      return AiResponse(
        text: '[Web Built-in AI prompt simulation: "$prompt"]',
        generationTimeMs: 10,
      );
    }

    try {
      final script =
          '''
        (async () => {
          const factory = window.ai?.languageModel || window.LanguageModel;
          const session = await factory.create({
            systemPrompt: ${instr.isNotEmpty ? '"$instr"' : 'undefined'}
          });
          const result = await session.prompt(${_escapeJs(prompt)});
          session.destroy?.();
          return result;
        })()
      ''';
      final res = _jsEval(script);
      if (res != null) {
        final promise = res as JSPromise<JSAny?>;
        final val = await promise.toDart;
        final output = val?.dartify()?.toString() ?? '';
        final duration = DateTime.now().millisecondsSinceEpoch - startTime;
        return AiResponse(text: output, generationTimeMs: duration);
      }
    } catch (e) {
      return AiResponse(
        text: 'Error generating text via Chrome Prompt API: $e',
      );
    }

    return AiResponse(text: '');
  }

  @override
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    final controller = StreamController<String>();

    if (!_hasChromeBuiltInAi()) {
      // Simulate stream
      scheduleMicrotask(() async {
        final words = '[Web Prompt API simulation for: $prompt]'.split(' ');
        for (final w in words) {
          await Future.delayed(const Duration(milliseconds: 30));
          controller.add('$w ');
        }
        await controller.close();
      });
      return controller.stream;
    }

    // Call through JS streaming if available
    scheduleMicrotask(() async {
      try {
        final res = await generateText(
          prompt: prompt,
          config: config,
          instructions: instructions,
        );
        controller.add(res.text);
      } catch (e) {
        controller.addError(e);
      } finally {
        await controller.close();
      }
    });

    return controller.stream;
  }

  @override
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() async {
    final hasAi = _hasChromeBuiltInAi();
    return OnDeviceAiPlatformInfo(
      backend: hasAi
          ? OnDeviceAiBackend.chromePromptApi
          : OnDeviceAiBackend.unsupported,
      supportsToolCalling: false,
      supportsStructuredOutput: hasAi,
      supportsVision: false,
      supportsModelDownload: hasAi,
      supportsPlayStoreRedirect: false,
      isConfigured: true,
      diagnosticNotes: hasAi
          ? 'Chrome Prompt API (window.ai) active'
          : 'Enable chrome://flags/#prompt-api-for-gemini-nano in Chrome Dev/Canary',
    );
  }

  @override
  Future<ModelFeatureStatus> getModelStatus() async {
    if (!_hasChromeBuiltInAi()) return ModelFeatureStatus.unavailable;
    return ModelFeatureStatus.available;
  }

  @override
  Stream<ModelDownloadStatus> downloadModel() {
    final controller = StreamController<ModelDownloadStatus>();
    scheduleMicrotask(() async {
      controller.add(
        const ModelDownloadStatus(
          status: ModelFeatureStatus.available,
          progress: 1.0,
        ),
      );
      await controller.close();
    });
    return controller.stream;
  }

  @override
  Future<void> registerTools(List<OnDeviceAiTool> tools) async {}

  @override
  Future<bool> openAICorePlayStore() async => false;

  // --- Session Management ---

  @override
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) async {
    final id = 'web_session_${DateTime.now().millisecondsSinceEpoch}';
    _sessions[id] = {
      'systemInstruction': systemInstruction,
      'transcript': <String>[],
    };
    return id;
  }

  @override
  Future<void> sessionAddQuery(String sessionId, String text) async {
    final session = _sessions[sessionId];
    if (session != null) {
      final transcript = session['transcript'] as List<String>;
      transcript.add('User: $text');
    }
  }

  @override
  Future<void> sessionAddImage(
    String sessionId,
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {}

  @override
  Future<AiResponse> sessionGetResponse(
    String sessionId, {
    GenerationConfig? config,
  }) async {
    final session = _sessions[sessionId];
    final transcript =
        (session?['transcript'] as List<String>?)?.join('\n') ?? '';
    final systemInstruction = session?['systemInstruction'] as String?;

    return await generateText(
      prompt: transcript,
      config: config,
      instructions: systemInstruction,
    );
  }

  @override
  Stream<String> sessionGetResponseStream(
    String sessionId, {
    GenerationConfig? config,
  }) {
    final session = _sessions[sessionId];
    final transcript =
        (session?['transcript'] as List<String>?)?.join('\n') ?? '';
    final systemInstruction = session?['systemInstruction'] as String?;

    return generateTextStream(
      prompt: transcript,
      config: config,
      instructions: systemInstruction,
    );
  }

  @override
  Future<int> sessionCountTokens(String sessionId, {String? text}) async {
    return (text?.length ?? 10) ~/ 4;
  }

  @override
  Future<void> sessionStopGeneration(String sessionId) async {}

  @override
  Future<void> sessionClose(String sessionId) async {
    _sessions.remove(sessionId);
  }

  static String _escapeJs(String input) {
    return '"${input.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
  }
}
