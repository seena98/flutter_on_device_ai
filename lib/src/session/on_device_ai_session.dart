import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../exceptions.dart';
import '../models/ai_response.dart';
import '../models/generation_config.dart';
import '../models/tool.dart';
import '../schema/json_schema.dart';
import 'session_backend.dart';
import 'tool_emulation.dart';

/// A multi-turn conversation with an on-device model.
///
/// Create one with `FlutterDeviceAi.createSession`. Sessions are isolated:
/// you can keep several open at once. A session answers one turn at a time;
/// touching it while it generates throws [OnDeviceAiSessionBusyException].
///
/// ```dart
/// final session = await ai.createSession(systemInstruction: 'Be brief.');
/// final reply = await session.ask('Why is the sky blue?');
/// await session.close();
/// ```
class OnDeviceAiSession {
  /// Wraps a [SessionBackend]. Use `FlutterDeviceAi.createSession` instead.
  OnDeviceAiSession.fromBackend({
    required this.sessionId,
    required SessionBackend backend,
    this.systemInstruction,
    this.tools = const [],
    this.config,
    this.maxToolRounds = 5,
  }) : _backend = backend;

  /// Unique id of this session.
  final String sessionId;

  /// The instruction the model was primed with, if any.
  final String? systemInstruction;

  /// Tools the model may call.
  final List<OnDeviceAiTool> tools;

  /// Default generation settings for this session.
  final GenerationConfig? config;

  /// Upper bound of tool round-trips within one answer.
  final int maxToolRounds;

  final SessionBackend _backend;
  bool _closed = false;
  bool _busy = false;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Whether a response is being generated right now.
  bool get isGenerating => _busy;

  /// Whether images can be attached to this session.
  bool get supportsImages => _backend.supportsImages;

  bool get _emulateTools => tools.isNotEmpty && !_backend.nativeTools;

  /// Adds user text to the pending turn. Call repeatedly to build a turn from
  /// several parts, then request the answer.
  Future<void> addQuery(String text) async {
    _ensureUsable();
    await _backend.addQuery(text);
  }

  /// Adds an image to the pending turn (check [supportsImages]).
  Future<void> addImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    _ensureUsable();
    if (!_backend.supportsImages) {
      throw const OnDeviceAiUnsupportedException(
        'The active backend does not support image input.',
      );
    }
    await _backend.addImage(imageBytes, mimeType);
  }

  /// Answers the pending turn.
  Future<AiResponse> getResponse({GenerationConfig? config}) async {
    _ensureUsable();
    _busy = true;
    try {
      final cfg = config ?? this.config;
      if (_wantsSchema(cfg)) return await _structured(cfg!);
      return await _turn(cfg);
    } finally {
      _busy = false;
    }
  }

  /// Answers the pending turn as a stream of text deltas.
  ///
  /// With a JSON schema the validated answer arrives as a single chunk.
  Stream<String> getResponseAsync({GenerationConfig? config}) async* {
    _ensureUsable();
    _busy = true;
    try {
      final cfg = config ?? this.config;
      if (_wantsSchema(cfg)) {
        yield (await _structured(cfg!)).text;
      } else {
        yield* _streamTurn(cfg);
      }
    } finally {
      _busy = false;
    }
  }

  /// Convenience: [addQuery] followed by [getResponse].
  Future<AiResponse> ask(String text, {GenerationConfig? config}) async {
    await addQuery(text);
    return getResponse(config: config);
  }

  /// Convenience: [addQuery] followed by [getResponseAsync].
  Stream<String> askStream(String text, {GenerationConfig? config}) async* {
    await addQuery(text);
    yield* getResponseAsync(config: config);
  }

  /// Token count of the conversation, or of [text] alone.
  ///
  /// Exact when `OnDeviceAiCapabilities.exactTokenCounts` is true, otherwise a
  /// ~4 characters per token estimate.
  Future<int> countTokens({String? text}) async {
    _ensureOpen();
    return _backend.countTokens(text);
  }

  /// Cancels the generation in flight. The pending call fails with
  /// [OnDeviceAiCancelledException].
  Future<void> stopGeneration() async {
    _ensureOpen();
    await _backend.stop();
  }

  /// Releases the session. Safe to call more than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _backend.close();
  }

  // --- internals ------------------------------------------------------------

  bool _wantsSchema(GenerationConfig? c) =>
      c != null && c.responseFormat == ResponseFormat.json && c.schema != null;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('OnDeviceAiSession "$sessionId" is already closed.');
    }
  }

  void _ensureUsable() {
    _ensureOpen();
    if (_busy) {
      throw OnDeviceAiSessionBusyException(
        'Session "$sessionId" is still generating. '
        'Await the response or call stopGeneration() first.',
      );
    }
  }

  /// One answer, running the emulated tool loop when needed.
  Future<AiResponse> _turn(GenerationConfig? cfg) async {
    var response = await _backend.respond(cfg);
    if (!_emulateTools) return response;

    var elapsed = response.generationTimeMs ?? 0;
    for (var round = 0; round < maxToolRounds; round++) {
      final parsed = parseToolCall(response.text, tools);
      if (!parsed.isToolRequest) break;
      await _backend.addQuery(await _toolResultMessage(parsed));
      response = await _backend.respond(cfg);
      elapsed += response.generationTimeMs ?? 0;
    }
    return AiResponse(
      text: response.text,
      tokenCount: response.tokenCount,
      generationTimeMs: elapsed,
    );
  }

  Stream<String> _streamTurn(GenerationConfig? cfg) async* {
    if (!_emulateTools) {
      yield* _backend.respondStream(cfg);
      return;
    }
    for (var round = 0; round <= maxToolRounds; round++) {
      final buffer = StringBuffer();
      var decided = false;
      var passthrough = false;
      await for (final chunk in _backend.respondStream(cfg)) {
        if (passthrough) {
          yield chunk;
          continue;
        }
        buffer.write(chunk);
        if (decided) continue;
        final seen = buffer.toString().trimLeft();
        if (seen.isEmpty) continue;
        decided = true;
        // Only text that opens a JSON object / fence can be a tool call.
        passthrough = !seen.startsWith('{') && !seen.startsWith('`');
        if (passthrough) yield buffer.toString();
      }
      if (passthrough) return;
      final text = buffer.toString();
      final parsed = parseToolCall(text, tools);
      if (!parsed.isToolRequest || round == maxToolRounds) {
        yield text;
        return;
      }
      await _backend.addQuery(await _toolResultMessage(parsed));
    }
  }

  Future<String> _toolResultMessage(ToolCallParse parsed) async {
    if (parsed.call == null) {
      return 'Tool "${parsed.unknownName}" does not exist. '
          'Available tools: ${tools.map((t) => t.name).join(', ')}. '
          'Answer the user without it or call an existing tool.';
    }
    final result = await runTool(parsed.call!);
    return 'Result of tool "${parsed.call!.tool.name}": ${jsonEncode(result)}\n'
        'Now answer the user using this result.';
  }

  /// Schema-constrained answer with validate-and-repair.
  Future<AiResponse> _structured(GenerationConfig cfg) async {
    final schema = cfg.schema!;
    JsonSchema.ensureSupported(schema);

    if (!_backend.nativeStructuredOutput) {
      await _backend.addQuery(
        'Reply with ONLY a JSON value that satisfies this JSON Schema. '
        'No prose, no Markdown fences.\n${jsonEncode(schema)}',
      );
    }

    var problems = <String>[];
    var raw = '';
    var elapsed = 0;
    int? tokens;
    for (var attempt = 0; attempt <= cfg.maxRepairAttempts; attempt++) {
      final response = await _turn(cfg);
      raw = response.text;
      elapsed += response.generationTimeMs ?? 0;
      tokens = response.tokenCount;

      final value = JsonExtractor.extract(raw);
      problems = value == null
          ? ['The reply is not valid JSON.']
          : JsonSchema.validate(value, schema);
      if (problems.isEmpty) {
        return AiResponse(
          text: jsonEncode(value),
          tokenCount: tokens,
          generationTimeMs: elapsed,
        );
      }
      if (attempt < cfg.maxRepairAttempts) {
        await _backend.addQuery(
          'Your reply was rejected: ${problems.join(' ')} '
          'Reply again with ONLY the corrected JSON.',
        );
      }
    }
    throw OnDeviceAiStructuredOutputException(
      'The model could not produce JSON matching the schema after '
      '${cfg.maxRepairAttempts + 1} attempts.',
      errors: problems,
      rawText: raw,
    );
  }
}
