import 'dart:collection';
import 'dart:convert';

/// Source and version metadata for a tutor tool result.
final class TutorToolProvenance {
  const TutorToolProvenance({
    required this.source,
    required this.schemaVersion,
  });

  final String source;
  final String schemaVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'schemaVersion': schemaVersion,
  };

  @override
  bool operator ==(Object other) =>
      other is TutorToolProvenance &&
      other.source == source &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(source, schemaVersion);
}

/// Data emitted by a tutor tool.
final class TutorToolPayload {
  TutorToolPayload(Map<String, Object?> values) : values = _freezeMap(values);

  final Map<String, Object?> values;

  int get serializedSizeBytes => utf8.encode(jsonEncode(values)).length;
}

/// Serialized-size data for a tool output.
final class TutorToolSizeReport {
  const TutorToolSizeReport({
    required this.maxOutputBytes,
    required this.actualBytes,
  });

  final int maxOutputBytes;
  final int actualBytes;

  bool get isOversized => actualBytes > maxOutputBytes;

  int get excessBytes => isOversized ? actualBytes - maxOutputBytes : 0;
}

/// State of one tool execution.
enum TutorToolExecutionState { completed, timedOut }

/// Result of one tutor tool execution.
final class TutorToolResult {
  const TutorToolResult._({
    required this.payload,
    required this.provenance,
    required this.timestamp,
    required this.sizeReport,
    required this.state,
  });

  factory TutorToolResult.completed({
    required TutorToolPayload payload,
    required TutorToolProvenance provenance,
    required DateTime timestamp,
    required int maxOutputBytes,
  }) {
    if (maxOutputBytes < 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    return TutorToolResult._(
      payload: payload,
      provenance: provenance,
      timestamp: timestamp.toUtc(),
      sizeReport: TutorToolSizeReport(
        maxOutputBytes: maxOutputBytes,
        actualBytes: payload.serializedSizeBytes,
      ),
      state: TutorToolExecutionState.completed,
    );
  }

  factory TutorToolResult.timedOut({
    required TutorToolProvenance provenance,
    required DateTime timestamp,
    required int maxOutputBytes,
  }) => TutorToolResult._(
    payload: TutorToolPayload(const <String, Object?>{}),
    provenance: provenance,
    timestamp: timestamp.toUtc(),
    sizeReport: TutorToolSizeReport(
      maxOutputBytes: maxOutputBytes,
      actualBytes: 0,
    ),
    state: TutorToolExecutionState.timedOut,
  );

  final TutorToolPayload payload;
  final TutorToolProvenance provenance;
  final DateTime timestamp;
  final TutorToolSizeReport sizeReport;
  final TutorToolExecutionState state;
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
