import 'dart:async';

import '../../flutter_device_ai.dart';

/// Turns a natural-language goal into a validated [GenUiModuleSpec].
///
/// ```dart
/// final generator = OnDeviceUiGenerator();
/// final module = await generator.generateModule('5K running plan for a week');
/// ```
class OnDeviceUiGenerator {
  OnDeviceUiGenerator([FlutterDeviceAi? ai]) : _ai = ai ?? FlutterDeviceAi();

  final FlutterDeviceAi _ai;

  /// Why the last call returned `null`, if it did.
  String? lastError;

  /// System prompt describing the block vocabulary. Reusable with any engine.
  static const String genUiInstructions = '''
You are a UI designer. Reply with ONLY one JSON object describing a screen made of typed blocks. No prose, no Markdown fences.
{
  "title": "short title",
  "icon": "one word icon name",
  "tone": "motivational | neutral | urgent | celebratory",
  "blurb": "one short sentence",
  "blocks": [
    {"type": "stat", "label": "", "value": "", "subtext": ""},
    {"type": "progress", "label": "", "current": 0, "target": 100, "unit": ""},
    {"type": "checklist", "items": [{"title": "", "completed": false}]},
    {"type": "list", "title": "", "items": [""]},
    {"type": "steps", "items": [{"title": "", "detail": ""}]},
    {"type": "table", "columns": [""], "rows": [[""]]},
    {"type": "callout", "kind": "info | warning | success", "content": ""},
    {"type": "note", "content": ""}
  ]
}
Use 2 to 5 blocks. Pick only the block types that fit the goal.''';

  /// Parses and repairs raw model text into a module (`null` if unusable).
  static GenUiModuleSpec? parseModelOutput(String rawText) {
    final decoded = JsonExtractor.extract(rawText);
    if (decoded is! Map) return null;
    return GenUiModuleSpec.tryFromJson(Map<String, dynamic>.from(decoded));
  }

  /// Generates a module for [goal].
  ///
  /// [principles] adds design guidance, [language] localises the copy,
  /// [tools] lets the model look things up while designing, and [onText]
  /// receives the raw text as it streams in.
  Future<GenUiModuleSpec?> generateModule(
    String goal, {
    String? principles,
    String? language,
    List<OnDeviceAiTool>? tools,
    void Function(String textSoFar)? onText,
  }) async {
    lastError = null;
    if (!await _ai.isAvailable()) {
      lastError = await _ai.availabilityReason();
      return null;
    }

    final instruction = StringBuffer(genUiInstructions);
    if (principles != null && principles.trim().isNotEmpty) {
      instruction.write('\nDesign principles: ${principles.trim()}');
    }
    if (language != null && language.trim().isNotEmpty) {
      instruction.write('\nWrite all user-facing text in ${language.trim()}.');
    }

    final session = await _ai.createSession(
      systemInstruction: instruction.toString(),
      tools: tools,
    );
    try {
      final caps = await _ai.capabilities();
      final config = GenerationConfig(
        maxTokens: 900,
        temperature: 0.4,
        responseFormat: ResponseFormat.json,
        schema: caps.structuredOutput == CapabilitySupport.native
            ? GenUiBlockTypes.moduleSchema
            : null,
      );

      final buffer = StringBuffer();
      await session.addQuery('Goal: $goal');
      await for (final chunk in session.getResponseAsync(config: config)) {
        buffer.write(chunk);
        onText?.call(buffer.toString());
      }
      final module = parseModelOutput(buffer.toString());
      if (module == null) {
        lastError = 'The model did not return a renderable module.';
      }
      return module;
    } on OnDeviceAiException catch (e) {
      lastError = e.message;
      return null;
    } finally {
      await session.close();
    }
  }
}
