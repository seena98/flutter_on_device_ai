/// Response format options for AI generation.
enum ResponseFormat {
  /// Standard free-form natural language text.
  text,

  /// Structured JSON output constrained by a JSON Schema.
  json,
}

/// Configuration options for generative text inference.
class GenerationConfig {
  /// The maximum number of tokens to generate.
  final int maxTokens;

  /// Controls randomness (0.0 = deterministic/greedy, 1.0 = highly creative).
  final double? temperature;

  /// Nucleus sampling probability threshold (0.0 to 1.0).
  final double? topP;

  /// Top-K sampling cutoff.
  final int? topK;

  /// Format of the generated output (text or schema-enforced JSON).
  final ResponseFormat responseFormat;

  /// JSON Schema definition to constrain the output when [responseFormat] is [ResponseFormat.json].
  final Map<String, dynamic>? schema;

  /// How often the package re-asks the model when its JSON does not satisfy
  /// [schema] and the backend cannot enforce the schema itself.
  final int maxRepairAttempts;

  const GenerationConfig({
    this.maxTokens = 256,
    this.temperature,
    this.topP,
    this.topK,
    this.responseFormat = ResponseFormat.text,
    this.schema,
    this.maxRepairAttempts = 2,
  });

  /// Serializes the configuration to a map for platform channels.
  Map<String, dynamic> toMap() {
    return {
      'maxTokens': maxTokens,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'topP': topP,
      if (topK != null) 'topK': topK,
      'responseFormat': responseFormat.name,
      if (schema != null) 'schema': schema,
    };
  }

  /// Creates a configuration from a map.
  factory GenerationConfig.fromMap(Map<String, dynamic> map) {
    return GenerationConfig(
      maxTokens: map['maxTokens'] as int? ?? 256,
      temperature: (map['temperature'] as num?)?.toDouble(),
      topP: (map['topP'] as num?)?.toDouble(),
      topK: map['topK'] as int?,
      responseFormat: ResponseFormat.values.firstWhere(
        (e) => e.name == map['responseFormat'],
        orElse: () => ResponseFormat.text,
      ),
      schema: map['schema'] == null
          ? null
          : Map<String, dynamic>.from(map['schema'] as Map),
      maxRepairAttempts: map['maxRepairAttempts'] as int? ?? 2,
    );
  }

  /// Returns a copy with the given fields replaced.
  GenerationConfig copyWith({
    int? maxTokens,
    double? temperature,
    double? topP,
    int? topK,
    ResponseFormat? responseFormat,
    Map<String, dynamic>? schema,
    int? maxRepairAttempts,
  }) {
    return GenerationConfig(
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      responseFormat: responseFormat ?? this.responseFormat,
      schema: schema ?? this.schema,
      maxRepairAttempts: maxRepairAttempts ?? this.maxRepairAttempts,
    );
  }
}
