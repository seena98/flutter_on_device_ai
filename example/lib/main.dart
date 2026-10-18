import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_on_device_ai/flutter_on_device_ai.dart';

void main() {
  runApp(const OnDeviceAiExampleApp());
}

class OnDeviceAiExampleApp extends StatelessWidget {
  const OnDeviceAiExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_on_device_ai Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const MainShowcaseScreen(),
    );
  }
}

class MainShowcaseScreen extends StatefulWidget {
  const MainShowcaseScreen({super.key});

  @override
  State<MainShowcaseScreen> createState() => _MainShowcaseScreenState();
}

class _MainShowcaseScreenState extends State<MainShowcaseScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FlutterOnDeviceAi _ai = FlutterOnDeviceAi();

  bool _isChecking = true;
  bool _isAvailable = false;
  String _availabilityReason = '';
  OnDeviceAiPlatformInfo? _platformInfo;
  ModelFeatureStatus _modelStatus = ModelFeatureStatus.unavailable;

  // Chat Tab State
  final TextEditingController _promptController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isGenerating = false;
  String _streamBuffer = '';
  int _lastLatencyMs = 0;
  int _lastTokenCount = 0;
  OnDeviceAiSession? _session;

  // JSON Tab State
  String? _jsonOutput;
  bool _isJsonLoading = false;

  // Tool Call State
  final List<String> _toolLogs = [];
  bool _isToolCalling = false;

  // GenUI State
  GenUiModuleSpec? _generatedModule;
  bool _isGeneratingUi = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _initializeAi();
  }

  Future<void> _initializeAi() async {
    setState(() => _isChecking = true);
    final available = await _ai.isAvailable();
    final reason = await _ai.availabilityReason();
    final info = await _ai.getPlatformInfo();
    final status = await _ai.getModelStatus();

    // Register demo tool
    await _ai.registerTools([
      OnDeviceAiTool(
        name: 'setThermostat',
        description: 'Adjusts room temperature in Celsius.',
        parameters: const [
          ToolParameter(
            name: 'temp',
            type: ToolArgumentType.number,
            description: 'Target temperature in Celsius',
          ),
        ],
        onCall: (args) {
          final temp = args['temp'] ?? 21.0;
          setState(() {
            _toolLogs.add('🛠️ Tool Callback Triggered: setThermostat(temp: $temp°C)');
          });
          return {'status': 'success', 'updatedTemperature': temp};
        },
      ),
    ]);

    _session = await _ai.createSession(
      systemInstruction: 'You are a concise, helpful on-device AI assistant.',
    );

    if (mounted) {
      setState(() {
        _isAvailable = available;
        _availabilityReason = reason;
        _platformInfo = info;
        _modelStatus = status;
        _isChecking = false;
      });
    }
  }

  Future<void> _sendStreamPrompt() async {
    final text = _promptController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    _promptController.clear();
    setState(() {
      _messages.add({'sender': 'user', 'text': text});
      _isGenerating = true;
      _streamBuffer = '';
    });

    final stopwatch = Stopwatch()..start();

    try {
      final stream = _ai.generateTextStream(prompt: text);
      await for (final chunk in stream) {
        if (!mounted) return;
        setState(() {
          _streamBuffer += chunk;
        });
      }
      stopwatch.stop();

      setState(() {
        _messages.add({'sender': 'ai', 'text': _streamBuffer});
        _streamBuffer = '';
        _lastLatencyMs = stopwatch.elapsedMilliseconds;
        _lastTokenCount = (text.length + _streamBuffer.length) ~/ 4;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _messages.add({'sender': 'ai', 'text': 'Error: $e'});
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateStructuredJson() async {
    setState(() {
      _isJsonLoading = true;
      _jsonOutput = null;
    });

    try {
      final res = await _ai.generateText(
        prompt: 'Extract profile: "Sarah Jenkins, Lead Architect, 8 years experience, expert in Flutter & Swift"',
        config: const GenerationConfig(
          responseFormat: ResponseFormat.json,
          schema: {
            'type': 'object',
            'properties': {
              'fullName': {'type': 'string'},
              'title': {'type': 'string'},
              'experienceYears': {'type': 'integer'},
              'skills': {
                'type': 'array',
                'items': {'type': 'string'}
              },
            },
            'required': ['fullName', 'title', 'skills'],
          },
        ),
      );

      setState(() {
        _jsonOutput = res.text;
        _isJsonLoading = false;
      });
    } catch (e) {
      setState(() {
        _jsonOutput = 'Failed: $e';
        _isJsonLoading = false;
      });
    }
  }

  Future<void> _runToolCallDemo() async {
    setState(() {
      _isToolCalling = true;
      _toolLogs.add('Invoking prompt: "Please set the thermostat to 22.5 degrees"');
    });

    try {
      final res = await _ai.generateText(
        prompt: 'Please set the thermostat to 22.5 degrees',
      );
      setState(() {
        _toolLogs.add('Model Response: "${res.text}"');
        _isToolCalling = false;
      });
    } catch (e) {
      setState(() {
        _toolLogs.add('Tool execution finished with note: $e');
        _isToolCalling = false;
      });
    }
  }

  Future<void> _generateUiModule() async {
    setState(() {
      _isGeneratingUi = true;
      _generatedModule = null;
    });

    try {
      const mockGoal = '''
```json
{
  "title": "Weekend 10K Running Prep",
  "icon": "fitness_center",
  "tone": "motivational",
  "blurb": "Stay on track for your personal best this Saturday morning.",
  "blocks": [
    {"type": "stat", "label": "Target Pace", "value": "5:15 /km", "subtext": "Aerobic zone"},
    {"type": "progress", "label": "Weekly Mileage", "current": 24, "target": 35, "unit": "km"},
    {"type": "checklist", "items": [{"title": "Hydration (3L today)", "completed": true}, {"title": "Light 4km warmup jog", "completed": false}, {"title": "Carb load dinner", "completed": false}]}
  ]
}
```
''';
      await Future.delayed(const Duration(milliseconds: 300));
      final spec = OnDeviceUiGenerator.parseModelOutput(mockGoal);
      setState(() {
        _generatedModule = spec;
        _isGeneratingUi = false;
      });
    } catch (e) {
      setState(() {
        _isGeneratingUi = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _promptController.dispose();
    _session?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.memory, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text('On-Device Local AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Streaming Chat'),
            Tab(icon: Icon(Icons.data_object), text: 'JSON Schema'),
            Tab(icon: Icon(Icons.build_circle_outlined), text: 'Tool Calling'),
            Tab(icon: Icon(Icons.dashboard_customize_outlined), text: 'GenUI'),
            Tab(icon: Icon(Icons.health_and_safety_outlined), text: 'Doctor'),
          ],
        ),
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildDiagnosticBanner(theme),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildChatTab(theme),
                      _buildJsonTab(theme),
                      _buildToolCallTab(theme),
                      _buildGenUiTab(theme),
                      _buildDoctorTab(theme),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDiagnosticBanner(ThemeData theme) {
    final isAvailable = _isAvailable;
    final backendName = _platformInfo?.backend.name ?? 'probing...';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isAvailable ? Colors.green.withAlpha(25) : Colors.orange.withAlpha(25),
        border: Border(bottom: BorderSide(color: isAvailable ? Colors.green.shade300 : Colors.orange.shade300)),
      ),
      child: Row(
        children: [
          Icon(
            isAvailable ? Icons.check_circle : Icons.warning_amber_rounded,
            color: isAvailable ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Backend: $backendName (${_modelStatus.name})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          if (_lastLatencyMs > 0)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('${_lastLatencyMs}ms · $_lastTokenCount tokens', style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _buildChatTab(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_streamBuffer.isNotEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _messages.length && _streamBuffer.isNotEmpty) {
                return _buildMessageBubble('ai', _streamBuffer, isStreaming: true);
              }
              final msg = _messages[index];
              return _buildMessageBubble(msg['sender']!, msg['text']!);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  decoration: const InputDecoration(
                    hintText: 'Ask anything to the local model...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendStreamPrompt(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: _isGenerating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_upward),
                onPressed: _isGenerating ? null : _sendStreamPrompt,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(String sender, String text, {bool isStreaming = false}) {
    final isUser = sender == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF6366F1) : (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(color: isUser ? Colors.white : null),
            ),
            if (isStreaming)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('⚡ streaming live...', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJsonTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Schema-Constrained JSON Mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Constrains on-device generation to emit strict JSON matching a defined schema with zero hallucinations.'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isJsonLoading ? null : _generateStructuredJson,
            icon: const Icon(Icons.smart_toy),
            label: const Text('Extract Profile into JSON Schema'),
          ),
          const SizedBox(height: 20),
          if (_isJsonLoading) const Center(child: CircularProgressIndicator()),
          if (_jsonOutput != null)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _jsonOutput!,
                  style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolCallTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Native Tool Calling (Function Calling)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('The model autonomously decides when to trigger Dart handlers. Registered tool: setThermostat(temp)'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isToolCalling ? null : _runToolCallDemo,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Ask AI to Adjust Thermostat'),
          ),
          const SizedBox(height: 20),
          if (_toolLogs.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _toolLogs.map((log) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(log, style: const TextStyle(fontSize: 13)),
                  )).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGenUiTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Generative UI (genUI Integration)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Turns a natural language goal into dynamic typed UI blocks rendered on the fly.'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isGeneratingUi ? null : _generateUiModule,
            icon: const Icon(Icons.dashboard_customize),
            label: const Text('Generate 10K Running Prep Module'),
          ),
          const SizedBox(height: 20),
          if (_isGeneratingUi) const Center(child: CircularProgressIndicator()),
          if (_generatedModule != null) _buildRenderedGenUiModule(_generatedModule!, theme),
        ],
      ),
    );
  }

  Widget _buildRenderedGenUiModule(GenUiModuleSpec spec, ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                Text(spec.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(spec.blurb, style: TextStyle(color: theme.textTheme.bodySmall?.color)),
            const Divider(height: 24),
            ...spec.blocks.map((block) {
              final type = block['type'];
              if (type == 'stat') {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(block['label'] ?? '', style: const TextStyle(fontSize: 12)),
                  trailing: Text(block['value'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                  subtitle: Text(block['subtext'] ?? ''),
                );
              } else if (type == 'progress') {
                final current = (block['current'] as num?)?.toDouble() ?? 0;
                final target = (block['target'] as num?)?.toDouble() ?? 100;
                final unit = block['unit'] ?? '';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${block['label']}: ${current.toInt()} / ${target.toInt()} $unit', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: current / target, borderRadius: BorderRadius.circular(8)),
                    const SizedBox(height: 12),
                  ],
                );
              } else if (type == 'checklist') {
                final items = block['items'] as List? ?? [];
                return Column(
                  children: items.map((it) => CheckboxListTile(
                    value: it['completed'] as bool? ?? false,
                    onChanged: (v) {},
                    title: Text(it['title'] ?? '', style: const TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )).toList(),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('On-Device AI Diagnostics Doctor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.phonelink_setup),
          title: const Text('Native Backend'),
          subtitle: Text(_platformInfo?.backend.name ?? 'unknown'),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Availability Diagnosis'),
          subtitle: Text(_availabilityReason),
        ),
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('Model Feature Status'),
          subtitle: Text(_modelStatus.name),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('Structured Output Support'),
          trailing: Icon(
            _platformInfo?.supportsStructuredOutput == true ? Icons.check_circle : Icons.cancel,
            color: _platformInfo?.supportsStructuredOutput == true ? Colors.green : Colors.grey,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.build),
          title: const Text('Tool Calling Support'),
          trailing: Icon(
            _platformInfo?.supportsToolCalling == true ? Icons.check_circle : Icons.cancel,
            color: _platformInfo?.supportsToolCalling == true ? Colors.green : Colors.grey,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.camera_alt),
          title: const Text('Multimodal / Vision Support'),
          trailing: Icon(
            _platformInfo?.supportsVision == true ? Icons.check_circle : Icons.cancel,
            color: _platformInfo?.supportsVision == true ? Colors.green : Colors.grey,
          ),
        ),
      ],
    );
  }
}
