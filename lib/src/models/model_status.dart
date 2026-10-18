/// Readiness state of the on-device AI model assets.
enum ModelFeatureStatus {
  /// Installed and ready for inference.
  available,

  /// Supported, but the OS / browser must download it first.
  downloadable,

  /// Currently downloading.
  downloading,

  /// Cannot run on this device.
  unavailable,
}

/// Why a model is (not) available. Lets apps show targeted guidance.
enum AvailabilityReason {
  /// Everything is fine.
  ready,

  /// Hardware cannot run the model.
  deviceNotEligible,

  /// The OS version is too old.
  osTooOld,

  /// The user has the AI feature switched off (e.g. Apple Intelligence).
  featureDisabled,

  /// Google AICore (or an equivalent system component) is missing.
  systemComponentMissing,

  /// The model must be downloaded or is still being prepared.
  modelNotReady,

  /// The browser does not expose the Prompt API.
  browserUnsupported,

  /// This package has no native backend for the platform.
  platformUnsupported,

  /// Anything else; see [OnDeviceAiAvailability.message].
  unknown,
}

/// Detailed availability of the native model.
class OnDeviceAiAvailability {
  final ModelFeatureStatus status;
  final AvailabilityReason reason;

  /// Human readable explanation, safe to show in the UI.
  final String message;

  const OnDeviceAiAvailability({
    required this.status,
    required this.reason,
    required this.message,
  });

  /// Whether inference can start immediately.
  bool get isReady => status == ModelFeatureStatus.available;

  factory OnDeviceAiAvailability.fromMap(Map<String, dynamic> map) {
    return OnDeviceAiAvailability(
      status: ModelFeatureStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => ModelFeatureStatus.unavailable,
      ),
      reason: AvailabilityReason.values.firstWhere(
        (r) => r.name == map['reason'],
        orElse: () => AvailabilityReason.unknown,
      ),
      message: map['message'] as String? ?? 'Unknown availability state.',
    );
  }

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'reason': reason.name,
    'message': message,
  };

  @override
  String toString() =>
      'OnDeviceAiAvailability(${status.name}, ${reason.name}: $message)';
}

/// Progress update while an OS-managed model downloads.
class ModelDownloadStatus {
  final ModelFeatureStatus status;

  /// 0.0 – 1.0, or null when indeterminate.
  final double? progress;
  final int? bytesDownloaded;
  final int? totalBytes;
  final String? errorMessage;

  const ModelDownloadStatus({
    required this.status,
    this.progress,
    this.bytesDownloaded,
    this.totalBytes,
    this.errorMessage,
  });

  factory ModelDownloadStatus.fromMap(Map<String, dynamic> map) {
    return ModelDownloadStatus(
      status: ModelFeatureStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => ModelFeatureStatus.unavailable,
      ),
      progress: (map['progress'] as num?)?.toDouble(),
      bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt(),
      totalBytes: (map['totalBytes'] as num?)?.toInt(),
      errorMessage: map['errorMessage'] as String?,
    );
  }

  @override
  String toString() =>
      'ModelDownloadStatus(${status.name}, '
      '${progress == null ? "?" : "${(progress! * 100).toStringAsFixed(1)}%"}'
      '${errorMessage != null ? ", error: $errorMessage" : ""})';
}
