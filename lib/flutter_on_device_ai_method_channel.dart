import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_on_device_ai_platform_interface.dart';
import 'src/models/ai_response.dart';
import 'src/models/capabilities.dart';
import 'src/models/generation_config.dart';
import 'src/models/model_status.dart';
import 'src/models/tool.dart';

/// An implementation of [FlutterOnDeviceAiPlatform] that uses method channels.
class MethodChannelFlutterOnDeviceAi extends FlutterOnDeviceAiPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_on_device_ai');

  @visibleForTesting
  final eventChannel = const EventChannel('flutter_on_device_ai/stream');

  @visibleForTesting
  final downloadEventChannel = const EventChannel('flutter_on_device_ai/download_stream');

  final Map<String, OnDeviceAiTool> _registeredTools = {};
  bool _methodHandlerConfigured = false;

  void _ensureMethodHandler() {
    if (_methodHandlerConfigured) return;
    _methodHandlerConfigured = true;
    methodChannel.setMethodCallHandler(_handleNativeMethodCall);
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onToolCall') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final toolName = args['name'] as String?;
      final toolArgs = Map<String, dynamic>.from(args['arguments'] as Map? ?? {});

      if (toolName != null && _registeredTools.containsKey(toolName)) {
        final tool = _registeredTools[toolName]!;
        try {
          final result = await tool.onCall(toolArgs);
          return {'result': result};
        } catch (e) {
          if (e is OnDeviceAiToolException) {
            return {'error': e.message, 'details': e.details};
          }
          return {'error': e.toString()};
        }
      }
      return {'error': 'Tool "$toolName" not found in registered tools.'};
    }
    throw PlatformException(
      code: 'UNIMPLEMENTED',
      message: 'Method ${call.method} not implemented on Dart side',
    );
  }

  @override
  Future<bool> isAvailable() async {
    _ensureMethodHandler();
    final result = await methodChannel.invokeMethod<bool>('isAvailable');
    return result ?? false;
  }

  @override
  Future<String> availabilityReason() async {
    final result = await methodChannel.invokeMethod<String>('availabilityReason');
    return result ?? 'Unknown availability reason.';
  }

  @override
  Future<bool> initialize({String? instructions}) async {
    _ensureMethodHandler();
    final result = await methodChannel.invokeMethod<bool>('initialize', {
      'instructions': ?instructions,
    });
    return result ?? false;
  }

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) async {
    _ensureMethodHandler();
    final map = await methodChannel.invokeMapMethod<String, dynamic>('generateText', {
      'prompt': prompt,
      'config': ?config?.toMap(),
      'instructions': ?instructions,
    });
    return AiResponse.fromMap(map ?? {'text': ''});
  }

  @override
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    _ensureMethodHandler();
    final controller = StreamController<String>();

    // Send the initiation call
    methodChannel.invokeMethod<void>('startStream', {
      'prompt': prompt,
      'config': ?config?.toMap(),
      'instructions': ?instructions,
    }).catchError((e) {
      if (!controller.isClosed) controller.addError(e);
    });

    final subscription = eventChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is String) {
          controller.add(data);
        } else if (data is Map && data.containsKey('chunk')) {
          controller.add(data['chunk'].toString());
        }
      },
      onError: (err) {
        if (!controller.isClosed) controller.addError(err);
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: true,
    );

    controller.onCancel = () {
      subscription.cancel();
      methodChannel.invokeMethod<void>('stopStream');
    };

    return controller.stream;
  }

  @override
  Future<void> registerTools(List<OnDeviceAiTool> tools) async {
    _ensureMethodHandler();
    _registeredTools.clear();
    for (final t in tools) {
      _registeredTools[t.name] = t;
    }

    final toolDeclarations = tools.map((t) => t.toMap()).toList();
    await methodChannel.invokeMethod<void>('registerTools', {
      'tools': toolDeclarations,
    });
  }

  @override
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() async {
    final map = await methodChannel.invokeMapMethod<String, dynamic>('getPlatformInfo');
    return OnDeviceAiPlatformInfo.fromMap(map ?? {'backend': 'unsupported'});
  }

  @override
  Future<ModelFeatureStatus> getModelStatus() async {
    final status = await methodChannel.invokeMethod<String>('getModelStatus');
    return ModelFeatureStatus.values.firstWhere(
      (s) => s.name == status,
      orElse: () => ModelFeatureStatus.unavailable,
    );
  }

  @override
  Stream<ModelDownloadStatus> downloadModel() {
    return downloadEventChannel.receiveBroadcastStream().map((data) {
      if (data is Map) {
        return ModelDownloadStatus.fromMap(Map<String, dynamic>.from(data));
      }
      return const ModelDownloadStatus(status: ModelFeatureStatus.downloading);
    });
  }

  @override
  Future<bool> openAICorePlayStore() async {
    final result = await methodChannel.invokeMethod<bool>('openAICorePlayStore');
    return result ?? false;
  }

  // --- Session Management ---

  @override
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) async {
    _ensureMethodHandler();
    if (tools != null) {
      for (final t in tools) {
        _registeredTools[t.name] = t;
      }
    }

    final sessionId = await methodChannel.invokeMethod<String>('createSession', {
      'systemInstruction': ?systemInstruction,
      'tools': ?tools?.map((t) => t.toMap()).toList(),
      'config': ?config?.toMap(),
    });
    return sessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> sessionAddQuery(String sessionId, String text) async {
    await methodChannel.invokeMethod<void>('sessionAddQuery', {
      'sessionId': sessionId,
      'text': text,
    });
  }

  @override
  Future<void> sessionAddImage(String sessionId, Uint8List imageBytes, {String mimeType = 'image/jpeg'}) async {
    await methodChannel.invokeMethod<void>('sessionAddImage', {
      'sessionId': sessionId,
      'imageBytes': imageBytes,
      'mimeType': mimeType,
    });
  }

  @override
  Future<AiResponse> sessionGetResponse(String sessionId, {GenerationConfig? config}) async {
    final map = await methodChannel.invokeMapMethod<String, dynamic>('sessionGetResponse', {
      'sessionId': sessionId,
      'config': ?config?.toMap(),
    });
    return AiResponse.fromMap(map ?? {'text': ''});
  }

  @override
  Stream<String> sessionGetResponseStream(String sessionId, {GenerationConfig? config}) {
    final controller = StreamController<String>();

    methodChannel.invokeMethod<void>('sessionStartStream', {
      'sessionId': sessionId,
      'config': ?config?.toMap(),
    }).catchError((e) {
      if (!controller.isClosed) controller.addError(e);
    });

    final channelName = 'flutter_on_device_ai/session_stream_$sessionId';
    final sessionChannel = EventChannel(channelName);

    final sub = sessionChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is String) {
          controller.add(data);
        } else if (data is Map && data.containsKey('chunk')) {
          controller.add(data['chunk'].toString());
        }
      },
      onError: (err) {
        if (!controller.isClosed) controller.addError(err);
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: true,
    );

    controller.onCancel = () {
      sub.cancel();
      methodChannel.invokeMethod<void>('sessionStopGeneration', {'sessionId': sessionId});
    };

    return controller.stream;
  }

  @override
  Future<int> sessionCountTokens(String sessionId, {String? text}) async {
    final count = await methodChannel.invokeMethod<int>('sessionCountTokens', {
      'sessionId': sessionId,
      'text': ?text,
    });
    return count ?? 0;
  }

  @override
  Future<void> sessionStopGeneration(String sessionId) async {
    await methodChannel.invokeMethod<void>('sessionStopGeneration', {
      'sessionId': sessionId,
    });
  }

  @override
  Future<void> sessionClose(String sessionId) async {
    await methodChannel.invokeMethod<void>('sessionClose', {
      'sessionId': sessionId,
    });
  }
}
