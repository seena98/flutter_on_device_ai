import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai_platform_interface.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterOnDeviceAiPlatform
    with MockPlatformInterfaceMixin
    implements FlutterOnDeviceAiPlatform {
  @override
  Future<bool> isAvailable() => Future.value(true);

  @override
  Future<String> availabilityReason() => Future.value('Mock Platform Ready');

  @override
  Future<bool> initialize({String? instructions}) => Future.value(true);

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    if (config?.responseFormat == ResponseFormat.json) {
      return Future.value(AiResponse(
        text: '{"result": "mock_json", "count": 42}',
        tokenCount: 15,
        generationTimeMs: 20,
      ));
    }
    return Future.value(AiResponse(
      text: 'Mock response for: $prompt',
      tokenCount: 10,
      generationTimeMs: 15,
    ));
  }

  @override
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) {
    return Stream.fromIterable(['Mock ', 'stream ', 'chunk']);
  }

  @override
  Future<void> registerTools(List<OnDeviceAiTool> tools) => Future.value();

  @override
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() {
    return Future.value(const OnDeviceAiPlatformInfo(
      backend: OnDeviceAiBackend.appleFoundationModels,
      supportsToolCalling: true,
      supportsStructuredOutput: true,
      supportsVision: true,
      supportsModelDownload: true,
      supportsPlayStoreRedirect: false,
    ));
  }

  @override
  Future<ModelFeatureStatus> getModelStatus() => Future.value(ModelFeatureStatus.available);

  @override
  Stream<ModelDownloadStatus> downloadModel() {
    return Stream.value(const ModelDownloadStatus(
      status: ModelFeatureStatus.available,
      progress: 1.0,
    ));
  }

  @override
  Future<bool> openAICorePlayStore() => Future.value(false);

  @override
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) => Future.value('mock_session_id');

  @override
  Future<void> sessionAddQuery(String sessionId, String text) => Future.value();

  @override
  Future<void> sessionAddImage(String sessionId, imageBytes, {String mimeType = 'image/jpeg'}) => Future.value();

  @override
  Future<AiResponse> sessionGetResponse(String sessionId, {GenerationConfig? config}) {
    return Future.value(AiResponse(text: 'Mock session reply'));
  }

  @override
  Stream<String> sessionGetResponseStream(String sessionId, {GenerationConfig? config}) {
    return Stream.fromIterable(['Session ', 'chunk']);
  }

  @override
  Future<int> sessionCountTokens(String sessionId, {String? text}) => Future.value(7);

  @override
  Future<void> sessionStopGeneration(String sessionId) => Future.value();

  @override
  Future<void> sessionClose(String sessionId) => Future.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final FlutterOnDeviceAiPlatform initialPlatform = FlutterOnDeviceAiPlatform.instance;

  test('$MethodChannelFlutterOnDeviceAi is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterOnDeviceAi>());
  });

  group('FlutterOnDeviceAi with Mock Platform', () {
    late FlutterOnDeviceAi ai;

    setUp(() {
      FlutterOnDeviceAiPlatform.instance = MockFlutterOnDeviceAiPlatform();
      ai = FlutterOnDeviceAi();
    });

    test('isAvailable returns true', () async {
      expect(await ai.isAvailable(), true);
    });

    test('generateText returns valid AiResponse', () async {
      final res = await ai.generateText(prompt: 'Hello AI');
      expect(res.text, 'Mock response for: Hello AI');
      expect(res.tokenCount, 10);
      expect(res.generationTimeMs, 15);
    });

    test('generateText structured JSON output decoding', () async {
      final res = await ai.generateText(
        prompt: 'Give me JSON',
        config: const GenerationConfig(responseFormat: ResponseFormat.json),
      );
      expect(res.json, isNotNull);
      expect(res.json!['result'], 'mock_json');
      expect(res.json!['count'], 42);
    });

    test('generateTextStream yields chunks', () async {
      final chunks = await ai.generateTextStream(prompt: 'Stream please').toList();
      expect(chunks, ['Mock ', 'stream ', 'chunk']);
    });

    test('createSession works and can generate turn', () async {
      final session = await ai.createSession(systemInstruction: 'Be helpful');
      expect(session.sessionId, 'mock_session_id');

      await session.addQuery('What is Flutter?');
      final reply = await session.getResponse();
      expect(reply.text, 'Mock session reply');

      final tokens = await session.countTokens(text: 'sample');
      expect(tokens, 7);

      await session.close();
      expect(session.isClosed, true);
    });

    test('OnDeviceUiGenerator parses and repairs truncated JSON', () {
      const rawText = '''
```json
{
  "title": "Running Goal",
  "icon": "fitness_center",
  "tone": "motivational",
  "blurb": "Keep moving every day",
  "blocks": [
    {"type": "stat", "label": "Distance", "value": "5 km", "subtext": "This week"}
  ]
}
```''';

      final spec = OnDeviceUiGenerator.parseModelOutput(rawText);
      expect(spec, isNotNull);
      expect(spec!.title, 'Running Goal');
      expect(spec.icon, 'fitness_center');
      expect(spec.blocks.length, 1);
      expect(spec.blocks.first['type'], 'stat');

      final componentMaps = spec.toComponentMaps();
      expect(componentMaps.length, 1);
      expect(componentMaps.first['type'], 'stat');
      expect(componentMaps.first['id'], 'block_0');
    });

    test('GemmaFallbackAdapter activates when configured', () async {
      final fallbackAi = FlutterOnDeviceAi.withFallback(
        fallbackAdapter: GemmaFallbackAdapter(modelPath: 'assets/gemma.bin'),
      );
      expect(await fallbackAi.isAvailable(), true);
    });
  });
}
