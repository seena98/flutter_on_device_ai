@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai_web.dart';
import 'package:flutter_test/flutter_test.dart';

@JS('eval')
external JSAny? _eval(String code);

/// Installs a stand-in for Chrome's `LanguageModel` so the interop code runs
/// against a real JS engine (the model itself is faked).
void installFakeLanguageModel(String availability) {
  _eval('''
    window.__created = 0;
    window.LanguageModel = {
      availability: async () => "$availability",
      params: async () => ({defaultTemperature: 1, defaultTopK: 3}),
      create: async (opts) => {
        window.__created++;
        window.__lastCreate = opts;
        if (opts.monitor) {
          opts.monitor({addEventListener: (n, cb) => { cb({loaded: 0.5}); cb({loaded: 1}); }});
        }
        return {
          prompt: async (input, o) => "echo:" + input,
          promptStreaming: (input, o) => new ReadableStream({
            start(c) {
              for (const x of ["he", "llo"]) c.enqueue(x);
              c.close();
            }
          }),
          measureInputUsage: async (t) => t.length * 2,
          destroy() {},
        };
      },
    };
  ''');
}

void main() {
  test('reports browserUnsupported without the Prompt API', () async {
    _eval('delete window.LanguageModel');
    final web = FlutterOnDeviceAiWeb();
    final a = await web.getAvailability();
    expect(a.reason, AvailabilityReason.browserUnsupported);
    expect(
      (await web.getPlatformInfo()).backend,
      OnDeviceAiBackend.unsupported,
    );
  });

  test('maps Prompt API availability states', () async {
    final web = FlutterOnDeviceAiWeb();
    for (final (raw, status) in [
      ('available', ModelFeatureStatus.available),
      ('downloadable', ModelFeatureStatus.downloadable),
      ('downloading', ModelFeatureStatus.downloading),
      ('unavailable', ModelFeatureStatus.unavailable),
    ]) {
      installFakeLanguageModel(raw);
      expect((await web.getAvailability()).status, status, reason: raw);
    }
  });

  test('prompt, stream and token count go through the JS API', () async {
    installFakeLanguageModel('available');
    final web = FlutterOnDeviceAiWeb();
    final id = await web.createSession(systemInstruction: 'sys');
    await web.sessionAddQuery(id, 'hi');
    final res = await web.sessionGetResponse(id);
    expect(res.text, 'echo:hi');

    await web.sessionAddQuery(id, 'again');
    expect((await web.sessionGetResponseStream(id).toList()).join(), 'hello');
    expect(await web.sessionCountTokens(id, text: 'abcd'), 8);
    await web.sessionClose(id);
  });

  test('system instruction and sampling reach create()', () async {
    installFakeLanguageModel('available');
    final web = FlutterOnDeviceAiWeb();
    final id = await web.createSession(
      systemInstruction: 'be brief',
      config: const GenerationConfig(temperature: 0.3),
    );
    await web.sessionAddQuery(id, 'x');
    await web.sessionGetResponse(id);
    final seen =
        (_eval('JSON.stringify(window.__lastCreate)') as JSString).toDart;
    expect(seen, contains('"role":"system"'));
    expect(seen, contains('be brief'));
    expect(seen, contains('"temperature":0.3'));
    expect(seen, contains('"topK":3'));
  });

  void setUserActivation(bool active) => _eval(
    'Object.defineProperty(navigator, "userActivation", '
    '{value: {isActive: $active}, configurable: true})',
  );

  test(
    'download without a user gesture is refused with a typed error',
    () async {
      installFakeLanguageModel('downloadable');
      setUserActivation(false);
      await expectLater(
        FlutterOnDeviceAiWeb().downloadModel().toList(),
        throwsA(isA<OnDeviceAiUserActivationRequiredException>()),
      );
    },
  );

  test('download reports progress from the monitor', () async {
    installFakeLanguageModel('downloadable');
    setUserActivation(true);
    final events = await FlutterOnDeviceAiWeb().downloadModel().toList();
    expect(events.map((e) => e.progress), containsAll([0.5, 1.0]));
    expect(events.last.status, ModelFeatureStatus.available);
  });

  test('empty turns are rejected', () async {
    installFakeLanguageModel('available');
    final web = FlutterOnDeviceAiWeb();
    final id = await web.createSession();
    await expectLater(
      web.sessionGetResponse(id),
      throwsA(isA<OnDeviceAiException>()),
    );
  });
}
