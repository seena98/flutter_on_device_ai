import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelFlutterOnDeviceAi platform = MethodChannelFlutterOnDeviceAi();
  const MethodChannel channel = MethodChannel('flutter_on_device_ai');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'isAvailable':
          return true;
        case 'availabilityReason':
          return 'On-device channel ready';
        case 'initialize':
          return true;
        case 'generateText':
          return {
            'text': 'Method channel response',
            'tokenCount': 12,
            'generationTimeMs': 24,
          };
        case 'getPlatformInfo':
          return {
            'backend': 'appleFoundationModels',
            'supportsToolCalling': true,
            'supportsStructuredOutput': true,
            'supportsVision': true,
            'supportsModelDownload': true,
            'supportsPlayStoreRedirect': false,
            'isConfigured': true,
          };
        case 'createSession':
          return 'chan_session_1';
        case 'sessionGetResponse':
          return {
            'text': 'Session reply over channel',
            'tokenCount': 8,
          };
        case 'sessionCountTokens':
          return 14;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isAvailable via method channel', () async {
    expect(await platform.isAvailable(), true);
  });

  test('generateText via method channel', () async {
    final res = await platform.generateText(prompt: 'Test prompt');
    expect(res.text, 'Method channel response');
    expect(res.tokenCount, 12);
    expect(res.generationTimeMs, 24);
  });

  test('getPlatformInfo via method channel', () async {
    final info = await platform.getPlatformInfo();
    expect(info.supportsToolCalling, true);
    expect(info.supportsStructuredOutput, true);
  });

  test('session lifecycle via method channel', () async {
    final sessionId = await platform.createSession(systemInstruction: 'Test');
    expect(sessionId, 'chan_session_1');

    final reply = await platform.sessionGetResponse(sessionId);
    expect(reply.text, 'Session reply over channel');

    final tokens = await platform.sessionCountTokens(sessionId, text: 'abc');
    expect(tokens, 14);
  });
}
