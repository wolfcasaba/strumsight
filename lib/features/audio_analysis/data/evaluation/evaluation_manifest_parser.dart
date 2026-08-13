/// Typed-failure parser for the Audio Analysis evaluation manifest schema
/// (`evaluation/analysis/manifest_schema.json`, E06-R29, ADR 0249).
///
/// Every rejection — a missing required annotation, an unrecognised field,
/// invalid chord-segment chronology, a duplicate case id, an unsupported
/// schema version, or any other malformed value — surfaces as a
/// [ManifestParseException]. The caller never sees a raw [TypeError] or
/// [ArgumentError] bubble out of `parse`.
library;

import 'dart:convert';

import '../../domain/evaluation/ground_truth.dart';

enum ManifestParseErrorKind {
  missingAnnotation,
  unknownField,
  invalidChronology,
  duplicateCaseId,
  invalidSchemaVersion,
  malformedValue,
}

final class ManifestParseException implements Exception {
  const ManifestParseException(this.kind, this.message, {this.path});

  final ManifestParseErrorKind kind;
  final String message;
  final String? path;

  @override
  String toString() =>
      'ManifestParseException(${kind.name})'
      '${path == null ? '' : ' at $path'}: $message';
}

const _rootKeys = <String>{'schemaVersion', 'cases'};
const _caseKeys = <String>{
  'id',
  'generation',
  'tempoBand',
  'signalQualityTier',
  'mode',
  'expected',
  'detected',
  'confidenceObservations',
};
const _annotationSetKeys = <String>{
  'events',
  'chordSegments',
  'tempoBpm',
  'beatsMs',
  'pitchPoints',
};
const _eventKeys = <String>{'id', 'timeMs', 'type', 'direction'};
const _chordSegmentKeys = <String>{'label', 'startMs', 'endMs'};
const _pitchPointKeys = <String>{'timeMs', 'hz'};
const _confidenceObservationKeys = <String>{'rawScore', 'correct'};

/// Parses a decoded (or raw JSON text) evaluation manifest into a
/// [GroundTruthManifest], rejecting anything that does not match
/// `manifest_schema.json` with a typed [ManifestParseException].
final class EvaluationManifestParser {
  const EvaluationManifestParser();

  GroundTruthManifest parseJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw ManifestParseException(
        ManifestParseErrorKind.malformedValue,
        'manifest is not valid JSON: ${error.message}',
      );
    }
    return parse(_asMap(decoded, 'manifest'));
  }

  GroundTruthManifest parse(Map<String, Object?> json) {
    _checkKeys(json, _rootKeys, 'manifest');
    final schemaVersion = _requireString(json, 'schemaVersion', 'manifest');
    if (schemaVersion != GroundTruthManifest.supportedSchemaVersion) {
      throw ManifestParseException(
        ManifestParseErrorKind.invalidSchemaVersion,
        'unsupported schemaVersion "$schemaVersion" '
        '(expected "${GroundTruthManifest.supportedSchemaVersion}")',
        path: 'manifest.schemaVersion',
      );
    }
    if (!json.containsKey('cases')) {
      throw const ManifestParseException(
        ManifestParseErrorKind.missingAnnotation,
        'manifest.cases is required',
        path: 'manifest.cases',
      );
    }
    final casesRaw = _asList(json['cases'], 'manifest.cases');

    final seenIds = <String>{};
    final cases = <GroundTruthCase>[];
    for (var i = 0; i < casesRaw.length; i++) {
      final caseJson = _asMap(casesRaw[i], 'manifest.cases[$i]');
      final parsed = _parseCase(caseJson, 'manifest.cases[$i]');
      if (!seenIds.add(parsed.id)) {
        throw ManifestParseException(
          ManifestParseErrorKind.duplicateCaseId,
          'duplicate case id "${parsed.id}"',
          path: 'manifest.cases[$i].id',
        );
      }
      cases.add(parsed);
    }
    return GroundTruthManifest(schemaVersion: schemaVersion, cases: cases);
  }

  GroundTruthCase _parseCase(Map<String, Object?> json, String path) {
    _checkKeys(json, _caseKeys, path);
    final id = _requireString(json, 'id', path);
    final tempoBand = _requireEnum(
      json,
      'tempoBand',
      path,
      TempoBand.values,
      (value) => value.name,
    );
    final signalQualityTier = _requireEnum(
      json,
      'signalQualityTier',
      path,
      SignalQualityTier.values,
      (value) => value.name,
    );
    final mode = _requireEnum(
      json,
      'mode',
      path,
      EvalMode.values,
      (value) => value.name,
    );
    _requireKey(json, 'expected', path);
    _requireKey(json, 'detected', path);
    final expected = _parseAnnotationSet(
      _asMap(json['expected'], '$path.expected'),
      '$path.expected',
    );
    final detected = _parseAnnotationSet(
      _asMap(json['detected'], '$path.detected'),
      '$path.detected',
    );
    final confidenceObservations = <ConfidenceObservation>[];
    final rawObservations = json['confidenceObservations'];
    if (rawObservations != null) {
      final list = _asList(rawObservations, '$path.confidenceObservations');
      for (var i = 0; i < list.length; i++) {
        confidenceObservations.add(
          _parseConfidenceObservation(
            _asMap(list[i], '$path.confidenceObservations[$i]'),
            '$path.confidenceObservations[$i]',
          ),
        );
      }
    }
    return GroundTruthCase(
      id: id,
      tempoBand: tempoBand,
      signalQualityTier: signalQualityTier,
      mode: mode,
      expected: expected,
      detected: detected,
      confidenceObservations: confidenceObservations,
    );
  }

  AnnotationSet _parseAnnotationSet(Map<String, Object?> json, String path) {
    _checkKeys(json, _annotationSetKeys, path);
    final events = <EvalEvent>[];
    final rawEvents = json['events'];
    if (rawEvents != null) {
      final list = _asList(rawEvents, '$path.events');
      for (var i = 0; i < list.length; i++) {
        events.add(
          _parseEvent(_asMap(list[i], '$path.events[$i]'), '$path.events[$i]'),
        );
      }
    }
    final chordSegments = <EvalChordSegment>[];
    final rawSegments = json['chordSegments'];
    if (rawSegments != null) {
      final list = _asList(rawSegments, '$path.chordSegments');
      for (var i = 0; i < list.length; i++) {
        chordSegments.add(
          _parseChordSegment(
            _asMap(list[i], '$path.chordSegments[$i]'),
            '$path.chordSegments[$i]',
          ),
        );
      }
    }
    double? tempoBpm;
    if (json.containsKey('tempoBpm') && json['tempoBpm'] != null) {
      tempoBpm = _asDouble(json['tempoBpm'], '$path.tempoBpm');
    }
    final beatsMs = <int>[];
    final rawBeats = json['beatsMs'];
    if (rawBeats != null) {
      final list = _asList(rawBeats, '$path.beatsMs');
      for (var i = 0; i < list.length; i++) {
        beatsMs.add(_asInt(list[i], '$path.beatsMs[$i]'));
      }
    }
    final pitchPoints = <PitchPoint>[];
    final rawPitch = json['pitchPoints'];
    if (rawPitch != null) {
      final list = _asList(rawPitch, '$path.pitchPoints');
      for (var i = 0; i < list.length; i++) {
        pitchPoints.add(
          _parsePitchPoint(
            _asMap(list[i], '$path.pitchPoints[$i]'),
            '$path.pitchPoints[$i]',
          ),
        );
      }
    }
    return _guard(
      () => AnnotationSet(
        events: events,
        chordSegments: chordSegments,
        tempoBpm: tempoBpm,
        beatsMs: beatsMs,
        pitchPoints: pitchPoints,
      ),
      path,
    );
  }

  EvalEvent _parseEvent(Map<String, Object?> json, String path) {
    _checkKeys(json, _eventKeys, path);
    final id = _requireString(json, 'id', path);
    final timeMs = _requireInt(json, 'timeMs', path);
    final type = _requireEnum(
      json,
      'type',
      path,
      EvalEventType.values,
      (value) => value.name,
    );
    StrumDirectionLabel? direction;
    final rawDirection = json['direction'];
    if (rawDirection != null) {
      direction = _enumFromString<StrumDirectionLabel>(
        _asString(rawDirection, '$path.direction'),
        StrumDirectionLabel.values,
        (value) => value.name,
        '$path.direction',
      );
    }
    if (type == EvalEventType.strum && direction == null) {
      throw ManifestParseException(
        ManifestParseErrorKind.missingAnnotation,
        'strum event requires a direction annotation',
        path: '$path.direction',
      );
    }
    return _guard(
      () => EvalEvent(id: id, timeMs: timeMs, type: type, direction: direction),
      path,
    );
  }

  EvalChordSegment _parseChordSegment(Map<String, Object?> json, String path) {
    _checkKeys(json, _chordSegmentKeys, path);
    final label = _requireString(json, 'label', path);
    final startMs = _requireInt(json, 'startMs', path);
    final endMs = _requireInt(json, 'endMs', path);
    if (endMs < startMs) {
      throw ManifestParseException(
        ManifestParseErrorKind.invalidChronology,
        'chord segment endMs ($endMs) is before startMs ($startMs)',
        path: path,
      );
    }
    return _guard(
      () => EvalChordSegment(label: label, startMs: startMs, endMs: endMs),
      path,
    );
  }

  PitchPoint _parsePitchPoint(Map<String, Object?> json, String path) {
    _checkKeys(json, _pitchPointKeys, path);
    final timeMs = _requireInt(json, 'timeMs', path);
    final hz = _requireDouble(json, 'hz', path);
    return _guard(() => PitchPoint(timeMs: timeMs, hz: hz), path);
  }

  ConfidenceObservation _parseConfidenceObservation(
    Map<String, Object?> json,
    String path,
  ) {
    _checkKeys(json, _confidenceObservationKeys, path);
    final rawScore = _requireDouble(json, 'rawScore', path);
    if (!json.containsKey('correct')) {
      throw ManifestParseException(
        ManifestParseErrorKind.missingAnnotation,
        'confidence observation requires "correct"',
        path: '$path.correct',
      );
    }
    final correctValue = json['correct'];
    if (correctValue is! bool) {
      throw ManifestParseException(
        ManifestParseErrorKind.malformedValue,
        'expected a bool',
        path: '$path.correct',
      );
    }
    return _guard(
      () => ConfidenceObservation(rawScore: rawScore, correct: correctValue),
      path,
    );
  }

  // --- typed field access helpers -----------------------------------

  void _checkKeys(Map<String, Object?> json, Set<String> allowed, String path) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        throw ManifestParseException(
          ManifestParseErrorKind.unknownField,
          'unrecognised field "$key"',
          path: '$path.$key',
        );
      }
    }
  }

  void _requireKey(Map<String, Object?> json, String key, String path) {
    if (!json.containsKey(key)) {
      throw ManifestParseException(
        ManifestParseErrorKind.missingAnnotation,
        '"$key" is required',
        path: '$path.$key',
      );
    }
  }

  String _requireString(Map<String, Object?> json, String key, String path) {
    _requireKey(json, key, path);
    return _asString(json[key], '$path.$key');
  }

  int _requireInt(Map<String, Object?> json, String key, String path) {
    _requireKey(json, key, path);
    return _asInt(json[key], '$path.$key');
  }

  double _requireDouble(Map<String, Object?> json, String key, String path) {
    _requireKey(json, key, path);
    return _asDouble(json[key], '$path.$key');
  }

  T _requireEnum<T>(
    Map<String, Object?> json,
    String key,
    String path,
    List<T> values,
    String Function(T) nameOf,
  ) {
    final raw = _requireString(json, key, path);
    return _enumFromString(raw, values, nameOf, '$path.$key');
  }

  T _enumFromString<T>(
    String raw,
    List<T> values,
    String Function(T) nameOf,
    String path,
  ) {
    for (final value in values) {
      if (nameOf(value) == raw) return value;
    }
    throw ManifestParseException(
      ManifestParseErrorKind.malformedValue,
      'unrecognised value "$raw" (expected one of '
      '${values.map(nameOf).join(', ')})',
      path: path,
    );
  }

  Map<String, Object?> _asMap(Object? value, String path) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key as String, v));
    }
    throw ManifestParseException(
      ManifestParseErrorKind.malformedValue,
      'expected an object',
      path: path,
    );
  }

  List<Object?> _asList(Object? value, String path) {
    if (value is List) return value;
    throw ManifestParseException(
      ManifestParseErrorKind.malformedValue,
      'expected an array',
      path: path,
    );
  }

  String _asString(Object? value, String path) {
    if (value is String) return value;
    throw ManifestParseException(
      ManifestParseErrorKind.malformedValue,
      'expected a string',
      path: path,
    );
  }

  int _asInt(Object? value, String path) {
    if (value is int) return value;
    throw ManifestParseException(
      ManifestParseErrorKind.malformedValue,
      'expected an integer',
      path: path,
    );
  }

  double _asDouble(Object? value, String path) {
    if (value is num) return value.toDouble();
    throw ManifestParseException(
      ManifestParseErrorKind.malformedValue,
      'expected a number',
      path: path,
    );
  }

  T _guard<T>(T Function() build, String path) {
    try {
      return build();
    } on ArgumentError catch (error) {
      throw ManifestParseException(
        ManifestParseErrorKind.malformedValue,
        error.message?.toString() ?? 'invalid value',
        path: path,
      );
    }
  }
}
