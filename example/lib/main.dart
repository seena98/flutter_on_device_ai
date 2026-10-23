import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_device_ai/flutter_device_ai.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  /// [embedder] powers the Docs tab; defaults to the local GGUF embedder.
  const ExampleApp({super.key, this.embedder});

  final OnDeviceAiEmbedder? embedder;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F766E),
        brightness: b,
      ),
    );
    return MaterialApp(
      title: 'On-device AI',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: Home(embedder: embedder),
    );
  }
}

/// Local models offered when the OS has none (any GGUF works, see "Custom").
final _models = [
  for (final p in LocalLlmFallbackAdapter.presets)
    (
      '${p.label} (${p.sizeMb >= 1000 ? '${(p.sizeMb / 1000).toStringAsFixed(1)} GB' : '${p.sizeMb} MB'})',
      p.source,
    ),
];

LocalLlmFallbackAdapter _newLocalModel(
  String source,
) => LocalLlmFallbackAdapter(
  model: source,
  // Free the memory after 5 idle minutes; the next request reloads from disk.
  idleUnloadAfter: const Duration(minutes: 5),
);

class Home extends StatefulWidget {
  const Home({super.key, this.embedder});

  final OnDeviceAiEmbedder? embedder;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // Uses the OS model when there is one, else a local llama.cpp model that is
  // downloaded on demand.
  final _ai = FlutterDeviceAi.withFallback(
    fallbackAdapter: _newLocalModel(LocalLlmFallbackAdapter.defaultModel),
  );

  late final OnDeviceAiEmbedder _embedder = widget.embedder ?? LocalEmbedder();

  LocalLlmFallbackAdapter get _local =>
      _ai.fallbackAdapter! as LocalLlmFallbackAdapter;

  OnDeviceAiAvailability? _availability;
  OnDeviceAiCapabilities? _caps;
  double? _downloadProgress;
  String? _setupError;
  String _model = LocalLlmFallbackAdapter.defaultModel;
  int _modelEpoch = 0;

  Future<void> _selectModel(String source) async {
    source = source.trim();
    if (source.isEmpty || source == _model) return;
    final old = _ai.fallbackAdapter;
    _ai.fallbackAdapter = _newLocalModel(source);
    _model = source;
    _modelEpoch++;
    await old?.dispose();
    await _refresh();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _embedder.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final availability = await _ai.availability();
    final caps = await _ai.capabilities();
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _caps = caps;
    });
  }

  Future<void> _prepare() async {
    setState(() {
      _setupError = null;
      _downloadProgress = 0;
    });
    try {
      await _ai.prepare(
        onProgress: (p) => setState(() => _downloadProgress = p),
      );
    } on OnDeviceAiException catch (e) {
      _setupError = e.message;
    }
    _downloadProgress = null;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        _caps != null && _caps!.backend != OnDeviceAiBackend.unsupported;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('On-device AI'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chat'),
              Tab(text: 'Extract'),
              Tab(text: 'Tools'),
              Tab(text: 'Screen'),
              Tab(text: 'Docs'),
            ],
          ),
        ),
        body: Column(
          children: [
            _StatusBar(
              availability: _availability,
              caps: _caps,
              progress: _downloadProgress,
              error: _setupError,
              fallbackReady: ready,
              model: _model,
              onModel: _selectModel,
              local: _local,
              onCancel: () => _local.cancelPrepare(),
              onDelete: () async {
                await _local.deleteModel();
                await _refresh();
              },
              busy: _downloadProgress != null,
              onPrepare: _prepare,
            ),
            Expanded(
              child: ready
                  ? TabBarView(
                      children: [
                        ChatTab(key: ValueKey(_modelEpoch), ai: _ai),
                        ExtractTab(key: ValueKey(_modelEpoch), ai: _ai),
                        ToolsTab(key: ValueKey(_modelEpoch), ai: _ai),
                        ScreenTab(key: ValueKey(_modelEpoch), ai: _ai),
                        DocsTab(
                          key: ValueKey(_modelEpoch),
                          ai: _ai,
                          embedder: _embedder,
                        ),
                      ],
                    )
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No model is usable yet. Follow the message above, or '
                          'download the local model.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.availability,
    required this.caps,
    required this.progress,
    required this.error,
    required this.fallbackReady,
    required this.model,
    required this.onModel,
    required this.local,
    required this.onCancel,
    required this.onDelete,
    required this.busy,
    required this.onPrepare,
  });

  final OnDeviceAiAvailability? availability;
  final OnDeviceAiCapabilities? caps;
  final double? progress;
  final String? error;
  final bool fallbackReady;
  final String model;
  final ValueChanged<String> onModel;
  final LocalLlmFallbackAdapter local;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final bool busy;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    final a = availability;
    final c = caps;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a == null
                  ? 'Probing…'
                  : '${c?.backend.name ?? '?'} · ${a.status.name}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (a != null)
              Text(a.message, style: Theme.of(context).textTheme.bodySmall),
            if (c != null)
              Text(
                'tools: ${c.toolCalling.name} · structured: ${c.structuredOutput.name} · '
                'images: ${c.imageInput} · exact tokens: ${c.exactTokenCounts}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (a != null && !a.isReady)
              _ModelPicker(model: model, onChanged: onModel, enabled: !busy),
            if (a != null && !a.isReady)
              StreamBuilder<LocalLlmStatus>(
                stream: local.status,
                initialData: local.currentStatus,
                builder: (context, snap) {
                  final st = snap.data!;
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'local model: ${st.phase.name}'
                          '${st.progress == null || st.phase == LocalLlmPhase.ready ? '' : ' ${(st.progress! * 100).round()}%'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (st.phase == LocalLlmPhase.downloading)
                        TextButton(
                          onPressed: onCancel,
                          child: const Text('Cancel'),
                        ),
                      if (fallbackReady && !busy)
                        TextButton(
                          onPressed: onDelete,
                          child: const Text('Delete model'),
                        ),
                    ],
                  );
                },
              ),
            if (progress != null) LinearProgressIndicator(value: progress),
            if (error != null)
              Text(error!, style: TextStyle(color: scheme.error)),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (a != null && !a.isReady && !fallbackReady)
                  FilledButton.tonal(
                    onPressed: onPrepare,
                    child: Text(
                      a.status == ModelFeatureStatus.unavailable
                          ? 'Download local model'
                          : 'Download model',
                    ),
                  ),
                if (a?.reason == AvailabilityReason.systemComponentMissing)
                  FilledButton.tonal(
                    onPressed: () => FlutterDeviceAi().openAICorePlayStore(),
                    child: const Text('Open AICore in Play Store'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.ai});
  final FlutterDeviceAi ai;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _input = TextEditingController();
  final _messages = <(bool, String)>[];
  OnDeviceAiSession? _session;
  String _live = '';
  bool _busy = false;
  int? _tokens;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _messages.add((true, text));
      _busy = true;
      _live = '';
    });
    try {
      _session ??= await widget.ai.createSession(
        systemInstruction: 'You are a concise, friendly assistant.',
      );
      await for (final chunk in _session!.askStream(text)) {
        setState(() => _live += chunk);
      }
      _tokens = await _session!.countTokens();
      setState(() => _messages.add((false, _live)));
    } on OnDeviceAiCancelledException {
      setState(() => _messages.add((false, '$_live (stopped)')));
    } on OnDeviceAiException catch (e) {
      setState(() => _messages.add((false, 'Error: ${e.message}')));
    } finally {
      setState(() {
        _live = '';
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    _session?.close();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final m in _messages) _Bubble(fromUser: m.$1, text: m.$2),
              if (_live.isNotEmpty) _Bubble(fromUser: false, text: _live),
            ],
          ),
        ),
        if (_tokens != null)
          Text(
            'conversation: ~$_tokens tokens',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _busy
                  ? IconButton.filledTonal(
                      onPressed: () => _session?.stopGeneration(),
                      icon: const Icon(Icons.stop),
                    )
                  : IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: fromUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(text),
      ),
    );
  }
}

class ExtractTab extends StatefulWidget {
  const ExtractTab({super.key, required this.ai});
  final FlutterDeviceAi ai;

  @override
  State<ExtractTab> createState() => _ExtractTabState();
}

class _ExtractTabState extends State<ExtractTab> {
  final _input = TextEditingController(
    text:
        'Elena Rostova is a principal engineer with 9 years in ML. '
        'She specialises in compilers and distributed systems.',
  );
  String _out = '';
  bool _busy = false;

  static const _schema = {
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
      'role': {'type': 'string'},
      'yearsExperience': {'type': 'integer', 'minimum': 0},
      'specialties': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['name', 'role', 'specialties'],
  };

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _out = '';
    });
    try {
      final res = await widget.ai.generateText(
        prompt: 'Extract the person described here:\n${_input.text}',
        config: const GenerationConfig(
          responseFormat: ResponseFormat.json,
          schema: _schema,
        ),
      );
      setState(() => _out = 'Parsed: ${res.json}');
    } on OnDeviceAiException catch (e) {
      setState(() => _out = '${e.runtimeType}: ${e.message}');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _input,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _run,
          child: const Text('Extract as JSON'),
        ),
        const SizedBox(height: 12),
        SelectableText(_out),
      ],
    );
  }
}

class ToolsTab extends StatefulWidget {
  const ToolsTab({super.key, required this.ai});
  final FlutterDeviceAi ai;

  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<ToolsTab> {
  double _temperature = 20;
  final _log = <String>[];
  bool _busy = false;
  final _input = TextEditingController(
    text: 'It feels chilly, set the thermostat to 23 degrees.',
  );

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _log.clear();
    });
    final session = await widget.ai.createSession(
      systemInstruction: 'You control a smart home. Use tools to act.',
      tools: [
        OnDeviceAiTool(
          name: 'setThermostat',
          description:
              'Sets the thermostat to a target temperature in Celsius.',
          parameters: const [
            ToolParameter(
              name: 'celsius',
              type: ToolArgumentType.number,
              description: 'Target temperature in Celsius',
            ),
          ],
          onCall: (args) {
            final c = (args['celsius'] as num).toDouble();
            setState(() {
              _temperature = c;
              _log.add('tool setThermostat(celsius: $c)');
            });
            return {'ok': true, 'celsius': c};
          },
        ),
      ],
    );
    try {
      final res = await session.ask(_input.text);
      setState(() => _log.add('model: ${res.text}'));
    } on OnDeviceAiException catch (e) {
      setState(() => _log.add('${e.runtimeType}: ${e.message}'));
    } finally {
      await session.close();
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Thermostat: ${_temperature.toStringAsFixed(1)} °C',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _run, child: const Text('Ask')),
        const SizedBox(height: 12),
        for (final l in _log) SelectableText(l),
      ],
    );
  }
}

class ScreenTab extends StatefulWidget {
  const ScreenTab({super.key, required this.ai});
  final FlutterDeviceAi ai;

  @override
  State<ScreenTab> createState() => _ScreenTabState();
}

class _ScreenTabState extends State<ScreenTab> {
  final _goal = TextEditingController(
    text: 'A one week plan to prepare for a 10K run',
  );
  GenUiModuleSpec? _module;
  String? _error;
  bool _busy = false;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _module = null;
      _error = null;
    });
    final generator = OnDeviceUiGenerator(widget.ai);
    final module = await generator.generateModule(_goal.text);
    setState(() {
      _module = module;
      _error = generator.lastError;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _module;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _goal,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _run,
          child: const Text('Generate screen'),
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (m != null) ...[
          Text(m.title, style: Theme.of(context).textTheme.headlineSmall),
          if (m.blurb.isNotEmpty) Text(m.blurb),
          const SizedBox(height: 8),
          for (final b in m.blocks) BlockView(block: b),
        ],
      ],
    );
  }
}

/// Minimal renderer for the typed blocks - replace with your own design system.
class BlockView extends StatelessWidget {
  const BlockView({super.key, required this.block});
  final Map<String, dynamic> block;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget card(Widget child) => Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
    switch (block['type']) {
      case 'stat':
        return card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${block['label']}', style: t.labelMedium),
              Text('${block['value']}', style: t.headlineMedium),
              if (block['subtext'] != null)
                Text('${block['subtext']}', style: t.bodySmall),
            ],
          ),
        );
      case 'progress':
        final current = (block['current'] as num).toDouble();
        final target = (block['target'] as num).toDouble();
        return card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${block['label']}  $current / $target ${block['unit'] ?? ''}',
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: (current / target).clamp(0, 1)),
            ],
          ),
        );
      case 'checklist':
        return card(
          Column(
            children: [
              for (final i in block['items'] as List)
                CheckboxListTile(
                  dense: true,
                  value: i['completed'] == true,
                  onChanged: (_) {},
                  title: Text('${i['title']}'),
                ),
            ],
          ),
        );
      case 'list':
        return card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block['title'] != null)
                Text('${block['title']}', style: t.titleSmall),
              for (final i in block['items'] as List) Text('• $i'),
            ],
          ),
        );
      case 'steps':
        return card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (n, i) in (block['items'] as List).indexed)
                Text(
                  '${n + 1}. ${i['title']}${(i['detail'] as String).isEmpty ? '' : ' - ${i['detail']}'}',
                ),
            ],
          ),
        );
      case 'table':
        return card(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (final c in block['columns'] as List)
                  DataColumn(label: Text('$c')),
              ],
              rows: [
                for (final r in block['rows'] as List)
                  DataRow(
                    cells: [
                      for (final cell in r as List) DataCell(Text('$cell')),
                    ],
                  ),
              ],
            ),
          ),
        );
      default:
        return card(Text('${block['content']}'));
    }
  }
}

/// Chooses the local fallback model: a preset or any GGUF source (`hf://`,
/// `https://` or a file path).
class _ModelPicker extends StatefulWidget {
  const _ModelPicker({
    required this.model,
    required this.onChanged,
    required this.enabled,
  });

  final String model;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  static const _custom = 'custom';
  final _controller = TextEditingController();
  bool _customSelected = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preset = _models.any((m) => m.$2 == widget.model);
    final value = _customSelected || !preset ? _custom : widget.model;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          value: value,
          isExpanded: true,
          onChanged: widget.enabled
              ? (v) {
                  if (v == null) return;
                  setState(() => _customSelected = v == _custom);
                  if (v != _custom) widget.onChanged(v);
                }
              : null,
          items: [
            for (final (label, source) in _models)
              DropdownMenuItem(value: source, child: Text(label)),
            const DropdownMenuItem(
              value: _custom,
              child: Text('Custom GGUF (URL, hf:// or file path)'),
            ),
          ],
        ),
        if (value == _custom)
          TextField(
            controller: _controller,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              hintText: 'hf://owner/repo/model-Q4_K_M.gguf',
              isDense: true,
            ),
            onSubmitted: widget.onChanged,
          ),
      ],
    );
  }
}

/// Retrieval-augmented answers over the user's own notes, all on device.
class DocsTab extends StatefulWidget {
  const DocsTab({super.key, required this.ai, required this.embedder});
  final FlutterDeviceAi ai;
  final OnDeviceAiEmbedder embedder;

  @override
  State<DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<DocsTab> {
  final _notes = TextEditingController(
    text:
        'Router reset: hold the small button on the back for 10 seconds '
        'until the light blinks white.\n\n'
        'Wi-Fi password: it is printed on the sticker under the router.\n\n'
        'Warranty: hardware faults are covered for 24 months from purchase.',
  );
  final _question = TextEditingController(text: 'How do I reset the router?');
  late final _index = RagIndex(embedder: widget.embedder);
  List<RagHit> _hits = const [];
  String _answer = '';
  String _indexed = '';
  double? _progress;
  bool _busy = false;

  Future<void> _ask() async {
    setState(() {
      _busy = true;
      _answer = '';
      _hits = const [];
    });
    try {
      if (!await widget.embedder.isReady()) {
        await widget.embedder.prepare(
          onProgress: (p) => setState(() => _progress = p),
        );
        _progress = null;
      }
      // Re-embed only when the notes changed.
      if (_indexed != _notes.text) {
        final paragraphs = _notes.text
            .split(RegExp(r'\n\s*\n'))
            .where((p) => p.trim().isNotEmpty)
            .toList();
        final old = {
          for (final r in _index.store.records) r.metadata['documentId'],
        };
        for (final id in old) {
          _index.removeDocument(id as String);
        }
        for (var i = 0; i < paragraphs.length; i++) {
          await _index.addDocument('note ${i + 1}', paragraphs[i]);
        }
        _indexed = _notes.text;
      }
      final hits = await _index.search(_question.text, k: 2, minScore: 0.2);
      setState(() => _hits = hits);
      if (hits.isEmpty) {
        setState(() => _answer = 'No note matches that question.');
        return;
      }
      final context = await _index.contextFor(
        _question.text,
        k: 2,
        minScore: 0.2,
      );
      final res = await widget.ai.generateText(
        prompt:
            'Answer using only these passages:\n$context\n\n'
            'Question: ${_question.text}',
      );
      setState(() => _answer = res.text);
    } on OnDeviceAiException catch (e) {
      setState(() => _answer = '${e.runtimeType}: ${e.message}');
    } finally {
      setState(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _notes,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Your notes (blank line between notes)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _question,
          decoration: const InputDecoration(
            labelText: 'Question',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _ask,
          child: const Text('Search and answer'),
        ),
        if (_progress != null) ...[
          const SizedBox(height: 8),
          Text('Downloading embedding model', style: text.bodySmall),
          LinearProgressIndicator(value: _progress),
        ],
        if (_hits.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Best matches', style: text.titleSmall),
          for (final h in _hits)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(h.text),
              subtitle: Text(
                '${h.documentId} · ${(h.score * 100).round()}% match',
              ),
            ),
        ],
        if (_answer.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Answer', style: text.titleSmall),
          SelectableText(_answer),
        ],
      ],
    );
  }
}
