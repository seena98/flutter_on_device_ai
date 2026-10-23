import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_device_ai/flutter_device_ai.dart';
import 'package:flutter_device_ai/flutter_device_ai_platform_interface.dart';
import 'package:flutter_device_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

class _VisionAdapter extends CallbackFallbackAdapter {
  _VisionAdapter(this.seen)
    : super(onGenerateText: (prompt, {config, instructions}) async => 'x');

  final List<FallbackMessage> seen;

  @override
  bool get supportsImages => true;

  @override
  Future<AiResponse> generateChat({
    required List<FallbackMessage> messages,
    GenerationConfig? config,
    String? instructions,
  }) async {
    seen.addAll(messages);
    return AiResponse(text: 'a cat');
  }
}

void main() {
  group('chunkText', () {
    test('keeps short text whole and drops empty text', () {
      expect(chunkText('hello'), ['hello']);
      expect(chunkText('  \n '), isEmpty);
    });

    test('splits long text under the limit with overlap', () {
      final text = List.generate(40, (i) => 'Sentence number $i.').join(' ');
      final chunks = chunkText(text, maxChars: 120, overlap: 20);
      expect(chunks.length, greaterThan(3));
      expect(chunks.every((c) => c.length <= 120), isTrue);
      expect(chunks.first, startsWith('Sentence number 0.'));
      expect(chunks.last, endsWith('Sentence number 39.'));
    });

    test('rejects an overlap that cannot make progress', () {
      expect(
        () => chunkText('x', maxChars: 10, overlap: 10),
        throwsArgumentError,
      );
    });
  });

  group('InMemoryVectorStore', () {
    test('ranks by cosine similarity and honours k and minScore', () {
      final store = InMemoryVectorStore()
        ..upsert(const VectorRecord(id: 'a', text: 'a', vector: [1, 0]))
        ..upsert(const VectorRecord(id: 'b', text: 'b', vector: [0.9, 0.1]))
        ..upsert(const VectorRecord(id: 'c', text: 'c', vector: [0, 1]));
      final hits = store.search([1, 0], k: 2);
      expect(hits.map((h) => h.record.id), ['a', 'b']);
      expect(store.search([1, 0], minScore: 0.5).length, 2);
    });

    test('rejects mixed dimensions', () {
      final store = InMemoryVectorStore()
        ..upsert(const VectorRecord(id: 'a', text: 'a', vector: [1, 0]));
      expect(
        () => store.upsert(
          const VectorRecord(id: 'b', text: 'b', vector: [1, 0, 0]),
        ),
        throwsArgumentError,
      );
    });

    test('round-trips through JSON', () {
      final store = InMemoryVectorStore()
        ..upsert(
          const VectorRecord(
            id: 'a',
            text: 'hi',
            vector: [0.5, 0.5],
            metadata: {'page': 2},
          ),
        );
      final copy = InMemoryVectorStore.fromJson(
        jsonDecode(jsonEncode(store.toJson())) as Map<String, dynamic>,
      );
      expect(copy.length, 1);
      expect(copy.records.single.metadata['page'], 2);
    });
  });

  group('RagIndex', () {
    late RagIndex index;
    setUp(() async {
      index = RagIndex(embedder: FakeOnDeviceAiEmbedder());
      await index.addDocument('pets', 'Cats purr and sleep on the sofa.');
      await index.addDocument('cars', 'Engines need oil and new tyres.');
    });

    test('finds the passage about the question', () async {
      final hits = await index.search('why do cats purr', minScore: 0.1);
      expect(hits.first.documentId, 'pets');
      expect(
        await index.contextFor('engine oil', minScore: 0.1),
        contains('[1]'),
      );
    });

    test('re-adding a document replaces its chunks', () async {
      await index.addDocument('pets', 'Dogs bark.');
      expect(index.store.length, 2);
      final hits = await index.search('dogs bark', minScore: 0.1);
      expect(hits.first.text, 'Dogs bark.');
    });

    test('works as a tool and survives JSON', () async {
      final tool = index.asTool(minScore: 0.1);
      final result = await tool.onCall({'query': 'cats'});
      expect((result['passages'] as List).first['document'], 'pets');

      final restored = RagIndex.fromJson(
        jsonDecode(jsonEncode(index.toJson())) as Map<String, dynamic>,
        embedder: FakeOnDeviceAiEmbedder(),
      );
      expect(
        (await restored.search('cats', minScore: 0.1)).first.documentId,
        'pets',
      );
    });

    test('empty index and blank query return nothing', () async {
      expect(
        await RagIndex(embedder: FakeOnDeviceAiEmbedder()).search('x'),
        isEmpty,
      );
      expect(await index.search('  '), isEmpty);
    });
  });

  group('fallback vision', () {
    setUp(() {
      FlutterDeviceAiPlatform.instance = FakeOnDeviceAiPlatform(
        availability: const OnDeviceAiAvailability(
          status: ModelFeatureStatus.unavailable,
          reason: AvailabilityReason.deviceNotEligible,
          message: 'none',
        ),
      );
    });

    test(
      'images reach a vision-capable fallback and show in capabilities',
      () async {
        final seen = <FallbackMessage>[];
        final ai = FlutterDeviceAi.withFallback(
          fallbackAdapter: _VisionAdapter(seen),
        );
        expect((await ai.capabilities()).imageInput, isTrue);
        final session = await ai.createSession();
        await session.addImage(
          Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/png',
        );
        final answer = await session.ask('what is this?');
        expect(answer.text, 'a cat');
        expect(seen.last.images.single.mimeType, 'image/png');
      },
    );

    test('a text-only fallback rejects images with a typed error', () async {
      final ai = FlutterDeviceAi.withFallback(
        fallbackAdapter: CallbackFallbackAdapter(
          onGenerateText: (p, {config, instructions}) async => 'x',
        ),
      );
      expect((await ai.capabilities()).imageInput, isFalse);
      final session = await ai.createSession();
      await expectLater(
        session.addImage(Uint8List(1)),
        throwsA(isA<OnDeviceAiUnsupportedException>()),
      );
    });
  });
}
