import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonSchema.validate', () {
    const schema = {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'minLength': 2},
        'age': {'type': 'integer', 'minimum': 0, 'maximum': 150},
        'tags': {
          'type': 'array',
          'maxItems': 2,
          'items': {'type': 'string'},
        },
        'role': {
          'type': 'string',
          'enum': ['admin', 'user'],
        },
      },
      'required': ['name', 'age'],
      'additionalProperties': false,
    };

    test('accepts a valid value', () {
      expect(
        JsonSchema.validate({
          'name': 'Al',
          'age': 3,
          'tags': ['a'],
          'role': 'user',
        }, schema),
        isEmpty,
      );
    });

    test('reports every problem with its path', () {
      final errors = JsonSchema.validate({
        'name': 'A',
        'age': 1.5,
        'tags': ['a', 'b', 'c'],
        'role': 'root',
        'extra': 1,
      }, schema);
      expect(errors, hasLength(5));
      expect(errors.join(), contains(r'$.name'));
      expect(errors.join(), contains(r'$.age must be an integer'));
      expect(errors.join(), contains('at most 2'));
      expect(errors.join(), contains('one of'));
      expect(errors.join(), contains('not an allowed property'));
    });

    test('flags missing required fields', () {
      expect(
        JsonSchema.validate({'name': 'Al'}, schema).single,
        contains('age is required'),
      );
    });
  });

  group('JsonSchema.ensureSupported', () {
    test('rejects unknown types', () {
      expect(
        () => JsonSchema.ensureSupported({'type': 'tuple'}),
        throwsA(isA<OnDeviceAiSchemaException>()),
      );
    });

    test('walks nested properties', () {
      expect(
        () => JsonSchema.ensureSupported({
          'type': 'object',
          'properties': {
            'a': {'type': 'wat'},
          },
        }),
        throwsA(isA<OnDeviceAiSchemaException>()),
      );
    });
  });

  group('JsonExtractor', () {
    test('plain object', () {
      expect(JsonExtractor.extract('{"a":1}'), {'a': 1});
    });

    test('fenced with chatter', () {
      expect(
        JsonExtractor.extract(
          'Sure!\n```json\n{"a": [1,2]}\n```\nAnything else?',
        ),
        {
          'a': [1, 2],
        },
      );
    });

    test('braces inside strings do not confuse balancing', () {
      expect(JsonExtractor.extract(r'{"a":"}{ \" }"} trailing'), {
        'a': '}{ " }',
      });
    });

    test('repairs truncated output', () {
      expect(
        JsonExtractor.extract(
          '{"title":"Run","blocks":[{"type":"note","content":"Go',
        ),
        {
          'title': 'Run',
          'blocks': [
            {'type': 'note', 'content': 'Go'},
          ],
        },
      );
    });

    test('drops a dangling key', () {
      expect(JsonExtractor.extract('{"a":1,"b"'), {'a': 1});
    });

    test('returns null without JSON', () {
      expect(JsonExtractor.extract('no json here'), isNull);
    });
  });
}
