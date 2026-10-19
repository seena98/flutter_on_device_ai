import 'dart:convert';

import '../models/tool.dart';
import '../schema/json_schema.dart';

/// Instruction block that teaches a text-only model to call tools by emitting
/// a JSON object.
String emulatedToolInstruction(List<OnDeviceAiTool> tools) {
  final catalogue = tools
      .map(
        (t) => {
          'name': t.name,
          'description': t.description,
          'arguments': t.resolvedParameterSchema,
        },
      )
      .toList();
  final example = jsonEncode({
    'tool': tools.first.name,
    'arguments': {
      for (final p in (tools.first.parameters ?? const <ToolParameter>[]).where(
        (p) => !p.optional,
      ))
        p.name: switch (p.type) {
          ToolArgumentType.number => 1,
          ToolArgumentType.integer => 1,
          ToolArgumentType.boolean => true,
          _ => 'text',
        },
    },
  });
  return '''
You can use tools. To use one, reply with ONLY this JSON object and nothing else:
{"tool": "<tool name>", "arguments": { ... }}
Example of a tool call (no other words, no Markdown): $example
You will then receive the tool result and must answer the user with it.
If no tool is needed, just answer normally in plain language.
Available tools:
${const JsonEncoder.withIndent('  ').convert(catalogue)}''';
}

/// A tool invocation parsed out of model text.
class ParsedToolCall {
  const ParsedToolCall(this.tool, this.arguments);
  final OnDeviceAiTool tool;
  final Map<String, dynamic> arguments;
}

/// Result of inspecting a model reply for a tool call.
class ToolCallParse {
  const ToolCallParse.none() : call = null, unknownName = null;
  const ToolCallParse.found(ParsedToolCall this.call) : unknownName = null;
  const ToolCallParse.unknown(String this.unknownName) : call = null;

  final ParsedToolCall? call;
  final String? unknownName;
  bool get isToolRequest => call != null || unknownName != null;
}

/// Detects `{"tool": "...", "arguments": {...}}` in [text].
///
/// Only replies that *are* the JSON object (optionally fenced) count; prose
/// that merely mentions JSON is a normal answer.
ToolCallParse parseToolCall(String text, List<OnDeviceAiTool> tools) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('`')) {
    return const ToolCallParse.none();
  }
  final decoded = JsonExtractor.extract(text);
  if (decoded is! Map) return const ToolCallParse.none();
  final name = decoded['tool'] ?? decoded['name'];
  if (name is! String) return const ToolCallParse.none();
  final args = decoded['arguments'] ?? decoded['args'] ?? decoded['parameters'];
  for (final tool in tools) {
    if (tool.name == name) {
      return ToolCallParse.found(
        ParsedToolCall(
          tool,
          args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{},
        ),
      );
    }
  }
  return ToolCallParse.unknown(name);
}

/// Runs the tool and wraps failures so the model can read them.
Future<Map<String, dynamic>> runTool(ParsedToolCall call) async {
  final problems = JsonSchema.validate(
    call.arguments,
    call.tool.resolvedParameterSchema,
    'arguments',
  );
  if (problems.isNotEmpty) {
    return {'error': 'Invalid arguments: ${problems.join(' ')}'};
  }
  try {
    return await call.tool.onCall(call.arguments);
  } on OnDeviceAiToolException catch (e) {
    return {'error': e.message, if (e.details != null) 'details': e.details};
  } catch (e) {
    return {'error': e.toString()};
  }
}
