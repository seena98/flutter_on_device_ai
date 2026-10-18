import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'flutter_on_device_ai_platform_interface.dart';
import 'src/exceptions.dart';
import 'src/models/ai_response.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';
import 'src/util.dart';

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}

/// Web implementation backed by the Prompt API (`LanguageModel`) that Chromium
/// browsers ship with Gemini Nano.
class FlutterOnDeviceAiWeb extends FlutterOnDeviceAiPlatform {
  FlutterOnDeviceAiWeb();

  static void registerWith(Registrar registrar) {
    FlutterOnDeviceAiPlatform.instance = FlutterOnDeviceAiWeb();
  }

  final Map<String, _WebSession> _sessions = {};
  int _counter = 0;

  static const _languages = ['en'];

  JSObject? get _languageModel {
    final v = globalContext.getProperty<JSAny?>('LanguageModel'.toJS);
    return v.isUndefinedOrNull ? null : v as JSObject;
  }

  Map<String, Object?> get _ioOptions => {
    'expectedInputs': [
      {'type': 'text', 'languages': _languages},
    ],
    'expectedOutputs': [
      {'type': 'text', 'languages': _languages},
    ],
  };

  Future<String> _rawAvailability() async {
    final lm = _languageModel;
    if (lm == null) return 'missing';
    try {
      final promise = lm.callMethod<JSPromise<JSString>>(
        'availability'.toJS,
        _ioOptions.jsify(),
      );
      return (await promise.toDart).toDart;
    } catch (_) {
      return 'unavailable';
    }
  }

  @override
  Future<OnDeviceAiAvailability> getAvailability() async {
    final raw = await _rawAvailability();
    switch (raw) {
      case 'available':
        return const OnDeviceAiAvailability(
          status: ModelFeatureStatus.available,
          reason: AvailabilityReason.ready,
          message: 'Chrome built-in AI (Gemini Nano) is ready.',
        );
      case 'downloadable':
        return const OnDeviceAiAvailability(
          status: ModelFeatureStatus.downloadable,
          reason: AvailabilityReason.modelNotReady,
          message:
              'The browser can download its built-in model. Call '
              'ensureReady() from a click or tap.',
        );
      case 'downloading':
        return const OnDeviceAiAvailability(
          status: ModelFeatureStatus.downloading,
          reason: AvailabilityReason.modelNotReady,
          message: 'The browser is downloading its built-in model.',
        );
      case 'missing':
        return const OnDeviceAiAvailability(
          status: ModelFeatureStatus.unavailable,
          reason: AvailabilityReason.browserUnsupported,
          message:
              'This browser does not expose the Prompt API. Use desktop '
              'Chrome or Edge with the built-in AI enabled.',
        );
      default:
        return const OnDeviceAiAvailability(
          status: ModelFeatureStatus.unavailable,
          reason: AvailabilityReason.deviceNotEligible,
          message:
              'The browser reports its built-in model as unavailable '
              '(unsupported hardware, too little disk space or disabled).',
        );
    }
  }

  @override
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() async {
    final present = _languageModel != null;
    return OnDeviceAiPlatformInfo(
      backend: present
          ? OnDeviceAiBackend.chromePromptApi
          : OnDeviceAiBackend.unsupported,
      supportsStructuredOutput: present,
      supportsExactTokenCounts: present,
      supportsModelDownload: present,
      diagnosticNotes: present
          ? 'Chromium Prompt API (LanguageModel)'
          : 'LanguageModel global not found',
    );
  }

  @override
  Stream<ModelDownloadStatus> downloadModel() {
    final controller = StreamController<ModelDownloadStatus>();
    () async {
      try {
        final raw = await _rawAvailability();
        if (raw == 'available') {
          controller.add(
            const ModelDownloadStatus(
              status: ModelFeatureStatus.available,
              progress: 1,
            ),
          );
          return;
        }
        if (raw == 'missing' || raw == 'unavailable') {
          controller.add(
            const ModelDownloadStatus(
              status: ModelFeatureStatus.unavailable,
              errorMessage: 'The built-in model is not supported here.',
            ),
          );
          return;
        }
        if (raw == 'downloadable' && !_userActivationActive()) {
          controller.addError(
            const OnDeviceAiUserActivationRequiredException(
              'Downloading the built-in model needs a user gesture. Call '
              'ensureReady() from a click or tap handler.',
            ),
          );
          return;
        }
        controller.add(
          const ModelDownloadStatus(
            status: ModelFeatureStatus.downloading,
            progress: 0,
          ),
        );
        final session = await _create(
          null,
          null,
          onProgress: (p) => controller.add(
            ModelDownloadStatus(
              status: ModelFeatureStatus.downloading,
              progress: p,
            ),
          ),
        );
        session.callMethod<JSAny?>('destroy'.toJS);
        controller.add(
          const ModelDownloadStatus(
            status: ModelFeatureStatus.available,
            progress: 1,
          ),
        );
      } catch (e) {
        controller.add(
          ModelDownloadStatus(
            status: ModelFeatureStatus.unavailable,
            errorMessage: _describe(e),
          ),
        );
      } finally {
        await controller.close();
      }
    }();
    return controller.stream;
  }

  bool _userActivationActive() {
    try {
      final nav = globalContext.getProperty<JSObject?>('navigator'.toJS);
      final ua = nav?.getProperty<JSObject?>('userActivation'.toJS);
      if (ua == null) return true; // cannot tell: let the browser decide
      return ua.getProperty<JSBoolean>('isActive'.toJS).toDart;
    } catch (_) {
      return true;
    }
  }

  // --- JS plumbing ----------------------------------------------------------

  Future<JSObject> _create(
    String? system,
    GenerationConfig? config, {
    void Function(double progress)? onProgress,
    JSObject? signal,
  }) async {
    final lm = _languageModel;
    if (lm == null) {
      throw const OnDeviceAiUnavailableException(
        'The Prompt API is not available in this browser.',
      );
    }
    final options = <String, Object?>{..._ioOptions};
    if (system != null && system.isNotEmpty) {
      options['initialPrompts'] = [
        {'role': 'system', 'content': system},
      ];
    }
    if (config?.temperature != null || config?.topK != null) {
      // Chrome requires temperature and topK together.
      final params = await _params(lm);
      options['temperature'] = config?.temperature ?? params.$1;
      options['topK'] = config?.topK ?? params.$2;
    }
    final jsOptions = options.jsify() as JSObject;
    if (signal != null) jsOptions.setProperty('signal'.toJS, signal);
    if (onProgress != null) {
      jsOptions.setProperty(
        'monitor'.toJS,
        ((JSObject monitor) {
          monitor.callMethod<JSAny?>(
            'addEventListener'.toJS,
            'downloadprogress'.toJS,
            ((JSObject event) {
              final loaded = event.getProperty<JSNumber?>('loaded'.toJS);
              if (loaded != null) onProgress(loaded.toDartDouble);
            }).toJS,
          );
        }).toJS,
      );
    }
    final promise = lm.callMethod<JSPromise<JSObject>>(
      'create'.toJS,
      jsOptions,
    );
    return await promise.toDart;
  }

  Future<(double, int)> _params(JSObject lm) async {
    try {
      final p = await lm.callMethod<JSPromise<JSObject?>>('params'.toJS).toDart;
      if (p != null) {
        return (
          p.getProperty<JSNumber>('defaultTemperature'.toJS).toDartDouble,
          p.getProperty<JSNumber>('defaultTopK'.toJS).toDartInt,
        );
      }
    } catch (_) {}
    return (1.0, 3);
  }

  String _describe(Object e) {
    // ignore: invalid_runtime_check_with_js_interop_types
    if (e is JSObject) {
      final msg = e.getProperty<JSString?>('message'.toJS)?.toDart;
      final name = e.getProperty<JSString?>('name'.toJS)?.toDart;
      return [name, msg].whereType<String>().join(': ');
    }
    return e.toString();
  }

  OnDeviceAiException _translate(Object e) {
    if (e is OnDeviceAiException) return e;
    final text = _describe(e);
    if (text.contains('AbortError')) {
      return const OnDeviceAiCancelledException();
    }
    if (text.contains('NotAllowedError')) {
      return OnDeviceAiUserActivationRequiredException(text);
    }
    if (text.contains('NotSupportedError')) {
      return OnDeviceAiUnsupportedException(text);
    }
    return OnDeviceAiGenerationException(text);
  }

  // --- sessions -------------------------------------------------------------

  _WebSession _session(String id) {
    final s = _sessions[id];
    if (s == null) {
      throw OnDeviceAiException(
        'Unknown session $id',
        code: 'SESSION_NOT_FOUND',
      );
    }
    return s;
  }

  @override
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) async {
    final id = 'web_${++_counter}';
    _sessions[id] = _WebSession(systemInstruction, config);
    return id;
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
    throw const OnDeviceAiUnsupportedException(
      'Image input is not supported by the Chrome Prompt API backend.',
    );
  }

  Future<JSObject> _ensureModel(_WebSession s, GenerationConfig? call) async {
    final existing = s.model;
    if (existing != null) {
      if (call?.maxTokens != null && kDebugMode && call!.maxTokens != 256) {
        debugPrint(
          'flutter_on_device_ai: the Prompt API has no max-token limit; '
          'maxTokens is ignored on the web.',
        );
      }
      return existing;
    }
    try {
      s.model = await _create(s.system, call ?? s.config);
    } catch (e) {
      throw _translate(e);
    }
    return s.model!;
  }

  Object? _promptOptions(_WebSession s, GenerationConfig? config) {
    s.abort = _AbortController();
    final options = <String, Object?>{}.jsify() as JSObject;
    options.setProperty('signal'.toJS, s.abort!.signal);
    final schema = config?.schema;
    if (config?.responseFormat == ResponseFormat.json && schema != null) {
      options.setProperty('responseConstraint'.toJS, schema.jsify());
    }
    return options;
  }

  @override
  Future<AiResponse> sessionGetResponse(
    String sessionId, {
    GenerationConfig? config,
  }) async {
    final s = _session(sessionId);
    final input = s.takeTurn();
    final watch = Stopwatch()..start();
    try {
      final model = await _ensureModel(s, config);
      final promise = model.callMethod<JSPromise<JSString>>(
        'prompt'.toJS,
        input.toJS,
        _promptOptions(s, config) as JSObject,
      );
      final text = (await promise.toDart).toDart;
      return AiResponse(
        text: text,
        tokenCount: estimateTokens(text),
        generationTimeMs: watch.elapsedMilliseconds,
      );
    } catch (e) {
      throw _translate(e);
    } finally {
      s.abort = null;
    }
  }

  @override
  Stream<String> sessionGetResponseStream(
    String sessionId, {
    GenerationConfig? config,
  }) async* {
    final s = _session(sessionId);
    final input = s.takeTurn();
    try {
      final model = await _ensureModel(s, config);
      final stream = model.callMethod<JSObject>(
        'promptStreaming'.toJS,
        input.toJS,
        _promptOptions(s, config) as JSObject,
      );
      final reader = stream.callMethod<JSObject>('getReader'.toJS);
      var full = '';
      while (true) {
        final result = await reader
            .callMethod<JSPromise<JSObject>>('read'.toJS)
            .toDart;
        if (result.getProperty<JSBoolean>('done'.toJS).toDart) break;
        final chunk = result.getProperty<JSString>('value'.toJS).toDart;
        // Older Chrome builds stream the whole text so far, newer ones deltas.
        final isCumulative = full.isNotEmpty && chunk.startsWith(full);
        final delta = isCumulative ? chunk.substring(full.length) : chunk;
        full = isCumulative ? chunk : full + chunk;
        if (delta.isNotEmpty) yield delta;
      }
    } catch (e) {
      throw _translate(e);
    } finally {
      s.abort = null;
    }
  }

  @override
  Future<int> sessionCountTokens(String sessionId, {String? text}) async {
    final s = _session(sessionId);
    final model = s.model;
    final probe = text ?? s.pending.join('\n');
    if (model == null) return estimateTokens(probe);
    try {
      for (final name in ['measureInputUsage', 'measureContextUsage']) {
        if (model.has(name)) {
          final n = await model
              .callMethod<JSPromise<JSNumber>>(name.toJS, probe.toJS)
              .toDart;
          return n.toDartInt;
        }
      }
    } catch (_) {}
    return estimateTokens(probe);
  }

  @override
  Future<void> sessionStopGeneration(String sessionId) async {
    _sessions[sessionId]?.abort?.abort();
  }

  @override
  Future<void> sessionClose(String sessionId) async {
    final s = _sessions.remove(sessionId);
    s?.abort?.abort();
    s?.model?.callMethod<JSAny?>('destroy'.toJS);
  }
}

class _WebSession {
  _WebSession(this.system, this.config);

  final String? system;
  final GenerationConfig? config;
  final List<String> pending = [];
  JSObject? model;
  _AbortController? abort;

  String takeTurn() {
    if (pending.isEmpty) {
      throw const OnDeviceAiException(
        'Nothing to answer: call addQuery() first.',
        code: 'EMPTY_TURN',
      );
    }
    final text = pending.join('\n');
    pending.clear();
    return text;
  }
}
