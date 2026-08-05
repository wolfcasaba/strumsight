import 'dart:convert';

import 'package:meta/meta.dart';

import 'context_purpose.dart';
import 'redaction_report.dart';

/// Stable names for the independently redacted tutor context sections.
enum TutorContextFieldKey {
  studentProfile,
  guitarProfile,
  activeGoals,
  skillEvidence,
  practice,
  songTrainer,
  analyze,
  progress,
  streak,
  settings,
}

/// Feature that produced a context field.
enum ContextSourceFeature {
  aiTutor,
  practice,
  songTrainer,
  analyze,
  progress,
  streak,
  settings,
}

/// Whether a source could provide a safe, public-contract context section.
enum ContextFieldAvailability { available, unavailable }

/// Origin and version tag attached to every context field.
@immutable
final class ContextProvenance {
  ContextProvenance({
    required this.sourceFeature,
    required this.schemaVersion,
    this.scorerVersion,
  }) {
    if (schemaVersion != null && schemaVersion!.trim().isEmpty) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
    if (scorerVersion != null && scorerVersion!.trim().isEmpty) {
      throw ArgumentError.value(scorerVersion, 'scorerVersion');
    }
  }

  final ContextSourceFeature sourceFeature;
  final String? schemaVersion;
  final String? scorerVersion;

  bool get hasVersion => schemaVersion != null || scorerVersion != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceFeature': sourceFeature.name,
    if (schemaVersion != null) 'schemaVersion': schemaVersion,
    if (scorerVersion != null) 'scorerVersion': scorerVersion,
  };
}

/// Immutable, structured data from one source feature.
@immutable
final class TutorContextField {
  TutorContextField.available({
    required this.key,
    required Map<String, Object?> values,
    required this.provenance,
  }) : availability = ContextFieldAvailability.available,
       values = _freezeMap(values) {
    if (!provenance.hasVersion) {
      throw ArgumentError.value(
        provenance,
        'provenance',
        'Available context fields require a scorer or schema version.',
      );
    }
  }

  const TutorContextField.unavailable({
    required this.key,
    required this.provenance,
  }) : availability = ContextFieldAvailability.unavailable,
       values = const <String, Object?>{};

  final TutorContextFieldKey key;
  final ContextFieldAvailability availability;
  final Map<String, Object?> values;
  final ContextProvenance provenance;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key.name,
    'availability': availability.name,
    'provenance': provenance.toJson(),
    if (availability == ContextFieldAvailability.available) 'values': values,
  };
}

/// Immutable, request-scoped and inspectable tutor input without a prompt.
@immutable
final class TutorContextSnapshot {
  // Defensive collection copies and UTC normalization require runtime work.
  // ignore: prefer_const_constructors_in_immutables
  TutorContextSnapshot({
    required this.requestId,
    required DateTime createdAt,
    required this.purpose,
    required Iterable<TutorContextField> fields,
    required this.redactionReport,
    Iterable<TutorContextFieldKey> truncatedFields =
        const <TutorContextFieldKey>[],
  }) : createdAt = createdAt.toUtc(),
       fields = List<TutorContextField>.unmodifiable(fields),
       truncatedFields = List<TutorContextFieldKey>.unmodifiable(
         truncatedFields,
       ) {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId');
    }
  }

  final String requestId;
  final DateTime createdAt;
  final ContextPurpose purpose;
  final List<TutorContextField> fields;
  final RedactionReport redactionReport;
  final List<TutorContextFieldKey> truncatedFields;

  /// UTF-8 size of the stable serialized representation, excluding this value.
  int get estimatedSizeBytes => utf8.encode(canonicalJson).length;

  /// Canonical JSON used by budget selection and deterministic test evidence.
  String get canonicalJson => jsonEncode(_canonicalMap(_estimatedPayload));

  TutorContextSnapshot withBudgetResult({
    required Iterable<TutorContextField> fields,
    required RedactionReport redactionReport,
    required Iterable<TutorContextFieldKey> truncatedFields,
  }) => TutorContextSnapshot(
    requestId: requestId,
    createdAt: createdAt,
    purpose: purpose,
    fields: fields,
    redactionReport: redactionReport,
    truncatedFields: truncatedFields,
  );

  Map<String, Object?> get _estimatedPayload => <String, Object?>{
    'requestId': requestId,
    'createdAt': createdAt.toIso8601String(),
    'purpose': purpose.name,
    'fields': <Object?>[for (final field in fields) field.toJson()],
    'redactionReport': redactionReport.toJson(),
    'truncatedFields': <Object?>[
      for (final field in truncatedFields) field.name,
    ],
  };
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) {
  final copied = <String, Object?>{};
  for (final entry in source.entries) {
    copied[entry.key] = _freezeValue(entry.value);
  }
  return Map<String, Object?>.unmodifiable(copied);
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
  throw ArgumentError.value(
    value,
    'value',
    'Context values must be JSON-compatible primitives, lists, or maps.',
  );
}

Object? _canonicalValue(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is List<Object?>) {
    return <Object?>[for (final item in value) _canonicalValue(item)];
  }
  if (value is Map<String, Object?>) {
    return _canonicalMap(value);
  }
  throw ArgumentError.value(value, 'value');
}

Map<String, Object?> _canonicalMap(Map<String, Object?> value) {
  final keys = value.keys.toList()..sort();
  return <String, Object?>{
    for (final key in keys) key: _canonicalValue(value[key]),
  };
}
