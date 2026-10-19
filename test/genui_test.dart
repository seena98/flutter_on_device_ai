import 'package:flutter_device_ai/flutter_device_ai.dart';
import 'package:flutter_device_ai/flutter_device_ai_platform_interface.dart';
import 'package:flutter_device_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnDeviceUiGenerator.parseModelOutput', () {
    test('parses fenced output and keeps valid blocks only', () {
      final spec = OnDeviceUiGenerator.parseModelOutput('''
Here is the screen:
```json
{"title":"Run","icon":"run","tone":"motivational","blurb":"Go","blocks":[
 {"type":"stat","label":"Pace","value":"5:10"},
 {"type":"mystery","x":1},
 {"type":"progress","label":"km","current":"12","target":0},
 {"type":"checklist","items":["Stretch",{"title":"Hydrate","completed":true}]},
 {"type":"note","content":""}
]}
```''')!;
      expect(spec.title, 'Run');
      expect(spec.blocks.map((b) => b['type']), [
        'stat',
        'progress',
        'checklist',
      ]);
      expect(spec.blocks[1]['current'], 12);
      expect(spec.blocks[1]['target'], 100);
      expect(spec.blocks[2]['items'], [
        {'title': 'Stretch', 'completed': false},
        {'title': 'Hydrate', 'completed': true},
      ]);
    });

    test('repairs truncated output', () {
      final spec = OnDeviceUiGenerator.parseModelOutput(
        '{"title":"T","blocks":[{"type":"note","content":"hello wor',
      )!;
      expect(spec.blocks.single['content'], 'hello wor');
    });

    test('returns null when nothing renderable remains', () {
      expect(
        OnDeviceUiGenerator.parseModelOutput('{"title":"T","blocks":[]}'),
        isNull,
      );
      expect(OnDeviceUiGenerator.parseModelOutput('sorry, I cannot'), isNull);
    });

    test('component maps carry ids and properties', () {
      final spec = OnDeviceUiGenerator.parseModelOutput(
        '{"title":"T","blocks":[{"type":"note","content":"x"}]}',
      )!;
      expect(spec.toComponentMaps(), [
        {
          'id': 'block_0',
          'type': 'note',
          'properties': {'content': 'x'},
        },
      ]);
    });

    test('table, steps, list and callout are supported', () {
      final spec = OnDeviceUiGenerator.parseModelOutput('''
{"title":"T","blocks":[
 {"type":"table","columns":["a","b"],"rows":[["1","2"]]},
 {"type":"steps","items":[{"title":"One","detail":"x"}]},
 {"type":"list","items":["a","b"]},
 {"type":"callout","kind":"weird","content":"careful"}]}''')!;
      expect(spec.blocks, hasLength(4));
      expect(spec.blocks.last['kind'], 'info');
    });
  });

  group('generateModule', () {
    test('table rows are padded or trimmed to the header width', () {
      final spec = OnDeviceUiGenerator.parseModelOutput(
        '{"title":"t","blocks":[{"type":"table","columns":["a","b"],'
        '"rows":[["1"],["1","2","3"],"junk"]}]}',
      )!;
      expect(spec.blocks.single['rows'], [
        ['1', ''],
        ['1', '2'],
      ]);
    });

    test('talks to the model and reports failures', () async {
      FlutterDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
        responder: (p, h) =>
            '{"title":"Plan","blocks":[{"type":"note","content":"hi"}]}',
      );
      final generator = OnDeviceUiGenerator(FlutterDeviceAi.withFallback());
      final streamed = <String>[];
      final spec = await generator.generateModule(
        'anything',
        language: 'German',
        onText: streamed.add,
      );
      expect(spec!.title, 'Plan');
      expect(streamed, isNotEmpty);

      FlutterDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
        responder: (p, h) => 'no json',
      );
      expect(await generator.generateModule('anything'), isNull);
      expect(generator.lastError, isNotNull);
    });

    test('returns null with a reason when AI is unavailable', () async {
      FlutterDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
        availability: const OnDeviceAiAvailability(
          status: ModelFeatureStatus.unavailable,
          reason: AvailabilityReason.featureDisabled,
          message: 'Turn it on',
        ),
      );
      final generator = OnDeviceUiGenerator(FlutterDeviceAi.withFallback());
      expect(await generator.generateModule('x'), isNull);
      expect(generator.lastError, 'Turn it on');
    });
  });
}
