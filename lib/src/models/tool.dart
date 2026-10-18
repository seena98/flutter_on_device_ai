import 'dart:async';

/// Supported scalar argument types for tool parameters.
enum ToolArgumentType {
  string,
  integer,
  number,
  boolean,
}

/// Defines a single scalar parameter in a tool definition.
class ToolParameter {
  /// Parameter identifier passed to the tool.
  final String name;

  /// Data type of the argument.
  final ToolArgumentType type;

  /// Explains what this parameter represents to guide the LLM.
  final String description;

  /// Whether this parameter is optional. Defaults to false.
  final bool optional;

  const ToolParameter({
    required this.name,
    required this.type,
    required this.description,
    this.optional = false,
  });

  /// Serializes parameter declaration to map.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type.name,
      'description': description,
      'optional': optional,
    };
  }
}

/// Callback signature invoked when an on-device model requests a tool execution.
typedef ToolCallHandler = FutureOr<Map<String, dynamic>> Function(
  Map<String, dynamic> arguments,
);

/// A Dart-defined tool that the on-device AI model can invoke natively.
class OnDeviceAiTool {
  /// Unique identifier of the tool.
  final String name;

  /// High-level description explaining what the tool does and when to call it.
  final String description;

  /// Flat parameter list for scalar arguments.
  final List<ToolParameter>? parameters;

  /// Optional complex JSON Schema defining the input parameters.
  ///
  /// Specify either [parameters] or [parameterSchema], not both.
  final Map<String, dynamic>? parameterSchema;

  /// Handler function executed in Dart when the model calls this tool.
  final ToolCallHandler onCall;

  OnDeviceAiTool({
    required this.name,
    required this.description,
    this.parameters,
    this.parameterSchema,
    required this.onCall,
  }) {
    if (parameters != null && parameterSchema != null) {
      throw ArgumentError('Supply either parameters or parameterSchema, never both.');
    }
  }

  /// Returns the resolved JSON schema for this tool's arguments.
  Map<String, dynamic> get resolvedParameterSchema {
    if (parameterSchema != null) {
      return parameterSchema!;
    }

    final properties = <String, dynamic>{};
    final requiredProps = <String>[];

    if (parameters != null) {
      for (final param in parameters!) {
        String jsonType;
        switch (param.type) {
          case ToolArgumentType.string:
            jsonType = 'string';
            break;
          case ToolArgumentType.integer:
            jsonType = 'integer';
            break;
          case ToolArgumentType.number:
            jsonType = 'number';
            break;
          case ToolArgumentType.boolean:
            jsonType = 'boolean';
            break;
        }

        properties[param.name] = {
          'type': jsonType,
          'description': param.description,
        };

        if (!param.optional) {
          requiredProps.add(param.name);
        }
      }
    }

    return {
      'type': 'object',
      'properties': properties,
      if (requiredProps.isNotEmpty) 'required': requiredProps,
    };
  }

  /// Serializes declaration to map for native platform channel registration.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'parameterSchema': resolvedParameterSchema,
    };
  }
}

/// An exception thrown inside [ToolCallHandler] to report a readable error back to the model.
class OnDeviceAiToolException implements Exception {
  final String message;
  final Map<String, dynamic>? details;

  const OnDeviceAiToolException(this.message, {this.details});

  @override
  String toString() => 'OnDeviceAiToolException: $message';
}
