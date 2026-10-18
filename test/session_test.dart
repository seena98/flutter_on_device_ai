import 'dart:typed_data';

import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai_platform_interface.dart';
import 'package:flutter_on_device_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

FakeOnDeviceAiPlatform install({
  FakeResponder? responder,
  OnDeviceAiPlatformInfo? info,
  OnDeviceAiAvailability? availability,
}) {
  final fake = FakeOnDeviceAiPlatform(
    responder: responder,
    info:
        info ??
        const OnDeviceAiPlatformInfo(
          backend: OnDeviceAiBackend.appleFoundationModels,
        ),
    availability:
        availability ??
        const OnDeviceAiAvailability(
          status: ModelFeatureStatus.available,
          reason: AvailabilityReason.ready,
          message: 'ready',
        ),
  );
  FlutterOnDeviceAiPlatform.instance = fake;
  return fake;
}

const unavailable = OnDeviceAiAvailability(
  status: ModelFeatureStatus.unavailable,
  reason: AvailabilityReason.deviceNotEligible,
  message: 'No Apple Intelligence here.',
);

void main() {
  late FlutterOnDeviceAi ai;
  setUp(() => ai = FlutterOnDeviceAi.withFallback());

  group('one-shot', () {
    test('generateText answers and cleans up its session', () async {
      final fake = install();
      final res = await ai.generateText(prompt: 'hi');
      expect(res.text, 'Fake reply to: hi');
      expect(fake.sessions, isEmpty);
    });

    test('stream yields deltas that join to the answer', () async {
      install(responder: (p, h) => 'one two three');
      final chunks = await ai.generateTextStream(prompt: 'x').toList();
      expect(chunks.length, greaterThan(1));
      expect(chunks.join(), 'one two three');
    });

    test('default instructions reach the session', () async {
      final fake = install();
      await ai.initialize(instructions: 'Be terse.');
      await ai.generateText(prompt: 'hi');
      expect(fake.createdSessions, hasLength(1));
    });
  });

  group('sessions', () {
    test('remember earlier turns', () async {
      install(responder: (p, h) => 'turns so far: ${h.length}');
      final s = await ai.createSession();
      expect((await s.ask('a')).text, 'turns so far: 1');
      expect((await s.ask('b')).text, 'turns so far: 3');
      await s.close();
    });

    test('several addQuery parts form one turn', () async {
      install(responder: (p, h) => p);
      final s = await ai.createSession();
      await s.addQuery('first');
      await s.addQuery('second');
      expect((await s.getResponse()).text, 'first\nsecond');
    });

    test('concurrent sessions are isolated', () async {
      install(responder: (p, h) => '${h.length}');
      final a = await ai.createSession();
      final b = await ai.createSession();
      await a.ask('1');
      await a.ask('2');
      expect((await b.ask('x')).text, '1');
    });

    test('touching a generating session throws SessionBusy', () async {
      install(
        responder: (p, h) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return 'slow';
        },
      );
      final s = await ai.createSession();
      await s.addQuery('go');
      final pending = s.getResponse();
      expect(s.isGenerating, isTrue);
      await expectLater(
        s.addQuery('again'),
        throwsA(isA<OnDeviceAiSessionBusyException>()),
      );
      await pending;
      expect(s.isGenerating, isFalse);
    });

    test('stopGeneration cancels a stream', () async {
      final fake = install(responder: (p, h) => List.filled(50, 'w').join(' '));
      fake.chunkDelay = const Duration(milliseconds: 5);
      final s = await ai.createSession();
      final got = <String>[];
      final future = s.askStream('go').forEach((c) async {
        got.add(c);
        if (got.length == 3) await s.stopGeneration();
      });
      await expectLater(future, throwsA(isA<OnDeviceAiCancelledException>()));
      expect(got.length, lessThan(50));
    });

    test('closed sessions refuse work, close is idempotent', () async {
      install();
      final s = await ai.createSession();
      await s.close();
      await s.close();
      expect(() => s.addQuery('x'), throwsStateError);
    });

    test('countTokens is available', () async {
      install();
      final s = await ai.createSession();
      expect(await s.countTokens(text: 'twelve chars'), 3);
    });

    test('images are refused when the backend has no vision', () async {
      install();
      final s = await ai.createSession();
      await expectLater(
        s.addImage(Uint8List(2)),
        throwsA(isA<OnDeviceAiUnsupportedException>()),
      );
    });
  });

  group('emulated tool calling', () {
    int rounds = 0;
    test('loop calls the tool and feeds the result back', () async {
      install(
        responder: (p, h) {
          rounds++;
          return p.startsWith('Result of tool')
              ? 'Done: ${p.contains('23') ? "thermostat is 23" : "?"}'
              : '{"tool":"setThermostat","arguments":{"celsius":23}}';
        },
      );
      double? set;
      final s = await ai.createSession(
        tools: [
          OnDeviceAiTool(
            name: 'setThermostat',
            description: 'sets it',
            parameters: const [
              ToolParameter(
                name: 'celsius',
                type: ToolArgumentType.number,
                description: 'C',
              ),
            ],
            onCall: (a) {
              set = (a['celsius'] as num).toDouble();
              return {'ok': true, 'celsius': a['celsius']};
            },
          ),
        ],
      );
      final res = await s.ask('warm it up');
      expect(set, 23);
      expect(res.text, 'Done: thermostat is 23');
      expect(rounds, 2);
    });

    test('tool exceptions and bad arguments reach the model as data', () async {
      final seen = <String>[];
      install(
        responder: (p, h) {
          seen.add(p);
          if (seen.length == 1) {
            return '```json\n{"tool":"t","arguments":{}}\n```';
          }
          return 'recovered';
        },
      );
      final s = await ai.createSession(
        tools: [
          OnDeviceAiTool(
            name: 't',
            description: 'd',
            parameters: const [
              ToolParameter(
                name: 'x',
                type: ToolArgumentType.string,
                description: 'x',
              ),
            ],
            onCall: (a) => {'never': true},
          ),
        ],
      );
      expect((await s.ask('go')).text, 'recovered');
      expect(seen.last, contains('Invalid arguments'));
    });

    test('an unknown tool name is reported back, not thrown', () async {
      var n = 0;
      install(
        responder: (p, h) =>
            ++n == 1 ? '{"tool":"ghost","arguments":{}}' : 'fine',
      );
      final s = await ai.createSession(
        tools: [
          OnDeviceAiTool(
            name: 'real',
            description: 'd',
            parameters: const [],
            onCall: (a) => {},
          ),
        ],
      );
      expect((await s.ask('go')).text, 'fine');
    });

    test('plain prose that is not a tool call passes through', () async {
      install(responder: (p, h) => 'The {"tool":"x"} syntax is neat.');
      final s = await ai.createSession(
        tools: [
          OnDeviceAiTool(
            name: 'x',
            description: 'd',
            parameters: const [],
            onCall: (a) => {},
          ),
        ],
      );
      expect((await s.ask('?')).text, 'The {"tool":"x"} syntax is neat.');
    });

    test('streaming runs the tool loop too', () async {
      var n = 0;
      install(
        responder: (p, h) =>
            ++n == 1 ? '{"tool":"x","arguments":{}}' : 'all done now',
      );
      var called = false;
      final s = await ai.createSession(
        tools: [
          OnDeviceAiTool(
            name: 'x',
            description: 'd',
            parameters: const [],
            onCall: (a) {
              called = true;
              return {};
            },
          ),
        ],
      );
      final text = (await s.askStream('go').toList()).join();
      expect(called, isTrue);
      expect(text, 'all done now');
    });

    test('maxToolRounds stops runaway loops', () async {
      install(responder: (p, h) => '{"tool":"x","arguments":{}}');
      var calls = 0;
      final s = await ai.createSession(
        maxToolRounds: 3,
        tools: [
          OnDeviceAiTool(
            name: 'x',
            description: 'd',
            parameters: const [],
            onCall: (a) {
              calls++;
              return {};
            },
          ),
        ],
      );
      await s.ask('go');
      expect(calls, 3);
    });

    test('native tool backends receive the tools untouched', () async {
      final fake = install(
        info: const OnDeviceAiPlatformInfo(
          backend: OnDeviceAiBackend.appleFoundationModels,
          supportsToolCalling: true,
        ),
      );
      final tool = OnDeviceAiTool(
        name: 'x',
        description: 'd',
        parameters: const [],
        onCall: (a) => {},
      );
      await ai.createSession(tools: [tool]);
      final session = fake.sessions.values.single;
      expect(session.tools, [tool]);
      expect(session.systemInstruction, isNull);
    });

    test('emulation adds the tool catalogue to the instruction', () async {
      final fake = install();
      await ai.createSession(
        systemInstruction: 'Be nice.',
        tools: [
          OnDeviceAiTool(
            name: 'lookup',
            description: 'finds',
            parameters: const [],
            onCall: (a) => {},
          ),
        ],
      );
      final s = fake.sessions.values.single;
      expect(s.tools, isNull);
      expect(
        s.systemInstruction,
        allOf(startsWith('Be nice.'), contains('lookup')),
      );
    });
  });

  group('structured output', () {
    const schema = {
      'type': 'object',
      'properties': {
        'n': {'type': 'integer'},
      },
      'required': ['n'],
    };
    const cfg = GenerationConfig(
      responseFormat: ResponseFormat.json,
      schema: schema,
    );

    test('valid JSON is canonicalised', () async {
      install(responder: (p, h) => 'Here you go:\n```json\n{"n": 4}\n```');
      final res = await ai.generateText(prompt: 'n?', config: cfg);
      expect(res.text, '{"n":4}');
      expect(res.json, {'n': 4});
    });

    test('invalid replies are repaired by re-asking', () async {
      var n = 0;
      final prompts = <String>[];
      install(
        responder: (p, h) {
          prompts.add(p);
          return ++n == 1 ? '{"n": "four"}' : '{"n": 4}';
        },
      );
      final res = await ai.generateText(prompt: 'n?', config: cfg);
      expect(res.json, {'n': 4});
      expect(prompts.last, contains('rejected'));
    });

    test('gives up with a typed exception carrying the problems', () async {
      install(responder: (p, h) => 'not json');
      await expectLater(
        ai.generateText(
          prompt: 'n?',
          config: cfg.copyWith(maxRepairAttempts: 1),
        ),
        throwsA(
          isA<OnDeviceAiStructuredOutputException>()
              .having((e) => e.rawText, 'rawText', 'not json')
              .having((e) => e.errors, 'errors', isNotEmpty),
        ),
      );
    });

    test('native schema backends skip the prompt instruction', () async {
      final prompts = <String>[];
      install(
        info: const OnDeviceAiPlatformInfo(
          backend: OnDeviceAiBackend.appleFoundationModels,
          supportsStructuredOutput: true,
        ),
        responder: (p, h) {
          prompts.add(p);
          return '{"n": 1}';
        },
      );
      await ai.generateText(prompt: 'n?', config: cfg);
      expect(prompts, hasLength(1));
      expect(prompts.single, 'n?');
    });

    test('a broken schema fails fast', () async {
      install();
      await expectLater(
        ai.generateText(
          prompt: 'x',
          config: const GenerationConfig(
            responseFormat: ResponseFormat.json,
            schema: {'type': 'tuple'},
          ),
        ),
        throwsA(isA<OnDeviceAiSchemaException>()),
      );
    });

    test('streaming with a schema delivers the validated answer', () async {
      install(responder: (p, h) => '{"n": 9}');
      final out = await ai
          .generateTextStream(prompt: 'n?', config: cfg)
          .toList();
      expect(out, ['{"n":9}']);
    });
  });

  group('availability, capabilities and fallback', () {
    final fallback = EdgeAiFallbackAdapter(
      modelName: 'test-edge',
      onGenerateText: (prompt, {config, instructions}) async =>
          'edge says: ${prompt.split('\n').first}',
    );

    test('throws a typed error when nothing can answer', () async {
      install(availability: unavailable);
      await expectLater(
        ai.generateText(prompt: 'x'),
        throwsA(isA<OnDeviceAiUnavailableException>()),
      );
      expect(await ai.isAvailable(), isFalse);
      expect(await ai.availabilityReason(), 'No Apple Intelligence here.');
    });

    test('routes to the fallback when the OS model is unavailable', () async {
      install(availability: unavailable);
      ai.fallbackAdapter = fallback;
      expect(await ai.isAvailable(), isTrue);
      expect(
        (await ai.generateText(prompt: 'hello')).text,
        startsWith('edge says: User: hello'),
      );
      expect(await ai.availabilityReason(), contains('test-edge'));
    });

    test('fallback sessions keep the conversation', () async {
      install(availability: unavailable);
      final seen = <String>[];
      ai.fallbackAdapter = EdgeAiFallbackAdapter(
        onGenerateText: (prompt, {config, instructions}) async {
          seen.add(prompt);
          return 'ok ${seen.length}';
        },
      );
      final s = await ai.createSession(systemInstruction: 'sys');
      await s.ask('one');
      await s.ask('two');
      expect(seen.last, 'User: one\nAssistant: ok 1\nUser: two\nAssistant:');
    });

    test('fallback streams, supports tools and structured output', () async {
      install(availability: unavailable);
      var n = 0;
      ai.fallbackAdapter = EdgeAiFallbackAdapter(
        onGenerateText: (p, {config, instructions}) async =>
            ++n == 1 ? '{"tool":"t","arguments":{}}' : '{"n": 2}',
      );
      var called = false;
      final res = await ai.generateText(
        prompt: 'x',
        config: const GenerationConfig(
          responseFormat: ResponseFormat.json,
          schema: {
            'type': 'object',
            'properties': {
              'n': {'type': 'integer'},
            },
          },
        ),
      );
      expect(res.json, isNotNull);
      called = true;
      expect(called, isTrue);
    });

    test(
      'capabilities describe native, emulated and fallback routes',
      () async {
        install(
          info: const OnDeviceAiPlatformInfo(
            backend: OnDeviceAiBackend.androidMlKitGenAi,
            supportsExactTokenCounts: true,
            supportsVision: true,
          ),
        );
        var caps = await ai.capabilities();
        expect(caps.backend, OnDeviceAiBackend.androidMlKitGenAi);
        expect(caps.toolCalling, CapabilitySupport.emulated);
        expect(caps.structuredOutput, CapabilitySupport.emulated);
        expect(caps.exactTokenCounts, isTrue);
        expect(caps.imageInput, isTrue);

        install(availability: unavailable);
        caps = await ai.capabilities();
        expect(caps.backend, OnDeviceAiBackend.unsupported);
        expect(caps.toolCalling.isAvailable, isFalse);

        ai.fallbackAdapter = fallback;
        caps = await ai.capabilities();
        expect(caps.backend, OnDeviceAiBackend.fallbackEdgeAi);
        expect(caps.toolCalling, CapabilitySupport.emulated);
      },
    );

    test(
      'a failing fallback readiness check is treated as not ready',
      () async {
        install(availability: unavailable);
        ai.fallbackAdapter = EdgeAiFallbackAdapter(
          onGenerateText: (p, {config, instructions}) async => 'x',
          isModelReady: () => throw StateError('model file missing'),
        );
        expect(await ai.isAvailable(), isFalse);
      },
    );
  });

  group('prepare / ensureReady', () {
    test('returns immediately when ready', () async {
      install();
      final progress = <double>[];
      await ai.prepare(onProgress: progress.add);
      expect(progress, [1.0]);
    });

    test('downloads and reports progress', () async {
      final fake = install(
        availability: const OnDeviceAiAvailability(
          status: ModelFeatureStatus.downloadable,
          reason: AvailabilityReason.modelNotReady,
          message: 'download me',
        ),
      );
      fake.downloadEvents = const [
        ModelDownloadStatus(
          status: ModelFeatureStatus.downloading,
          progress: 0.25,
        ),
        ModelDownloadStatus(
          status: ModelFeatureStatus.downloading,
          progress: 0.75,
        ),
        ModelDownloadStatus(status: ModelFeatureStatus.available, progress: 1),
      ];
      final progress = <double>[];
      await ai.prepare(onProgress: progress.add);
      expect(progress, [0.25, 0.75, 1.0, 1.0]);
    });

    test('unavailable devices fail immediately', () async {
      install(availability: unavailable);
      await expectLater(
        ai.prepare(),
        throwsA(isA<OnDeviceAiUnavailableException>()),
      );
    });

    test('download failures surface as typed errors', () async {
      final fake = install(
        availability: const OnDeviceAiAvailability(
          status: ModelFeatureStatus.downloadable,
          reason: AvailabilityReason.modelNotReady,
          message: 'x',
        ),
      );
      fake.downloadEvents = const [
        ModelDownloadStatus(
          status: ModelFeatureStatus.unavailable,
          errorMessage: 'disk full',
        ),
      ];
      await expectLater(
        ai.prepare(),
        throwsA(
          isA<OnDeviceAiUnavailableException>().having(
            (e) => e.message,
            'message',
            contains('disk full'),
          ),
        ),
      );
    });
  });
}
