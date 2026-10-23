import '../models/tool.dart';
import 'embedder.dart';
import 'vector_store.dart';

/// Splits [text] into chunks of at most [maxChars], preferring paragraph and
/// sentence boundaries, with [overlap] characters repeated between neighbours.
List<String> chunkText(String text, {int maxChars = 800, int overlap = 100}) {
  if (maxChars <= 0 || overlap < 0 || overlap >= maxChars) {
    throw ArgumentError('Need 0 <= overlap < maxChars.');
  }
  final clean = text.replaceAll('\r\n', '\n').trim();
  if (clean.isEmpty) return const [];
  if (clean.length <= maxChars) return [clean];

  final chunks = <String>[];
  var start = 0;
  while (start < clean.length) {
    var end = start + maxChars;
    if (end >= clean.length) {
      chunks.add(clean.substring(start).trim());
      break;
    }
    // Break at the last paragraph, sentence or word boundary in the window.
    final window = clean.substring(start, end);
    final floor = window.length ~/ 2;
    var cut = -1;
    for (final sep in ['\n\n', '. ', '! ', '? ', '\n', ' ']) {
      final i = window.lastIndexOf(sep);
      if (i >= floor) {
        cut = i + sep.length;
        break;
      }
    }
    if (cut < 0) cut = window.length;
    final piece = window.substring(0, cut).trim();
    if (piece.isNotEmpty) chunks.add(piece);
    final next = start + cut - overlap;
    start = next > start ? next : start + cut;
  }
  return chunks;
}

/// A passage found by [RagIndex.search].
class RagHit {
  const RagHit({
    required this.documentId,
    required this.text,
    required this.score,
    required this.metadata,
  });

  final String documentId;
  final String text;
  final double score;
  final Map<String, dynamic> metadata;
}

/// Retrieval for grounding answers in your own documents, fully on device.
///
/// ```dart
/// final index = RagIndex(embedder: LocalEmbedder());
/// await index.addDocument('manual', manualText);
/// final session = await ai.createSession(tools: [index.asTool()]);
/// ```
class RagIndex {
  RagIndex({
    required this.embedder,
    InMemoryVectorStore? store,
    this.chunkChars = 800,
    this.chunkOverlap = 100,
  }) : store = store ?? InMemoryVectorStore();

  final OnDeviceAiEmbedder embedder;
  final InMemoryVectorStore store;
  final int chunkChars;
  final int chunkOverlap;

  /// Chunks, embeds and stores [text] under [id], replacing an earlier
  /// document with the same id. Returns the number of chunks stored.
  Future<int> addDocument(
    String id,
    String text, {
    Map<String, dynamic> metadata = const {},
  }) async {
    final chunks = chunkText(text, maxChars: chunkChars, overlap: chunkOverlap);
    final vectors = await embedder.embedBatch(chunks);
    store.removeDocument(id);
    for (var i = 0; i < chunks.length; i++) {
      store.upsert(
        VectorRecord(
          id: '$id#$i',
          text: chunks[i],
          vector: vectors[i],
          metadata: {...metadata, 'documentId': id, 'chunk': i},
        ),
      );
    }
    return chunks.length;
  }

  /// Removes a document added with [addDocument].
  int removeDocument(String id) => store.removeDocument(id);

  /// The [k] passages closest to [query].
  Future<List<RagHit>> search(
    String query, {
    int k = 4,
    double minScore = 0.3,
  }) async {
    if (store.length == 0 || query.trim().isEmpty) return const [];
    final vector = await embedder.embedQuery(query);
    return [
      for (final r in store.search(vector, k: k, minScore: minScore))
        RagHit(
          documentId: r.record.metadata['documentId'] as String? ?? r.record.id,
          text: r.record.text,
          score: r.score,
          metadata: r.record.metadata,
        ),
    ];
  }

  /// The best passages for [query] joined into a block to put in a prompt,
  /// capped at [maxChars]. Empty when nothing is relevant.
  Future<String> contextFor(
    String query, {
    int k = 4,
    double minScore = 0.3,
    int maxChars = 2400,
  }) async {
    final buffer = StringBuffer();
    var n = 1;
    for (final hit in await search(query, k: k, minScore: minScore)) {
      final entry = '[$n] ${hit.text}\n';
      if (buffer.length + entry.length > maxChars) break;
      buffer.write(entry);
      n++;
    }
    return buffer.toString().trimRight();
  }

  /// A tool a session can call to look things up in this index, so the model
  /// decides when to retrieve.
  OnDeviceAiTool asTool({
    String name = 'search_documents',
    String description =
        'Searches the user\'s documents and returns the most relevant '
        'passages. Call it before answering questions about their content.',
    int k = 4,
    double minScore = 0.3,
  }) => OnDeviceAiTool(
    name: name,
    description: description,
    parameters: const [
      ToolParameter(
        name: 'query',
        type: ToolArgumentType.string,
        description: 'What to look for, in a few words.',
      ),
    ],
    onCall: (args) async {
      final hits = await search(
        (args['query'] ?? '').toString(),
        k: k,
        minScore: minScore,
      );
      return {
        'passages': [
          for (final h in hits) {'document': h.documentId, 'text': h.text},
        ],
      };
    },
  );

  /// Snapshot for saving to disk. Restore with [RagIndex.fromJson].
  Map<String, dynamic> toJson() => store.toJson();

  /// Restores an index saved with [toJson]. The [embedder] must be the model
  /// that made the stored vectors.
  factory RagIndex.fromJson(
    Map<String, dynamic> json, {
    required OnDeviceAiEmbedder embedder,
    int chunkChars = 800,
    int chunkOverlap = 100,
  }) => RagIndex(
    embedder: embedder,
    store: InMemoryVectorStore.fromJson(json),
    chunkChars: chunkChars,
    chunkOverlap: chunkOverlap,
  );
}
