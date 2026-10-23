import 'dart:async';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

import '../exceptions.dart';

/// A speech-recognition model offered to users.
class LocalSpeechPreset {
  const LocalSpeechPreset(this.label, this.source, this.projector, this.sizeMb);

  final String label;

  /// `hf://owner/repo/file.gguf`.
  final String source;

  /// Audio projector (mmproj) GGUF.
  final String projector;

  /// Combined download size in megabytes.
  final int sizeMb;
}

/// Offline speech-to-text: a Qwen3-ASR model run locally with llama.cpp
/// (through [llamadart](https://pub.dev/packages/llamadart)).
///
/// Input is mono 16 kHz audio; clips up to about 30 seconds work best.
///
/// ```dart
/// final stt = LocalSpeechToText();
/// await stt.prepare(onProgress: print);
/// final text = await stt.transcribeFile('/path/to/clip.wav');
/// ```
class LocalSpeechToText {
  LocalSpeechToText({
    this.model = defaultModel,
    this.projector = defaultProjector,
  });

  /// Qwen3-ASR 0.6B, Q8_0 (about 800 MB).
  static const defaultModel =
      'hf://unslothai/Qwen3-ASR-0.6B-GGUF/Qwen3-ASR-0.6B-Q8_0.gguf';

  /// Audio projector matching [defaultModel] (about 214 MB).
  static const defaultProjector =
      'hf://unslothai/Qwen3-ASR-0.6B-GGUF/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf';

  /// Models that work, smallest first.
  static const presets = <LocalSpeechPreset>[
    LocalSpeechPreset('Qwen3-ASR 0.6B', defaultModel, defaultProjector, 1020),
    LocalSpeechPreset(
      'Qwen3-ASR 1.7B',
      'hf://ggml-org/Qwen3-ASR-1.7B-GGUF/Qwen3-ASR-1.7B-Q8_0.gguf',
      'hf://ggml-org/Qwen3-ASR-1.7B-GGUF/mmproj-Qwen3-ASR-1.7B-Q8_0.gguf',
      2520,
    ),
  ];

  final String model;
  final String projector;

  SpeechToTextEngine? _engine;
  Future<void>? _loading;

  /// Whether the model is loaded.
  bool get isLoaded => _engine != null;

  /// Downloads (first run only) and loads the model.
  Future<void> prepare({void Function(double progress)? onProgress}) {
    if (_engine != null) {
      onProgress?.call(1.0);
      return Future.value();
    }
    return _loading ??= _load(onProgress).whenComplete(() => _loading = null);
  }

  Future<void> _load(void Function(double progress)? onProgress) async {
    try {
      _engine = await SpeechToTextEngine.load(
        SpeechToTextModel(
          ModelSource.parse(model),
          projector: ModelSource.parse(projector),
          adapter: const Qwen3AsrAdapter(),
        ),
        onProgress: (p) {
          final fraction = p.fraction;
          if (fraction != null) onProgress?.call(fraction);
        },
      );
      onProgress?.call(1.0);
    } on LlamaUnsupportedException catch (e) {
      throw OnDeviceAiUnsupportedException(
        'Speech recognition is not supported here: ${e.message}',
      );
    } catch (e) {
      throw OnDeviceAiUnavailableException(
        'Could not download or load the speech model: $e. Check the network '
        'connection and free disk space.',
      );
    }
  }

  Future<String> _transcribe(SpeechAudioInput audio, String? language) async {
    await prepare();
    final result = await _engine!.transcribeOnce(
      SpeechToTextRequest(audio: audio, languageHint: language),
    );
    return result.text.trim();
  }

  /// Transcribes an audio file on disk.
  Future<String> transcribeFile(String path, {String? language}) =>
      _transcribe(SpeechAudioFileInput(path), language);

  /// Transcribes encoded audio (WAV, MP3, ...) held in memory.
  Future<String> transcribeBytes(Uint8List bytes, {String? language}) =>
      _transcribe(SpeechAudioBytesInput(bytes), language);

  /// Releases the model.
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}
