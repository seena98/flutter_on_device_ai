/// Base class for every error raised by `flutter_device_ai`.
class OnDeviceAiException implements Exception {
  /// Human readable description of what went wrong.
  final String message;

  /// Stable machine readable code, e.g. `UNAVAILABLE` or `SESSION_BUSY`.
  final String code;

  const OnDeviceAiException(this.message, {this.code = 'UNKNOWN'});

  @override
  String toString() => '$runtimeType($code): $message';
}

/// No usable model exists on this device (and no fallback is configured).
class OnDeviceAiUnavailableException extends OnDeviceAiException {
  const OnDeviceAiUnavailableException(super.message)
    : super(code: 'UNAVAILABLE');
}

/// The requested feature is not offered by the active backend.
class OnDeviceAiUnsupportedException extends OnDeviceAiException {
  const OnDeviceAiUnsupportedException(super.message)
    : super(code: 'UNSUPPORTED');
}

/// A browser refused the call because it was not made from a user gesture.
///
/// Chrome only starts downloading its built-in model in response to a click,
/// tap or key press. Call `ensureReady()` from such an event handler.
class OnDeviceAiUserActivationRequiredException extends OnDeviceAiException {
  const OnDeviceAiUserActivationRequiredException(super.message)
    : super(code: 'USER_ACTIVATION_REQUIRED');
}

/// A session was asked to do something while it was still generating.
class OnDeviceAiSessionBusyException extends OnDeviceAiException {
  const OnDeviceAiSessionBusyException(super.message)
    : super(code: 'SESSION_BUSY');
}

/// Generation was cancelled by `stopGeneration()` or by cancelling a stream.
class OnDeviceAiCancelledException extends OnDeviceAiException {
  const OnDeviceAiCancelledException([super.message = 'Generation cancelled.'])
    : super(code: 'CANCELLED');
}

/// The model did not produce output matching the requested JSON Schema, even
/// after the automatic repair attempts.
class OnDeviceAiStructuredOutputException extends OnDeviceAiException {
  /// Validation problems found in the last attempt.
  final List<String> errors;

  /// The last raw text the model produced.
  final String rawText;

  const OnDeviceAiStructuredOutputException(
    super.message, {
    this.errors = const [],
    this.rawText = '',
  }) : super(code: 'STRUCTURED_OUTPUT_INVALID');
}

/// The supplied JSON Schema uses a construct this package cannot enforce.
class OnDeviceAiSchemaException extends OnDeviceAiException {
  const OnDeviceAiSchemaException(super.message)
    : super(code: 'INVALID_SCHEMA');
}

/// The native generation engine reported a failure.
class OnDeviceAiGenerationException extends OnDeviceAiException {
  const OnDeviceAiGenerationException(super.message)
    : super(code: 'GENERATION_FAILED');
}
