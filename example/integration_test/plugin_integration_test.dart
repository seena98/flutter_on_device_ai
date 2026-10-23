// Runs against the REAL on-device model of the machine it executes on:
//
//   flutter test integration_test -d <device>
//
// Skips (with a printed reason) when the device has no usable model, so it is
// safe to run anywhere. On a capable device it proves the native path works.
import 'dart:convert';

import 'package:flutter_device_ai/flutter_device_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final ai = FlutterDeviceAi.withFallback();

  Future<bool> modelReady() async {
    final a = await ai.availability();
    // ignore: avoid_print
    print('availability: $a');
    return a.isReady;
  }

  testWidgets('availability and capabilities answer', (tester) async {
    final a = await ai.availability();
    expect(a.message, isNotEmpty);
    final caps = await ai.capabilities();
    // ignore: avoid_print
    print('capabilities: $caps');
    expect(caps.backend, isNotNull);
  });

  testWidgets('real model answers and streams', (tester) async {
    if (!await modelReady()) {
      markTestSkipped('No usable on-device model on this device.');
      return;
    }
    final res = await ai.generateText(
      prompt: 'Reply with exactly one word: pong',
      config: const GenerationConfig(maxTokens: 20, temperature: 0),
    );
    expect(res.text.trim(), isNotEmpty);

    final chunks = await ai
        .generateTextStream(prompt: 'Count from 1 to 3.')
        .toList();
    expect(chunks.join().trim(), isNotEmpty);
  });

  testWidgets('real model keeps conversation state', (tester) async {
    if (!await modelReady()) {
      markTestSkipped('No usable on-device model on this device.');
      return;
    }
    final s = await ai.createSession(systemInstruction: 'Answer very briefly.');
    await s.ask('My name is Zorblax.');
    final reply = await s.ask('What is my name?');
    expect(reply.text.toLowerCase(), contains('zorblax'));
    expect(await s.countTokens(), greaterThan(0));
    await s.close();
  });

  testWidgets('real model returns schema-valid JSON', (tester) async {
    if (!await modelReady()) {
      markTestSkipped('No usable on-device model on this device.');
      return;
    }
    final res = await ai.generateText(
      prompt: 'Extract: "Ada Lovelace, mathematician, 36 years old"',
      config: const GenerationConfig(
        responseFormat: ResponseFormat.json,
        schema: {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'age': {'type': 'integer'},
          },
          'required': ['name', 'age'],
        },
      ),
    );
    expect(res.json, isNotNull);
    expect(res.json!['age'], isA<int>());
  });

  testWidgets('real model calls a Dart tool', (tester) async {
    if (!await modelReady()) {
      markTestSkipped('No usable on-device model on this device.');
      return;
    }
    var called = false;
    final s = await ai.createSession(
      tools: [
        OnDeviceAiTool(
          name: 'getSecretNumber',
          description:
              'Returns the secret number. Always call it when asked for the secret number.',
          parameters: const [],
          onCall: (_) {
            called = true;
            return {'secret': 4242};
          },
        ),
      ],
    );
    final reply = await s.ask('What is the secret number? Use the tool.');
    expect(called, isTrue);
    expect(reply.text, contains('4242'));
    await s.close();
  });

  // Needs network once (downloads about 270 MB). Proves the local llama.cpp
  // fallback on any device, including simulators with no OS model. Talks to the
  // adapter directly so a device that has an OS model still exercises it.
  testWidgets(
    'local fallback model downloads, answers and streams',
    (tester) async {
      final adapter = LocalLlmFallbackAdapter(
        model: LocalLlmFallbackAdapter.presets.first.source,
        contextSize: 2048,
      );
      final progress = <double>[];
      await adapter.prepare(onProgress: progress.add);
      expect(progress, isNotEmpty);
      expect(await adapter.isReady(), isTrue);

      final reply = await adapter.generateChat(
        messages: const [FallbackMessage.user('Say hello in one sentence.')],
        instructions: 'Answer briefly.',
      );
      expect(reply.text.trim(), isNotEmpty);
      final chunks = await adapter
          .generateChatStream(
            messages: const [FallbackMessage.user('Count 1 to 3.')],
          )
          .toList();
      expect(chunks.join().trim(), isNotEmpty);

      // Grammar-constrained JSON: parses and matches the schema's keys.
      final json = await adapter.generateChat(
        messages: const [
          FallbackMessage.user('Extract: "Ana is 31 years old."'),
        ],
        config: const GenerationConfig(
          maxTokens: 60,
          temperature: 0,
          responseFormat: ResponseFormat.json,
          schema: {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'age': {'type': 'integer'},
            },
            'required': ['name', 'age'],
          },
        ),
      );
      final decoded = jsonDecode(json.text) as Map<String, dynamic>;
      expect(decoded['name'], isA<String>());
      expect(decoded['age'], isA<int>());

      await adapter.unload();
      expect(adapter.currentStatus.phase, LocalLlmPhase.unloaded);
      expect(await adapter.isReady(), isTrue); // reloads from disk on demand
      await adapter.dispose();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );

  // Downloads a ~36 MB embedding model and searches real documents with it.
  testWidgets(
    'local embedder powers semantic search',
    (tester) async {
      final embedder = LocalEmbedder();
      await embedder.prepare();
      final index = RagIndex(embedder: embedder);
      await index.addDocument('pets', 'Cats purr when they are content.');
      await index.addDocument(
        'cars',
        'Replace the engine oil every 10,000 km.',
      );
      final hits = await index.search(
        'why does my kitten make a humming sound',
      );
      expect(hits, isNotEmpty);
      expect(hits.first.documentId, 'pets');
      await embedder.dispose();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
