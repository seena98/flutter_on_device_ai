import 'dart:math' as math;

/// A stored passage and its embedding.
class VectorRecord {
  const VectorRecord({
    required this.id,
    required this.text,
    required this.vector,
    this.metadata = const {},
  });

  factory VectorRecord.fromJson(Map<String, dynamic> json) => VectorRecord(
    id: json['id'] as String,
    text: json['text'] as String,
    vector: [for (final v in json['vector'] as List) (v as num).toDouble()],
    metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
  );

  final String id;
  final String text;
  final List<double> vector;

  /// Free-form JSON-encodable data (source, page, ...).
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'vector': vector,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// A search result.
class VectorSearchResult {
  const VectorSearchResult(this.record, this.score);

  final VectorRecord record;

  /// Cosine similarity in `-1..1`; higher is closer.
  final double score;
}

/// Cosine similarity of [a] and [b] (0 when either has no length).
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError(
      'Vectors differ in length (${a.length} vs ${b.length}); were they made '
      'by different embedding models?',
    );
  }
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Brute-force in-memory vector index. Fine for the thousands of passages an
/// app keeps on a phone; persist it with [toJson] / [InMemoryVectorStore.fromJson].
class InMemoryVectorStore {
  InMemoryVectorStore();

  factory InMemoryVectorStore.fromJson(Map<String, dynamic> json) {
    final store = InMemoryVectorStore();
    for (final r in json['records'] as List) {
      store.upsert(VectorRecord.fromJson(Map<String, dynamic>.from(r as Map)));
    }
    return store;
  }

  final Map<String, VectorRecord> _records = {};

  int get length => _records.length;
  Iterable<VectorRecord> get records => _records.values;

  /// Vector length, or null while empty.
  int? get dimensions =>
      _records.isEmpty ? null : _records.values.first.vector.length;

  /// Adds [record], replacing one with the same id.
  void upsert(VectorRecord record) {
    final replacingOnlyRecord =
        _records.length == 1 && _records.containsKey(record.id);
    final dims = dimensions;
    if (dims != null && record.vector.length != dims && !replacingOnlyRecord) {
      throw ArgumentError(
        'Vector has ${record.vector.length} dimensions, the store holds '
        '$dims.',
      );
    }
    _records[record.id] = record;
  }

  bool remove(String id) => _records.remove(id) != null;

  /// Removes every record whose id equals [prefix] or starts with `prefix#`.
  int removeDocument(String prefix) {
    final ids = _records.keys
        .where((id) => id == prefix || id.startsWith('$prefix#'))
        .toList();
    ids.forEach(_records.remove);
    return ids.length;
  }

  void clear() => _records.clear();

  /// The [k] records closest to [query], best first, at or above [minScore].
  List<VectorSearchResult> search(
    List<double> query, {
    int k = 4,
    double minScore = -1,
  }) {
    final hits =
        <VectorSearchResult>[
            for (final r in _records.values)
              VectorSearchResult(r, cosineSimilarity(query, r.vector)),
          ].where((h) => h.score >= minScore).toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return hits.take(k).toList();
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'records': [for (final r in _records.values) r.toJson()],
  };
}
