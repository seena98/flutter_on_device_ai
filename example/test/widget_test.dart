import 'package:flutter/material.dart';
import 'package:flutter_device_ai/flutter_device_ai.dart';
import 'package:flutter_device_ai/flutter_device_ai_platform_interface.dart';
import 'package:flutter_device_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_device_ai_example/main.dart';

void main() {
  testWidgets('chats with the (fake) on-device model', (tester) async {
    FlutterDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
      responder: (prompt, history) => 'Echo: $prompt',
    );

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('ready'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.textContaining('Echo: hello'), findsOneWidget);
  });

  testWidgets('answers from the user\'s notes in the Docs tab', (tester) async {
    FlutterDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
      responder: (prompt, history) => 'Answer: hold the button.',
    );
    tester.view
      ..physicalSize = const Size(780, 1560)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ExampleApp(embedder: FakeOnDeviceAiEmbedder()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Docs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search and answer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('note 1'), findsOneWidget);
    expect(
      find.textContaining('Answer: hold the button.', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('explains why nothing is usable', (tester) async {
    FlutterDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
      availability: const OnDeviceAiAvailability(
        status: ModelFeatureStatus.unavailable,
        reason: AvailabilityReason.deviceNotEligible,
        message: 'Not eligible',
      ),
    );
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('No model is usable'), findsOneWidget);
  });
}
