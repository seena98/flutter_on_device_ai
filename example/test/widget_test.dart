import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter_on_device_ai_example/main.dart';

class MockPlatform
    with MockPlatformInterfaceMixin
    implements FlutterOnDeviceAiPlatform {
  @override
  Future<bool> isAvailable() => Future.value(true);

  @override
  Future<String> availabilityReason() => Future.value('Ready');

  @override
  Future<bool> initialize({String? instructions}) => Future.value(true);

  @override
  Future<AiResponse> generateText({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) => Future.value(AiResponse(text: 'Mock Response'));

  @override
  Stream<String> generateTextStream({
    required String prompt,
    GenerationConfig? config,
    String? instructions,
  }) => Stream.fromIterable(['Chunk 1 ', 'Chunk 2']);

  @override
  Future<void> registerTools(List<OnDeviceAiTool> tools) => Future.value();

  @override
  Future<OnDeviceAiPlatformInfo> getPlatformInfo() => Future.value(
    const OnDeviceAiPlatformInfo(
      backend: OnDeviceAiBackend.appleFoundationModels,
      supportsToolCalling: true,
      supportsStructuredOutput: true,
    ),
  );

  @override
  Future<ModelFeatureStatus> getModelStatus() =>
      Future.value(ModelFeatureStatus.available);

  @override
  Stream<ModelDownloadStatus> downloadModel() => Stream.value(
    const ModelDownloadStatus(status: ModelFeatureStatus.available),
  );

  @override
  Future<bool> openAICorePlayStore() => Future.value(false);

  @override
  Future<String> createSession({
    String? systemInstruction,
    List<OnDeviceAiTool>? tools,
    GenerationConfig? config,
  }) => Future.value('test_session');

  @override
  Future<void> sessionAddQuery(String sessionId, String text) => Future.value();

  @override
  Future<void> sessionAddImage(
    String sessionId,
    imageBytes, {
    String mimeType = 'image/jpeg',
  }) => Future.value();

  @override
  Future<AiResponse> sessionGetResponse(
    String sessionId, {
    GenerationConfig? config,
  }) => Future.value(AiResponse(text: 'Mock Session Response'));

  @override
  Stream<String> sessionGetResponseStream(
    String sessionId, {
    GenerationConfig? config,
  }) => Stream.fromIterable(['chunk']);

  @override
  Future<int> sessionCountTokens(String sessionId, {String? text}) =>
      Future.value(5);

  @override
  Future<void> sessionStopGeneration(String sessionId) => Future.value();

  @override
  Future<void> sessionClose(String sessionId) => Future.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Verify OnDeviceAiExampleApp loads showcase tabs', (
    WidgetTester tester,
  ) async {
    FlutterOnDeviceAiPlatform.instance = MockPlatform();

    await tester.pumpWidget(const OnDeviceAiExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('On-Device Local AI'), findsOneWidget);
    expect(find.text('Streaming Chat'), findsOneWidget);
    expect(find.text('JSON Schema'), findsOneWidget);
    expect(find.text('Tool Calling'), findsOneWidget);
    expect(find.text('GenUI'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
  });
}
