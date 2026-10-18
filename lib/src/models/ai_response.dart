import 'dart:convert';

/// Encapsulates the output of on-device AI generation.
class AiResponse {
  /// The raw generated text from the model.
  final String text;

  /// Approximate or exact token count generated, if provided by the engine.
  final int? tokenCount;

  /// Total generation time in milliseconds.
  final int? generationTimeMs;

  /// Cached parsed JSON object.
  Map<String, dynamic>? _cachedJson;

  /// Cached parsed arbitrary JSON structure (object, list, scalar).
  Object? _cachedDecodedJson;

  AiResponse({required this.text, this.tokenCount, this.generationTimeMs});

  /// Decodes [text] as a JSON Object (`Map<String, dynamic>`).
  ///
  /// Returns `null` if the text cannot be parsed as valid JSON or is not an object.
  Map<String, dynamic>? get json {
    if (_cachedJson != null) return _cachedJson;
    try {
      final decoded = jsonDecode(_sanitizeJson(text));
      if (decoded is Map<String, dynamic>) {
        _cachedJson = decoded;
      } else if (decoded is Map) {
        _cachedJson = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      _cachedJson = null;
    }
    return _cachedJson;
  }

  /// Decodes [text] as any valid JSON value (Map, List, num, String, bool).
  Object? get decodedJson {
    if (_cachedDecodedJson != null) return _cachedDecodedJson;
    try {
      _cachedDecodedJson = jsonDecode(_sanitizeJson(text));
    } catch (_) {
      _cachedDecodedJson = null;
    }
    return _cachedDecodedJson;
  }

  /// Removes potential markdown code fence wrappers (```json ... ```) from output.
  static String _sanitizeJson(String input) {
    var trimmed = input.trim();
    if (trimmed.startsWith('```json')) {
      trimmed = trimmed.substring(7);
    } else if (trimmed.startsWith('```')) {
      trimmed = trimmed.substring(3);
    }
    if (trimmed.endsWith('```')) {
      trimmed = trimmed.substring(0, trimmed.length - 3);
    }
    return trimmed.trim();
  }

  /// Serializes response to map.
  Map<String, dynamic> toMap() {
    return {
      'text': text,
      if (tokenCount != null) 'tokenCount': tokenCount,
      if (generationTimeMs != null) 'generationTimeMs': generationTimeMs,
    };
  }

  /// Constructs [AiResponse] from platform map.
  factory AiResponse.fromMap(Map<String, dynamic> map) {
    return AiResponse(
      text: map['text'] as String? ?? '',
      tokenCount: map['tokenCount'] as int?,
      generationTimeMs: map['generationTimeMs'] as int?,
    );
  }

  @override
  String toString() =>
      'AiResponse(tokens: $tokenCount, time: ${generationTimeMs}ms, text: ${text.length > 50 ? "${text.substring(0, 50)}..." : text})';
}
