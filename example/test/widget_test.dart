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
