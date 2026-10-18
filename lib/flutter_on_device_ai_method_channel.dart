import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_on_device_ai_platform_interface.dart';
import 'src/exceptions.dart';
import 'src/models/ai_response.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';

/// [FlutterOnDeviceAiPlatform] backed by platform channels (Android, iOS,
/// macOS, Windows, Linux).
///
/// Wire protocol
/// * method channel `flutter_on_device_ai` — request / response calls and the
///   `onToolCall` callback from native to Dart,
/// * event channel `flutter_on_device_ai/events` — one multiplexed stream of
///   `{sessionId, type: chunk|done|error, ...}` events for streaming turns,
/// * event channel `flutter_on_device_ai/download` — model download progress.
class MethodChannelFlutterOnDeviceAi extends FlutterOnDeviceAiPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_on_device_ai');

  @visibleForTesting
  final eventChannel = const EventChannel('flutter_on_device_ai/events');

  @visibleForTesting
  final downloadEventChannel = const EventChannel(
    'flutter_on_device_ai/download',
  );

  final Map<String, Map<String, OnDeviceAiTool>> _toolsBySession = {};
  final Map<String, StreamController<String>> _streams = {};
  StreamSubscription<dynamic>? _eventSubscription;
  bool _handlerInstalled = false;
  final Random _random = Random();

  void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    methodChannel.setMethodCallHandler(_onNativeCall);
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    _installHandler();
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  Future<Map<String, dynamic>?> _invokeMap(
    String method, [
    Object? arguments,
  ]) async {
    _installHandler();
    try {
      return await methodChannel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  // --- native -> Dart -------------------------------------------------------

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'onToolCall') {
      throw PlatformException(
        code: 'UNIMPLEMENTED',
        message: 'Method ${call.method} not implemented on Dart side',
      );
    }
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final sessionId = args['sessionId'] as String? ?? '';
    final name = args['name'] as String?;
    final toolArgs = Map<String, dynamic>.from(args['arguments'] as Map? ?? {});

    final tool = _toolsBySession[sessionId]?[name];
    if (tool == null) {
      return {'error': 'Tool "$name" is not registered for this session.'};
    }
    try {
      return {'result': await tool.onCall(toolArgs)};
    } on OnDeviceAiToolException catch (e) {
      return {'error': e.message, if (e.details != null) 'details': e.details};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  void _ensureEvents() {
    if (_eventSubscription != null) return;
    _eventSubscription = eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error) {
        for (final c in _streams.values.toList()) {
          if (!c.isClosed) c.addError(error);
        }
      },
    );
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final id = event['sessionId'] as String?;
    final controller = _streams[id];
    if (controller == null || controller.isClosed) return;
    if (event['type'] != 'chunk') _streams.remove(id);
    switch (event['type']) {
      case 'chunk':
        controller.add(event['text'] as String? ?? '');
      case 'error':
        controller.addError(
          mapPlatformException(
            PlatformException(
              code: event['code'] as String? ?? 'GENERATION_FAILED',
              message: event['message'] as String?,
            ),
          ),
        );
        controller.close();
      case 'done':
        controller.close();
    }
  }

  // --- availability ---------------------------------------------------------

  @override
  Future<OnDeviceAiAvailability> getAvailability() async {
    final map = await _invokeMap('getAvailability');
    return map == null
        ? const OnDeviceAiAvailability(
            status: ModelFeatureStatus.unavailable,
            reason: AvailabilityReason.platformUnsupported,
            message: 'No native implementation answered.',
          )
        : OnDeviceAiAvailability.fromMap(map);
  }

  @override
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() async {
    final map = await _invokeMap('getPlatformInfo');
    return OnDeviceAiPlatformInfo.fromMap(map ?? {'backend': 'unsupported'});
  }

  @override
  Stream<ModelDownloadStatus> downloadModel() {
    return downloadEventChannel
        .receiveBroadcastStream()
        .map((data) {
          if (data is Map) {
            return ModelDownloadStatus.fromMap(Map<String, dynamic>.from(data));
          }
          return const ModelDownloadStatus(
            status: ModelFeatureStatus.downloading,
          );
        })
        .handleError((Object e) {
          if (e is PlatformException) throw mapPlatformException(e);
          throw e;
        });
  }

  @override
  Future<bool> openAICorePlayStore() async =>
      await _invoke<bool>('openAICorePlayStore') ?? false;

  // --- sessions -------------------------------------------------------------

  String _newSessionId() =>
      's${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 20).toRadixString(36)}';

  @override
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) async {
    final id = _newSessionId();
    if (tools != null && tools.isNotEmpty) {
      _toolsBySession[id] = {for (final t in tools) t.name: t};
    }
    try {
      await _invoke<void>('createSession', {
        'sessionId': id,
        'systemInstruction': ?systemInstruction,
        'tools': ?tools?.map((t) => t.toMap()).toList(),
        'config': ?config?.toMap(),
      });
    } catch (_) {
      _toolsBySession.remove(id);
      rethrow;
    }
    return id;
  }

  @override
  Future<void> sessionAddQuery(String sessionId, String text) =>
      _invoke<void>('sessionAddQuery', {'sessionId': sessionId, 'text': text});

  @override
  Future<void> sessionAddImage(
    String sessionId,
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) => _invoke<void>('sessionAddImage', {
    'sessionId': sessionId,
    'imageBytes': imageBytes,
    'mimeType': mimeType,
  });

  @override
  Future<AiResponse> sessionGetResponse(
    String sessionId, {
    GenerationConfig? config,
  }) async {
    final map = await _invokeMap('sessionGetResponse', {
      'sessionId': sessionId,
      'config': ?config?.toMap(),
    });
    return AiResponse.fromMap(map ?? {'text': ''});
  }

  @override
  Stream<String> sessionGetResponseStream(
    String sessionId, {
    GenerationConfig? config,
  }) {
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        _ensureEvents();
        _streams[sessionId] = controller;
        _invoke<void>('sessionStartStream', {
          'sessionId': sessionId,
          'config': ?config?.toMap(),
        }).catchError((Object e) {
          if (!controller.isClosed) {
            controller.addError(e);
            controller.close();
          }
        });
      },
      onCancel: () async {
        final wasOpen = _streams.remove(sessionId) == controller;
        if (wasOpen && !controller.isClosed) {
          try {
            await _invoke<void>('sessionStopGeneration', {
              'sessionId': sessionId,
            });
          } catch (_) {}
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<int> sessionCountTokens(String sessionId, {String? text}) async =>
      await _invoke<int>('sessionCountTokens', {
        'sessionId': sessionId,
        'text': ?text,
      }) ??
      0;

  @override
  Future<void> sessionStopGeneration(String sessionId) =>
      _invoke<void>('sessionStopGeneration', {'sessionId': sessionId});

  @override
  Future<void> sessionClose(String sessionId) async {
    _toolsBySession.remove(sessionId);
    _streams.remove(sessionId);
    await _invoke<void>('sessionClose', {'sessionId': sessionId});
  }
}

/// Converts a native error into the matching typed exception.
OnDeviceAiException mapPlatformException(PlatformException e) {
  final message = e.message ?? e.code;
  return switch (e.code) {
    'UNAVAILABLE' => OnDeviceAiUnavailableException(message),
    'UNSUPPORTED' => OnDeviceAiUnsupportedException(message),
    'CANCELLED' => OnDeviceAiCancelledException(message),
    'SESSION_BUSY' => OnDeviceAiSessionBusyException(message),
    'USER_ACTIVATION_REQUIRED' => OnDeviceAiUserActivationRequiredException(
      message,
    ),
    _ => OnDeviceAiGenerationException(message),
  };
}
