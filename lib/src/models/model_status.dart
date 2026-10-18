/// Readiness state of the on-device AI model assets.
enum ModelFeatureStatus {
  /// The model is fully installed, loaded, and ready for inference.
  available,

  /// The model is supported on this device but must be downloaded by the OS.
  downloadable,

  /// Model assets are currently being downloaded in the background.
  downloading,

  /// The model cannot run on this device due to hardware or OS limitations.
  unavailable,
}

/// Download progress update when fetching on-device model weights.
class ModelDownloadStatus {
  /// Current status phase.
  final ModelFeatureStatus status;

  /// Progress fraction from 0.0 to 1.0 (or null if indeterminate).
  final double? progress;

  /// Total bytes downloaded so far, if known.
  final int? bytesDownloaded;

  /// Total bytes expected, if known.
  final int? totalBytes;

  /// Human-readable error message if download failed.
  final String? errorMessage;

  const ModelDownloadStatus({
    required this.status,
    this.progress,
    this.bytesDownloaded,
    this.totalBytes,
    this.errorMessage,
  });

  /// Factory from platform channel map.
  factory ModelDownloadStatus.fromMap(Map<String, dynamic> map) {
    final statusStr = map['status'] as String? ?? 'unavailable';
    final status = ModelFeatureStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => ModelFeatureStatus.unavailable,
    );

    return ModelDownloadStatus(
      status: status,
      progress: (map['progress'] as num?)?.toDouble(),
      bytesDownloaded: map['bytesDownloaded'] as int?,
      totalBytes: map['totalBytes'] as int?,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  @override
  String toString() => 'ModelDownloadStatus(status: ${status.name}, progress: ${(progress != null ? (progress! * 100).toStringAsFixed(1) : "?")}%${errorMessage != null ? ", error: $errorMessage" : ""})';
}
