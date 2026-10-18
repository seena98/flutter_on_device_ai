import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelFlutterOnDeviceAi platform;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void mockMethods(Future<Object?> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(platform.methodChannel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls.clear();
    platform = MethodChannelFlutterOnDeviceAi();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platform.methodChannel, null);
    messenger.setMockStreamHandler(platform.eventChannel, null);
    messenger.setMockStreamHandler(platform.downloadEventChannel, null);
  });

  test('getAvailability and getPlatformInfo decode native maps', () async {
    mockMethods((call) async {
      return switch (call.method) {
        'getAvailability' => {
          'status': 'downloadable',
          'reason': 'modelNotReady',
          'message': 'x',
        },
        'getPlatformInfo' => {
          'backend': 'androidMlKitGenAi',
          'supportsExactTokenCounts': true,
        },
        _ => null,
      };
    });
    final a = await platform.getAvailability();
    expect(a.status, ModelFeatureStatus.downloadable);
    expect(a.reason, AvailabilityReason.modelNotReady);
    final info = await platform.getPlatformInfo();
    expect(info.backend, OnDeviceAiBackend.androidMlKitGenAi);
    expect(info.supportsExactTokenCounts, isTrue);
  });

  test('native error codes become typed exceptions', () async {
    mockMethods(
      (call) async =>
          throw PlatformException(code: 'SESSION_BUSY', message: 'busy'),
    );
    await expectLater(
      platform.sessionGetResponse('s'),
      throwsA(isA<OnDeviceAiSessionBusyException>()),
    );
    mockMethods((call) async => throw PlatformException(code: 'CANCELLED'));
    await expectLater(
      platform.sessionStopGeneration('s'),
      throwsA(isA<OnDeviceAiCancelledException>()),
    );
    mockMethods(
      (call) async =>
          throw PlatformException(code: 'UNAVAILABLE', message: 'no'),
    );
    await expectLater(
      platform.createSession(),
      throwsA(isA<OnDeviceAiUnavailableException>()),
    );
  });

  test('session lifecycle sends the expected arguments', () async {
    mockMethods(
      (call) async => switch (call.method) {
        'sessionGetResponse' => {
          'text': 'hello',
          'tokenCount': 2,
          'generationTimeMs': 9,
        },
        'sessionCountTokens' => 7,
        _ => null,
      },
    );
    final id = await platform.createSession(
      systemInstruction: 'sys',
      config: const GenerationConfig(temperature: 0.2),
    );
    await platform.sessionAddQuery(id, 'hi');
    final res = await platform.sessionGetResponse(
      id,
      config: const GenerationConfig(
        responseFormat: ResponseFormat.json,
        schema: {'type': 'object'},
      ),
    );
    expect(res.text, 'hello');
    expect(res.generationTimeMs, 9);
    expect(await platform.sessionCountTokens(id, text: 'abc'), 7);
    await platform.sessionClose(id);

    expect(calls.map((c) => c.method), [
      'createSession',
      'sessionAddQuery',
      'sessionGetResponse',
      'sessionCountTokens',
      'sessionClose',
    ]);
    expect(calls.first.arguments['sessionId'], id);
    expect(calls.first.arguments['systemInstruction'], 'sys');
    expect(calls[2].arguments['config']['responseFormat'], 'json');
  });

  test('native tool callbacks run the Dart tool, scoped per session', () async {
    mockMethods((call) async => null);
    final id = await platform.createSession(
      tools: [
        OnDeviceAiTool(
          name: 'add',
          description: 'adds',
          parameters: const [
            ToolParameter(
              name: 'a',
              type: ToolArgumentType.integer,
              description: 'a',
            ),
          ],
          onCall: (args) => {'sum': (args['a'] as int) + 1},
        ),
        OnDeviceAiTool(
          name: 'boom',
          description: 'fails',
          parameters: const [],
          onCall: (args) => throw const OnDeviceAiToolException('nope'),
        ),
      ],
    );

    Future<Object?> callTool(
      String session,
      String name,
      Map<String, Object?> args,
    ) async {
      final done = Completer<ByteData?>();
      await messenger.handlePlatformMessage(
        platform.methodChannel.name,
        platform.methodChannel.codec.encodeMethodCall(
          MethodCall('onToolCall', {
            'sessionId': session,
            'name': name,
            'arguments': args,
          }),
        ),
        done.complete,
      );
      return platform.methodChannel.codec.decodeEnvelope((await done.future)!);
    }

    expect((await callTool(id, 'add', {'a': 1})), {
      'result': {'sum': 2},
    });
    expect((await callTool(id, 'boom', {})), {'error': 'nope'});
    expect(
      (await callTool('other', 'add', {'a': 1})),
      containsPair('error', contains('not registered')),
    );
    await platform.sessionClose(id);
    expect(
      (await callTool(id, 'add', {'a': 1})),
      containsPair('error', contains('not registered')),
    );
  });

  test('streams are demultiplexed by session id', () async {
    late MockStreamHandlerEventSink sink;
    messenger.setMockStreamHandler(
      platform.eventChannel,
      MockStreamHandler.inline(onListen: (args, events) => sink = events),
    );
    mockMethods((call) async {
      if (call.method == 'sessionStartStream') {
        final id = call.arguments['sessionId'] as String;
        scheduleMicrotask(() {
          sink.success({'sessionId': id, 'type': 'chunk', 'text': 'A'});
          sink.success({
            'sessionId': 'unrelated',
            'type': 'chunk',
            'text': 'X',
          });
          sink.success({'sessionId': id, 'type': 'chunk', 'text': 'B'});
          sink.success({'sessionId': id, 'type': 'done'});
        });
      }
      return null;
    });
    expect(await platform.sessionGetResponseStream('s1').toList(), ['A', 'B']);
  });

  test('stream error events surface as typed errors', () async {
    late MockStreamHandlerEventSink sink;
    messenger.setMockStreamHandler(
      platform.eventChannel,
      MockStreamHandler.inline(onListen: (args, events) => sink = events),
    );
    mockMethods((call) async {
      scheduleMicrotask(
        () => sink.success({
          'sessionId': 's2',
          'type': 'error',
          'code': 'CANCELLED',
          'message': 'stopped',
        }),
      );
      return null;
    });
    await expectLater(
      platform.sessionGetResponseStream('s2').toList(),
      throwsA(isA<OnDeviceAiCancelledException>()),
    );
  });

  test('cancelling a stream asks native to stop', () async {
    late MockStreamHandlerEventSink sink;
    messenger.setMockStreamHandler(
      platform.eventChannel,
      MockStreamHandler.inline(onListen: (args, events) => sink = events),
    );
    mockMethods((call) async => null);
    final sub = platform.sessionGetResponseStream('s3').listen((_) {});
    await Future<void>.delayed(Duration.zero);
    sink.success({'sessionId': 's3', 'type': 'chunk', 'text': 'x'});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(calls.map((c) => c.method), contains('sessionStopGeneration'));
  });

  test('downloadModel maps progress maps', () async {
    messenger.setMockStreamHandler(
      platform.downloadEventChannel,
      MockStreamHandler.inline(
        onListen: (args, events) {
          events.success({
            'status': 'downloading',
            'progress': 0.5,
            'totalBytes': 10,
          });
          events.success({'status': 'available', 'progress': 1.0});
          events.endOfStream();
        },
      ),
    );
    final events = await platform.downloadModel().toList();
    expect(events.map((e) => e.status), [
      ModelFeatureStatus.downloading,
      ModelFeatureStatus.available,
    ]);
    expect(events.first.progress, 0.5);
    expect(events.first.totalBytes, 10);
  });
}
