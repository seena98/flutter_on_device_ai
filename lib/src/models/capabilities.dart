/// The detected native on-device AI backend.
enum OnDeviceAiBackend {
  /// Apple Foundation Models (iOS 26+, macOS 26+).
  appleFoundationModels,

  /// Google ML Kit GenAI / Gemini Nano on Android.
  androidMlKitGenAi,

  /// Microsoft Windows AI Foundry (WinRT).
  windowsAiFoundry,

  /// Chromium Prompt API (`window.ai` / `self.LanguageModel`).
  chromePromptApi,

  /// Custom bring-your-own model / flutter_gemma fallback engine.
  fallbackGemma,

  /// Unsupported hardware or OS.
  unsupported,
}

/// Diagnostic platform details and hardware capabilities.
class OnDeviceAiPlatformInfo {
  /// The active inference backend.
  final OnDeviceAiBackend backend;

  /// Whether bidirectional tool calling to Dart handlers is natively supported.
  final bool supportsToolCalling;

  /// Whether structured JSON schema output is supported.
  final bool supportsStructuredOutput;

  /// Whether multimodal/image input is supported.
  final bool supportsVision;

  /// Whether requesting an OS-level model download is supported.
  final bool supportsModelDownload;

  /// Whether the platform can redirect to Google Play to install/update AICore (Android only).
  final bool supportsPlayStoreRedirect;

  /// Whether the native backend is properly compiled and configured.
  final bool isConfigured;

  /// Underlying OS and device hardware notes.
  final String? diagnosticNotes;

  const OnDeviceAiPlatformInfo({
    required this.backend,
    this.supportsToolCalling = false,
    this.supportsStructuredOutput = false,
    this.supportsVision = false,
    this.supportsModelDownload = false,
    this.supportsPlayStoreRedirect = false,
    this.isConfigured = true,
    this.diagnosticNotes,
  });

  /// Construct from platform channel map.
  factory OnDeviceAiPlatformInfo.fromMap(Map<String, dynamic> map) {
    final backendStr = map['backend'] as String? ?? 'unsupported';
    final backend = OnDeviceAiBackend.values.firstWhere(
      (b) => b.name == backendStr,
      orElse: () => OnDeviceAiBackend.unsupported,
    );

    return OnDeviceAiPlatformInfo(
      backend: backend,
      supportsToolCalling: map['supportsToolCalling'] as bool? ?? false,
      supportsStructuredOutput: map['supportsStructuredOutput'] as bool? ?? false,
      supportsVision: map['supportsVision'] as bool? ?? false,
      supportsModelDownload: map['supportsModelDownload'] as bool? ?? false,
      supportsPlayStoreRedirect: map['supportsPlayStoreRedirect'] as bool? ?? false,
      isConfigured: map['isConfigured'] as bool? ?? true,
      diagnosticNotes: map['diagnosticNotes'] as String?,
    );
  }

  /// Serialize to map.
  Map<String, dynamic> toMap() {
    return {
      'backend': backend.name,
      'supportsToolCalling': supportsToolCalling,
      'supportsStructuredOutput': supportsStructuredOutput,
      'supportsVision': supportsVision,
      'supportsModelDownload': supportsModelDownload,
      'supportsPlayStoreRedirect': supportsPlayStoreRedirect,
      'isConfigured': isConfigured,
      if (diagnosticNotes != null) 'diagnosticNotes': diagnosticNotes,
    };
  }

  @override
  String toString() => 'OnDeviceAiPlatformInfo(backend: ${backend.name}, tools: $supportsToolCalling, schema: $supportsStructuredOutput, vision: $supportsVision)';
}
