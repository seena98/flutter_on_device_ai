import 'dart:convert';

import '../exceptions.dart';

/// A small, dependency-free JSON Schema engine.
///
/// It understands the subset that on-device models can realistically honour:
/// `type` (object, array, string, integer, number, boolean, null), `enum`,
/// `properties`, `required`, `additionalProperties: false`, `items`,
/// `minItems`/`maxItems`, `minLength`/`maxLength`, `minimum`/`maximum` and
/// `pattern`.
class JsonSchema {
  JsonSchema._();

  static const _types = {
    'object',
    'array',
    'string',
    'integer',
    'number',
    'boolean',
    'null',
  };

  /// Throws [OnDeviceAiSchemaException] when [schema] cannot be enforced.
  static void ensureSupported(
    Map<String, dynamic> schema, [
    String path = r'$',
  ]) {
    final type = schema['type'];
    if (type == null && schema['enum'] == null) {
      throw OnDeviceAiSchemaException(
        'Schema at $path needs a "type" or "enum".',
      );
    }
    if (type != null && !_types.contains(type)) {
      throw OnDeviceAiSchemaException(
        'Schema at $path has unsupported type "$type".',
      );
    }
    final props = schema['properties'];
    if (props is Map) {
      props.forEach((key, value) {
        if (value is! Map) {
          throw OnDeviceAiSchemaException(
            'Property "$key" at $path is not an object.',
          );
        }
        ensureSupported(Map<String, dynamic>.from(value), '$path.$key');
      });
    }
    final items = schema['items'];
    if (items is Map) {
      ensureSupported(Map<String, dynamic>.from(items), '$path[]');
    }
  }

  /// Returns a list of human readable problems; empty when [value] is valid.
  static List<String> validate(
    Object? value,
    Map<String, dynamic> schema, [
    String path = r'$',
  ]) {
    final errors = <String>[];

    final allowed = schema['enum'];
    if (allowed is List && !allowed.contains(value)) {
      errors.add('$path must be one of ${jsonEncode(allowed)}.');
      return errors;
    }

    final type = schema['type'];
    switch (type) {
      case 'object':
        if (value is! Map) {
          errors.add('$path must be an object.');
          return errors;
        }
        final props = schema['properties'];
        final propMap = props is Map ? props : const {};
        final required = schema['required'];
        if (required is List) {
          for (final key in required) {
            if (!value.containsKey(key)) {
              errors.add('$path.$key is required.');
            }
          }
        }
        value.forEach((key, v) {
          final sub = propMap[key];
          if (sub is Map) {
            errors.addAll(
              validate(v, Map<String, dynamic>.from(sub), '$path.$key'),
            );
          } else if (schema['additionalProperties'] == false) {
            errors.add('$path.$key is not an allowed property.');
          }
        });
      case 'array':
        if (value is! List) {
          errors.add('$path must be an array.');
          return errors;
        }
        final min = schema['minItems'];
        final max = schema['maxItems'];
        if (min is int && value.length < min) {
          errors.add('$path needs at least $min items.');
        }
        if (max is int && value.length > max) {
          errors.add('$path allows at most $max items.');
        }
        final items = schema['items'];
        if (items is Map) {
          for (var i = 0; i < value.length; i++) {
            errors.addAll(
              validate(value[i], Map<String, dynamic>.from(items), '$path[$i]'),
            );
          }
        }
      case 'string':
        if (value is! String) {
          errors.add('$path must be a string.');
          return errors;
        }
        final min = schema['minLength'];
        final max = schema['maxLength'];
        if (min is int && value.length < min) {
          errors.add('$path must have at least $min characters.');
        }
        if (max is int && value.length > max) {
          errors.add('$path must have at most $max characters.');
        }
        final pattern = schema['pattern'];
        if (pattern is String && !RegExp(pattern).hasMatch(value)) {
          errors.add('$path must match /$pattern/.');
        }
      case 'integer':
        if (value is! num || value != value.truncate()) {
          errors.add('$path must be an integer.');
          return errors;
        }
        errors.addAll(_range(value, schema, path));
      case 'number':
        if (value is! num) {
          errors.add('$path must be a number.');
          return errors;
        }
        errors.addAll(_range(value, schema, path));
      case 'boolean':
        if (value is! bool) errors.add('$path must be a boolean.');
      case 'null':
        if (value != null) errors.add('$path must be null.');
    }
    return errors;
  }

  static List<String> _range(
    num value,
    Map<String, dynamic> schema,
    String path,
  ) {
    final errors = <String>[];
    final min = schema['minimum'];
    final max = schema['maximum'];
    if (min is num && value < min) errors.add('$path must be >= $min.');
    if (max is num && value > max) errors.add('$path must be <= $max.');
    return errors;
  }
}

/// Helpers to pull JSON out of free-form model output.
class JsonExtractor {
  JsonExtractor._();

  /// Finds the first JSON object or array in [text] and decodes it.
  ///
  /// Handles Markdown fences, leading prose and truncated output (unterminated
  /// strings and missing closing brackets are repaired). Returns `null` when no
  /// JSON can be recovered.
  static Object? extract(String text) {
    var body = text.trim();
    final fence = RegExp(
      r'```(?:json|JSON)?\s*([\s\S]*?)(?:```|$)',
    ).firstMatch(body);
    if (fence != null && fence.group(1)!.trim().isNotEmpty) {
      body = fence.group(1)!.trim();
    }
    final start = body.indexOf(RegExp(r'[\{\[]'));
    if (start == -1) return null;
    body = body.substring(start);

    final end = _balancedEnd(body);
    if (end != null) {
      try {
        return jsonDecode(body.substring(0, end + 1));
      } catch (_) {}
    }
    final repaired = repairTruncated(body);
    if (repaired != null) {
      try {
        return jsonDecode(repaired);
      } catch (_) {}
      // The cut may have left a key without a value: drop it and retry.
      final withoutKey = repairTruncated(
        body.replaceFirst(RegExp(r',?\s*"[^"]*"\s*:?\s*$'), ''),
      );
      if (withoutKey != null) {
        try {
          return jsonDecode(withoutKey);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Index of the bracket closing the first value in [s], or `null`.
  static int? _balancedEnd(String s) {
    final stack = <String>[];
    var inString = false;
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{' || c == '[') {
        stack.add(c);
      } else if (c == '}' || c == ']') {
        if (stack.isEmpty) return null;
        stack.removeLast();
        if (stack.isEmpty) return i;
      }
    }
    return null;
  }

  /// Closes open strings and brackets of truncated JSON.
  static String? repairTruncated(String input) {
    final stack = <String>[];
    var inString = false;
    var escaped = false;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{' || c == '[') {
        stack.add(c);
      } else if (c == '}' || c == ']') {
        if (stack.isNotEmpty) stack.removeLast();
      }
    }
    if (stack.isEmpty && !inString) return null;

    var out = input.trimRight();
    if (inString) out = '$out"';
    // A trailing comma or colon cannot be closed.
    out = out.replaceFirst(RegExp(r'[,:\s]+$'), '');
    final closing = StringBuffer(out);
    for (final open in stack.reversed) {
      closing.write(open == '{' ? '}' : ']');
    }
    return closing.toString();
  }
}
