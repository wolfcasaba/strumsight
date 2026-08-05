import 'dart:collection';

import 'tutor_tool_result.dart';

/// Permissions for tutor tools.
enum TutorToolPermission { readLocal, computeLocal }

/// Primitive types for tool schema fields.
enum TutorToolSchemaValueType {
  string,
  integer,
  number,
  boolean,
  object,
  array,
}

/// A named input accepted by a tool schema.
final class TutorToolSchemaField {
  const TutorToolSchemaField({
    required this.name,
    required this.type,
    this.isRequired = false,
  });

  final String name;
  final TutorToolSchemaValueType type;
  final bool isRequired;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.name,
    if (isRequired) 'required': true,
  };
}

/// A tool input schema.
final class TutorToolSchema {
  TutorToolSchema({
    required this.toolName,
    required Iterable<TutorToolSchemaField> fields,
    this.additionalProperties = false,
  }) : fields = List<TutorToolSchemaField>.unmodifiable(fields) {
    if (toolName.trim().isEmpty) {
      throw ArgumentError.value(toolName, 'toolName');
    }
    final names = <String>{};
    for (final field in this.fields) {
      if (field.name.trim().isEmpty || !names.add(field.name)) {
        throw ArgumentError.value(fields, 'fields');
      }
    }
  }

  final String toolName;
  final List<TutorToolSchemaField> fields;
  final bool additionalProperties;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': toolName,
    'input': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        for (final field in fields) field.name: field.toJson(),
      },
      'required': <String>[
        for (final field in fields)
          if (field.isRequired) field.name,
      ],
      'additionalProperties': additionalProperties,
    },
  };
}

/// Input passed into one tutor tool call.
final class TutorToolInput {
  TutorToolInput(Map<String, Object?> values) : values = _freezeMap(values);

  final Map<String, Object?> values;
}

/// Signals invalid tool input.
final class TutorToolInputException implements Exception {
  const TutorToolInputException();
}

/// Typed contract for an individual tutor tool.
abstract interface class TutorTool {
  String get name;

  TutorToolPermission get permission;

  TutorToolSchema get inputSchema;

  TutorToolProvenance get provenance;

  Future<TutorToolPayload> execute(TutorToolInput input);
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) {
  final copied = <String, Object?>{};
  for (final entry in source.entries) {
    copied[entry.key] = _freezeValue(entry.value);
  }
  return UnmodifiableMapView<String, Object?>(copied);
}

Object? _freezeValue(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(<Object?>[
      for (final item in value) _freezeValue(item),
    ]);
  }
  if (value is Map<String, Object?>) {
    return _freezeMap(value);
  }
  throw ArgumentError.value(value, 'values');
}
