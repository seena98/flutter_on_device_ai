// Renders the demo GIF frames. Skipped unless DEMO_FRAMES_DIR is set:
//
//   DEMO_FRAMES_DIR=/tmp/frames flutter test test/demo_frames_test.dart
//
// The app and the library code are the real ones; only the model's replies are
// scripted through FakeOnDeviceAiPlatform. The README says so next to the GIF.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai_platform_interface.dart';
import 'package:flutter_on_device_ai/testing.dart';
import 'package:flutter_on_device_ai_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

const _walk =
    'Here is a simple 20-minute lunch walk: 5 minutes at an easy pace to '
    'warm up, 10 minutes at a brisk pace, then 5 minutes to cool down. '
    'Bring water and finish with a short stretch.';

const _module =
    '{"title":"10K in one week","icon":"run","tone":"motivational",'
    '"blurb":"Seven easy days, one confident finish.","blocks":['
    '{"type":"stat","label":"Target pace","value":"5:45 /km","subtext":"Comfortable, conversational"},'
    '{"type":"progress","label":"Weekly distance","current":18,"target":30,"unit":"km"},'
    '{"type":"checklist","items":[{"title":"Easy 5 km run","completed":true},'
    '{"title":"Strength and mobility","completed":true},{"title":"Long run, 8 km","completed":false}]},'
    '{"type":"callout","kind":"info","content":"Rest well the night before race day."}]}';

String _reply(String prompt) {
  if (prompt.startsWith('Result of tool')) {
    return 'Done. The thermostat is now set to 23 °C.';
  }
  if (prompt.contains('chilly')) {
    return '{"tool":"setThermostat","arguments":{"celsius":23}}';
  }
  if (prompt.contains('Extract the person')) {
    return '{"name":"Elena Rostova","role":"principal engineer",'
        '"yearsExperience":9,"specialties":["compilers","distributed systems"]}';
  }
  if (prompt.startsWith('Goal:')) return _module;
  return _walk;
}

void main() {
  final dir = Platform.environment['DEMO_FRAMES_DIR'];

  testWidgets('record demo frames', (tester) async {
    for (final w in ['Regular', 'Medium', 'Bold']) {
      final data = File(
        '${Platform.environment['FLUTTER_ROOT'] ?? '/Users/seena/development/flutter'}'
        '/bin/cache/artifacts/material_fonts/Roboto-$w.ttf',
      ).readAsBytesSync();
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(data)));
      await loader.load();
    }

    final icons = File(
      '${Platform.environment['FLUTTER_ROOT'] ?? '/Users/seena/development/flutter'}'
      '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytesSync();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();

    tester.view
      ..physicalSize = const Size(780, 1560)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    FlutterOnDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
      availability: const OnDeviceAiAvailability(
        status: ModelFeatureStatus.available,
        reason: AvailabilityReason.ready,
        message: 'Scripted demo: model replies are pre-written.',
      ),
      responder: (prompt, history) => _reply(prompt),
      chunkDelay: const Duration(milliseconds: 55),
      info: const OnDeviceAiPlatformInfo(
        backend: OnDeviceAiBackend.appleFoundationModels,
        supportsStructuredOutput: true,
      ),
    );

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const ExampleApp()),
    );
    await tester.pumpAndSettle();

    final manifest = <String>[];
    var n = 0;
    Future<void> snap(int holdMs) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final name = 'f${(n++).toString().padLeft(4, '0')}.png';
        File('$dir/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
        manifest.add('$name $holdMs');
      });
    }

    Future<void> type(Finder field, String text, {int step = 3}) async {
      for (var i = step; i < text.length + step; i += step) {
        final end = i > text.length ? text.length : i;
        await tester.enterText(field, text.substring(0, end));
        await tester.pump(const Duration(milliseconds: 40));
        await snap(70);
      }
    }

    Future<void> run(
      Finder trigger, {
      int maxFrames = 60,
      int every = 2,
      bool Function()? done,
    }) async {
      await tester.tap(trigger);
      await tester.pump();
      for (var i = 0; i < maxFrames; i++) {
        await tester.pump(const Duration(milliseconds: 55));
        if (i % every == 0) await snap(110);
        if (done != null && done()) break;
      }
      await tester.pumpAndSettle();
    }

    // Scene 0: status
    await snap(1400);

    // Scene 1: streaming chat
    await type(
      find.byType(TextField).first,
      'Plan a 20 minute lunch walk',
      step: 4,
    );
    await snap(400);
    await run(
      find.byIcon(Icons.send),
      maxFrames: 80,
      every: 2,
      done: () =>
          find.byIcon(Icons.send).evaluate().isNotEmpty &&
          find.textContaining('stretch').evaluate().isNotEmpty,
    );
    await snap(1800);

    // Scene 2: extract
    await tester.tap(find.text('Extract'));
    await tester.pumpAndSettle();
    await snap(900);
    await run(find.text('Extract as JSON'), maxFrames: 6, every: 3);
    await snap(2200);

    // Scene 3: tools
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    await snap(900);
    await run(find.text('Ask'), maxFrames: 8, every: 2);
    await snap(2400);

    // Scene 4: generated screen
    await tester.tap(find.text('Screen'));
    await tester.pumpAndSettle();
    await snap(900);
    await run(find.text('Generate screen'), maxFrames: 6, every: 3);
    await snap(2600);

    if (dir != null)
      File('$dir/manifest.txt').writeAsStringSync(manifest.join('\n'));
  }, skip: dir == null);
}
