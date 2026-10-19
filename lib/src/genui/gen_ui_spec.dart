import 'dart:convert';

/// Block kinds a generated module may contain, with the fields each needs.
///
/// | type        | fields                                              |
/// |-------------|-----------------------------------------------------|
/// | `stat`      | `label`, `value`, optional `subtext`                |
/// | `progress`  | `label`, `current`, `target`, optional `unit`       |
/// | `checklist` | `items`: `[{title, completed}]`                     |
/// | `list`      | optional `title`, `items`: `[String]`               |
/// | `steps`     | `items`: `[{title, detail}]`                        |
/// | `table`     | `columns`: `[String]`, `rows`: `[[String]]`         |
/// | `callout`   | `kind` (info/warning/success), `content`            |
/// | `note`      | `content`                                           |
class GenUiBlockTypes {
  GenUiBlockTypes._();

  static const all = [
    'stat',
    'progress',
    'checklist',
    'list',
    'steps',
    'table',
    'callout',
    'note',
  ];

  /// Normalises one raw block. Returns `null` when it cannot be rendered.
  static Map<String, dynamic>? sanitize(Object? raw) {
    if (raw is! Map) return null;
    final block = Map<String, dynamic>.from(raw);
    final type = block['type'];
    if (type is! String || !all.contains(type)) return null;

    String str(String key, [String fallback = '']) {
      final v = block[key];
      return v == null ? fallback : v.toString();
    }

    num number(String key, [num fallback = 0]) {
      final v = block[key];
      if (v is num) return v;
      return num.tryParse(v?.toString() ?? '') ?? fallback;
    }

    switch (type) {
      case 'stat':
        if (str('label').isEmpty && str('value').isEmpty) return null;
        return {
          'type': type,
          'label': str('label'),
          'value': str('value'),
          if (str('subtext').isNotEmpty) 'subtext': str('subtext'),
        };
      case 'progress':
        final target = number('target', 100);
        return {
          'type': type,
          'label': str('label'),
          'current': number('current'),
          'target': target == 0 ? 100 : target,
          if (str('unit').isNotEmpty) 'unit': str('unit'),
        };
      case 'checklist':
        final items = <Map<String, dynamic>>[];
        for (final item in block['items'] as List? ?? const []) {
          if (item is Map) {
            final title = item['title']?.toString() ?? '';
            if (title.isNotEmpty) {
              items.add({
                'title': title,
                'completed': item['completed'] == true,
              });
            }
          } else if (item != null && item.toString().isNotEmpty) {
            items.add({'title': item.toString(), 'completed': false});
          }
        }
        return items.isEmpty ? null : {'type': type, 'items': items};
      case 'list':
        final items = [
          for (final i in block['items'] as List? ?? const [])
            if (i != null && i.toString().isNotEmpty) i.toString(),
        ];
        if (items.isEmpty) return null;
        return {
          'type': type,
          if (str('title').isNotEmpty) 'title': str('title'),
          'items': items,
        };
      case 'steps':
        final items = <Map<String, dynamic>>[];
        for (final item in block['items'] as List? ?? const []) {
          if (item is Map && (item['title']?.toString() ?? '').isNotEmpty) {
            items.add({
              'title': item['title'].toString(),
              'detail': item['detail']?.toString() ?? '',
            });
          } else if (item is String && item.isNotEmpty) {
            items.add({'title': item, 'detail': ''});
          }
        }
        return items.isEmpty ? null : {'type': type, 'items': items};
      case 'table':
        final columns = [
          for (final c in block['columns'] as List? ?? const []) c.toString(),
        ];
        final rows = <List<String>>[];
        for (final r in block['rows'] as List? ?? const []) {
          if (r is! List) continue;
          // Small models return ragged rows; pad or trim to the header width.
          rows.add([
            for (var i = 0; i < columns.length; i++)
              i < r.length ? r[i].toString() : '',
          ]);
        }
        if (columns.isEmpty || rows.isEmpty) return null;
        return {'type': type, 'columns': columns, 'rows': rows};
      case 'callout':
        if (str('content').isEmpty) return null;
        final kind = str('kind', 'info');
        return {
          'type': type,
          'kind': const ['info', 'warning', 'success'].contains(kind)
              ? kind
              : 'info',
          'content': str('content'),
        };
      case 'note':
        return str('content').isEmpty
            ? null
            : {'type': type, 'content': str('content')};
    }
    return null;
  }

  /// JSON Schema for a whole module, used for schema-constrained generation.
  static Map<String, dynamic> get moduleSchema => {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
      'icon': {'type': 'string'},
      'tone': {
        'type': 'string',
        'enum': ['motivational', 'neutral', 'urgent', 'celebratory'],
      },
      'blurb': {'type': 'string'},
      'blocks': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 6,
        'items': {
          'type': 'object',
          'properties': {
            'type': {'type': 'string', 'enum': all},
            'label': {'type': 'string'},
            'value': {'type': 'string'},
            'subtext': {'type': 'string'},
            'current': {'type': 'number'},
            'target': {'type': 'number'},
            'unit': {'type': 'string'},
            'title': {'type': 'string'},
            'content': {'type': 'string'},
            'kind': {'type': 'string'},
            'items': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'title': {'type': 'string'},
                  'detail': {'type': 'string'},
                  'completed': {'type': 'boolean'},
                },
                'required': ['title'],
              },
            },
          },
          'required': ['type'],
        },
      },
    },
    'required': ['title', 'blocks'],
  };
}

/// A validated generative-UI module: a titled list of typed blocks that your
/// own widgets (or a renderer such as `genui`) turn into a screen.
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

  /// Module as plain JSON.
  Map<String, dynamic> toModuleJson() => {
    'title': title,
    'icon': icon,
    'tone': tone,
    'blurb': blurb,
    'blocks': blocks,
  };

  /// Blocks as `{id, type, properties}` component maps.
  List<Map<String, dynamic>> toComponentMaps() {
    return [
      for (var i = 0; i < blocks.length; i++)
        {
          'id': 'block_$i',
          'type': blocks[i]['type'],
          'properties': Map<String, dynamic>.from(blocks[i])..remove('type'),
        },
    ];
  }

  /// Builds a module from raw JSON, dropping blocks that cannot be rendered.
  /// Returns `null` when nothing renderable remains.
  static GenUiModuleSpec? tryFromJson(Map<String, dynamic> json) {
    final blocks = <Map<String, dynamic>>[];
    for (final raw in json['blocks'] as List? ?? const []) {
      final clean = GenUiBlockTypes.sanitize(raw);
      if (clean != null) blocks.add(clean);
    }
    if (blocks.isEmpty) return null;
    return GenUiModuleSpec(
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : 'Untitled module',
      icon: json['icon'] as String? ?? 'sparkles',
      tone: json['tone'] as String? ?? 'neutral',
      blurb: json['blurb'] as String? ?? '',
      blocks: blocks,
    );
  }

  @override
  String toString() => jsonEncode(toModuleJson());
}
