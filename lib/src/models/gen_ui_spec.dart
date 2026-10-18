import 'dart:convert';
import 'package:flutter/foundation.dart';

/// A validated generative UI module specification produced by an on-device model.
class GenUiModuleSpec {
  final String title;
  final String icon;
  final String tone;
  final String blurb;
  final List<Map<String, dynamic>> blocks;

  const GenUiModuleSpec({
    required this.title,
    required this.icon,
    required this.tone,
    required this.blurb,
    required this.blocks,
  });

  /// Serializes to the standard typed-block format expected by genui renderers.
  Map<String, dynamic> toModuleJson() {
    return {
      'title': title,
      'icon': icon,
      'tone': tone,
      'blurb': blurb,
      'blocks': blocks,
    };
  }

  /// Converts the typed blocks into standard A2UI component maps for surface renderers.
  List<Map<String, dynamic>> toComponentMaps() {
    final components = <Map<String, dynamic>>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final type = block['type'] as String? ?? 'card';
      final props = Map<String, dynamic>.from(block)..remove('type');
      components.add({'id': 'block_$i', 'type': type, 'properties': props});
    }
    return components;
  }

  /// Deserializes a module specification from a JSON map.
  factory GenUiModuleSpec.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'];
    final blocksList = <Map<String, dynamic>>[];
    if (rawBlocks is List) {
      for (final item in rawBlocks) {
        if (item is Map<String, dynamic>) {
          blocksList.add(item);
        } else if (item is Map) {
          blocksList.add(Map<String, dynamic>.from(item));
        }
      }
    }

    return GenUiModuleSpec(
      title: json['title'] as String? ?? 'Untitled Module',
      icon: json['icon'] as String? ?? 'sparkles',
      tone: json['tone'] as String? ?? 'informative',
      blurb: json['blurb'] as String? ?? '',
      blocks: blocksList,
    );
  }
}

/// System instructions and parser for turning natural-language goals into typed-block GenUI modules.
class OnDeviceUiGenerator {
  /// System instructions embedded in genUI prompt requests.
  static const String genUiInstructions = '''
You are a UI Designer that outputs ONLY valid JSON representing a typed-block UI module.
Do not include conversational preamble or markdown code fences outside JSON.
Output schema:
{
  "title": "Short title",
  "icon": "icon_name (e.g. check_circle, trending_up, fitness_center, lightbulb)",
  "tone": "motivational | neutral | urgent | celebratory",
  "blurb": "One short introductory sentence",
  "blocks": [
    {"type": "stat", "label": "String", "value": "String", "subtext": "String"},
    {"type": "progress", "label": "String", "current": 0, "target": 100, "unit": "String"},
    {"type": "checklist", "items": [{"title": "String", "completed": false}]},
    {"type": "note", "content": "String"}
  ]
}
''';

  /// Parses and repairs raw model text into a valid [GenUiModuleSpec].
  ///
  /// Automatically repairs missing closing brackets or truncated JSON output.
  static GenUiModuleSpec? parseModelOutput(String rawText) {
    var text = rawText.trim();
    if (text.isEmpty) return null;

    // Strip Markdown code fences if present
    if (text.contains('```json')) {
      final start = text.indexOf('```json') + 7;
      final end = text.indexOf('```', start);
      text = end != -1
          ? text.substring(start, end).trim()
          : text.substring(start).trim();
    } else if (text.contains('```')) {
      final start = text.indexOf('```') + 3;
      final end = text.indexOf('```', start);
      text = end != -1
          ? text.substring(start, end).trim()
          : text.substring(start).trim();
    }

    // Isolate first '{' to last '}'
    final firstBrace = text.indexOf('{');
    if (firstBrace == -1) return null;
    var lastBrace = text.lastIndexOf('}');
    if (lastBrace < firstBrace) {
      // Truncation repair: append missing closing brackets
      text = '${text.substring(firstBrace)}\n}\n}';
    } else {
      text = text.substring(firstBrace, lastBrace + 1);
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return GenUiModuleSpec.fromJson(decoded);
      } else if (decoded is Map) {
        return GenUiModuleSpec.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      // Attempt heuristic bracket repair if truncated
      final repaired = _attemptBracketRepair(text);
      if (repaired != null) {
        try {
          final decoded = jsonDecode(repaired);
          if (decoded is Map) {
            return GenUiModuleSpec.fromJson(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      }
      debugPrint('Failed to parse GenUI model output: $e\nRaw: $text');
    }
    return null;
  }

  static String? _attemptBracketRepair(String input) {
    var openCurly = 0;
    var openSquare = 0;
    var inQuotes = false;
    var escape = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (char == '\\') {
        escape = true;
        continue;
      }
      if (char == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (!inQuotes) {
        if (char == '{') openCurly++;
        if (char == '}') openCurly--;
        if (char == '[') openSquare++;
        if (char == ']') openSquare--;
      }
    }

    if (openCurly <= 0 && openSquare <= 0) return null;

    final buffer = StringBuffer(input);
    if (inQuotes) buffer.write('"');
    while (openSquare > 0) {
      buffer.write(']');
      openSquare--;
    }
    while (openCurly > 0) {
      buffer.write('}');
      openCurly--;
    }
    return buffer.toString();
  }
}
