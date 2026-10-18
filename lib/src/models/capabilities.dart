/// The detected native on-device AI backend.
enum OnDeviceAiBackend {
  /// Apple Foundation Models (iOS 26+, macOS 26+).
  appleFoundationModels,

  /// Google ML Kit GenAI Prompt API / Gemini Nano on Android.
  androidMlKitGenAi,

  /// Microsoft Windows AI Foundry (WinRT).
  windowsAiFoundry,

  /// Chromium Prompt API (`LanguageModel`).
  chromePromptApi,

  /// A pluggable [OnDeviceAiFallbackAdapter] (e.g. a flutter_edge_ai runner).
  fallbackEdgeAi,

  /// No usable backend on this platform.
  unsupported,
}

/// How a feature is delivered on the active backend.
enum CapabilitySupport {
  /// Provided by the OS / browser itself.
  native,

  /// Provided by this package on top of plain text generation.
  emulated,

  /// Not available.
  unsupported;

  /// Whether the feature can be used at all.
  bool get isAvailable => this != CapabilitySupport.unsupported;
}

/// What the *native* backend can do, as reported by the platform layer.
class OnDeviceAiPlatformInfo {
  /// The active inference backend.
  final OnDeviceAiBackend backend;

  /// Whether the OS model calls Dart tools natively.
  final bool supportsToolCalling;

  /// Whether the OS model natively enforces a JSON Schema.
  final bool supportsStructuredOutput;

  /// Whether image input is supported.
  final bool supportsVision;

  /// Whether the OS can download / prepare the model on request.
  final bool supportsModelDownload;

  /// Whether the platform can open the Play Store page of Google AICore.
  final bool supportsPlayStoreRedirect;

  /// Whether token counts reported by the platform are exact.
  final bool supportsExactTokenCounts;

  /// Whether the native backend is compiled in and configured.
  final bool isConfigured;

  /// Free-form notes (OS version, AICore presence, ...).
  final String? diagnosticNotes;

  const OnDeviceAiPlatformInfo({
    required this.backend,
    this.supportsToolCalling = false,
    this.supportsStructuredOutput = false,
    this.supportsVision = false,
    this.supportsModelDownload = false,
    this.supportsPlayStoreRedirect = false,
    this.supportsExactTokenCounts = false,
    this.isConfigured = true,
    this.diagnosticNotes,
  });

  factory OnDeviceAiPlatformInfo.fromMap(Map<String, dynamic> map) {
    final backendStr = map['backend'] as String? ?? 'unsupported';
    return OnDeviceAiPlatformInfo(
      backend: OnDeviceAiBackend.values.firstWhere(
        (b) => b.name == backendStr,
        orElse: () => OnDeviceAiBackend.unsupported,
      ),
      supportsToolCalling: map['supportsToolCalling'] as bool? ?? false,
      supportsStructuredOutput:
          map['supportsStructuredOutput'] as bool? ?? false,
      supportsVision: map['supportsVision'] as bool? ?? false,
      supportsModelDownload: map['supportsModelDownload'] as bool? ?? false,
      supportsPlayStoreRedirect:
          map['supportsPlayStoreRedirect'] as bool? ?? false,
      supportsExactTokenCounts:
          map['supportsExactTokenCounts'] as bool? ?? false,
      isConfigured: map['isConfigured'] as bool? ?? true,
      diagnosticNotes: map['diagnosticNotes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'backend': backend.name,
    'supportsToolCalling': supportsToolCalling,
    'supportsStructuredOutput': supportsStructuredOutput,
    'supportsVision': supportsVision,
    'supportsModelDownload': supportsModelDownload,
    'supportsPlayStoreRedirect': supportsPlayStoreRedirect,
    'supportsExactTokenCounts': supportsExactTokenCounts,
    'isConfigured': isConfigured,
    if (diagnosticNotes != null) 'diagnosticNotes': diagnosticNotes,
  };

  @override
  String toString() =>
      'OnDeviceAiPlatformInfo(backend: ${backend.name}, tools: $supportsToolCalling, '
      'schema: $supportsStructuredOutput, vision: $supportsVision)';
}

/// What the app can rely on *right now*, after fallback routing and the
/// package's own emulation layers are taken into account.
///
/// Check this instead of checking the platform name.
class OnDeviceAiCapabilities {
  /// The backend that will serve requests.
  final OnDeviceAiBackend backend;

  /// Token-by-token streaming.
  final bool streaming;

  /// Calling Dart [OnDeviceAiTool]s.
  final CapabilitySupport toolCalling;

  /// JSON-Schema constrained answers.
  final CapabilitySupport structuredOutput;

  /// Image input in sessions.
  final bool imageInput;

  /// Whether `countTokens` is exact (otherwise a ~4 chars/token estimate).
  final bool exactTokenCounts;

  /// Whether the model can be downloaded on request.
  final bool modelDownload;

  const OnDeviceAiCapabilities({
    required this.backend,
    this.streaming = true,
    this.toolCalling = CapabilitySupport.unsupported,
    this.structuredOutput = CapabilitySupport.unsupported,
    this.imageInput = false,
    this.exactTokenCounts = false,
    this.modelDownload = false,
  });

  @override
  String toString() =>
      'OnDeviceAiCapabilities(${backend.name}, tools: ${toolCalling.name}, '
      'structured: ${structuredOutput.name}, images: $imageInput, '
      'exactTokens: $exactTokenCounts)';
}
