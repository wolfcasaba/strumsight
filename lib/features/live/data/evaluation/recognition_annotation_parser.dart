/// Typed-failure parser for the recognition annotation contract
/// (`evaluation/recognition/annotation_schema.json`, E14-R07, ADR 0359).
///
/// Every rejection — a missing required field (including `provenance`), an
/// unrecognised field, an overlapping event/chord-segment pair, or an
/// unsupported schema version — surfaces as a
/// [RecognitionAnnotationParseException]. The caller never sees a raw
/// [TypeError] or [ArgumentError] bubble out of `parse`. This file never
/// opens a file or a socket (ADR 0359 D1/D7) — reading the annotation pair
/// off disk is the CLI's job (`tool/recognition_annotate.dart`).
library;

import 'dart:convert';

import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_annotation.dart';

enum RecognitionAnnotationParseErrorKind {
  missingField,
  unknownField,
  invalidSchemaVersion,
  overlappingEvents,
  malformedValue,
}

final class RecognitionAnnotationParseException implements Exception {
  const RecognitionAnnotationParseException(
    this.kind,
    this.message, {
    this.path,
    this.conflictingIndices,
  });

  final RecognitionAnnotationParseErrorKind kind;
  final String message;
  final String? path;

  /// The two conflicting event/chord-segment indices, set only for
  /// [RecognitionAnnotationParseErrorKind.overlappingEvents] (ADR 0359 D3).
  final List<int>? conflictingIndices;

  @override
  String toString() =>
      'RecognitionAnnotationParseException(${kind.name})'
      '${path == null ? '' : ' at $path'}: $message';
}

const _rootKeys = <String>{'schemaVersion', 'annotatorA', 'annotatorB'};
const _annotationKeys = <String>{'annotatorId', 'events', 'chordSegments'};
const _eventKeys = <String>{'id', 'timeMs', 'type', 'direction', 'provenance'};
const _chordSegmentKeys = <String>{
  'id',
  'startMs',
  'endMs',
  'label',
  'provenance',
};

/// Parses a decoded (or raw JSON text) annotation pair into a
/// [RecognitionAnnotationPair], rejecting anything that does not match
/// `annotation_schema.json` with a typed [RecognitionAnnotationParseException].
final class RecognitionAnnotationParser {
  const RecognitionAnnotationParser();

  RecognitionAnnotationPair parseJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw RecognitionAnnotationParseException(
        RecognitionAnnotationParseErrorKind.malformedValue,
        'annotation pair is not valid JSON: ${error.message}',
      );
    }
    return parse(_asMap(decoded, 'annotationPair'));
  }

  RecognitionAnnotationPair parse(Map<String, Object?> json) {
    _checkKeys(json, _rootKeys, 'annotationPair');
    final schemaVersion = _requireString(
      json,
      'schemaVersion',
      'annotationPair',
    );
    if (schemaVersion != RecognitionAnnotationPair.supportedSchemaVersion) {
      throw RecognitionAnnotationParseException(
        RecognitionAnnotationParseErrorKind.invalidSchemaVersion,
        'unsupported schemaVersion "$schemaVersion" '
        '(expected "${RecognitionAnnotationPair.supportedSchemaVersion}")',
        path: 'annotationPair.schemaVersion',
      );
    }
    final annotatorA = _parseAnnotation(
      _asMap(
        _requireField(json, 'annotatorA', 'annotationPair'),
        'annotationPair.annotatorA',
      ),
      'annotationPair.annotatorA',
    );
    final annotatorB = _parseAnnotation(
      _asMap(
        _requireField(json, 'annotatorB', 'annotationPair'),
        'annotationPair.annotatorB',
      ),
      'annotationPair.annotatorB',
    );
    return RecognitionAnnotationPair(
      schemaVersion: schemaVersion,
      annotatorA: annotatorA,
      annotatorB: annotatorB,
    );
  }

  RecognitionAnnotation _parseAnnotation(
    Map<String, Object?> json,
    String path,
  ) {
    _checkKeys(json, _annotationKeys, path);
    final annotatorId = _requireString(json, 'annotatorId', path);

    final events = <AnnotationEvent>[];
    final rawEvents = json['events'];
    if (rawEvents != null) {
      final list = _asList(rawEvents, '$path.events');
      for (var i = 0; i < list.length; i++) {
        events.add(
          _parseEvent(_asMap(list[i], '$path.events[$i]'), '$path.events[$i]'),
        );
      }
    }
    _checkEventOverlaps(events, '$path.events');

    final chordSegments = <AnnotationChordSegment>[];
    final rawChordSegments = json['chordSegments'];
    if (rawChordSegments != null) {
      final list = _asList(rawChordSegments, '$path.chordSegments');
      for (var i = 0; i < list.length; i++) {
        chordSegments.add(
          _parseChordSegment(
            _asMap(list[i], '$path.chordSegments[$i]'),
            '$path.chordSegments[$i]',
          ),
        );
      }
    }
    _checkChordSegmentOverlaps(chordSegments, '$path.chordSegments');

    return _guard(
      () => RecognitionAnnotation(
        annotatorId: annotatorId,
        events: events,
        chordSegments: chordSegments,
      ),
      path,
    );
  }

  AnnotationEvent _parseEvent(Map<String, Object?> json, String path) {
    _checkKeys(json, _eventKeys, path);
    final id = _requireString(json, 'id', path);
    final timeMs = _requireInt(json, 'timeMs', path);
    final type = _requireEnum(
      json,
      'type',
      path,
      AnnotationEventType.values,
      (value) => value.name,
    );
    StrumDirection? direction;
    final rawDirection = json['direction'];
    if (rawDirection != null) {
      direction = _enumFromString<StrumDirection>(
        _asString(rawDirection, '$path.direction'),
        StrumDirection.values,
        (value) => value.name,
        '$path.direction',
      );
    }
    if (type == AnnotationEventType.strum && direction == null) {
      throw RecognitionAnnotationParseException(
        RecognitionAnnotationParseErrorKind.missingField,
        'strum event requires a direction annotation',
        path: '$path.direction',
      );
    }
    final provenance = _requireEnum(
      json,
      'provenance',
      path,
      AnnotationProvenance.values,
      (value) => value.name,
    );
    return _guard(
      () => AnnotationEvent(
        id: id,
        timeMs: timeMs,
        type: type,
        provenance: provenance,
        direction: direction,
      ),
      path,
    );
  }

  AnnotationChordSegment _parseChordSegment(
    Map<String, Object?> json,
    String path,
  ) {
    _checkKeys(json, _chordSegmentKeys, path);
    final id = _requireString(json, 'id', path);
    final startMs = _requireInt(json, 'startMs', path);
    final endMs = _requireInt(json, 'endMs', path);
    final label = _requireString(json, 'label', path);
    final provenance = _requireEnum(
      json,
      'provenance',
      path,
      AnnotationProvenance.values,
      (value) => value.name,
    );
    return _guard(
      () => AnnotationChordSegment(
        id: id,
        startMs: startMs,
        endMs: endMs,
        label: label,
        provenance: provenance,
      ),
      path,
    );
  }

  /// Two events on the same lane (`type`) at the exact same `timeMs` are a
  /// typed overlap failure (ADR 0359 D3) — never silently dropped, merged,
  /// or reordered.
  void _checkEventOverlaps(List<AnnotationEvent> events, String path) {
    for (var i = 0; i < events.length; i++) {
      for (var j = i + 1; j < events.length; j++) {
        if (events[i].type == events[j].type &&
            events[i].timeMs == events[j].timeMs) {
          throw RecognitionAnnotationParseException(
            RecognitionAnnotationParseErrorKind.overlappingEvents,
            'events at indices $i and $j overlap: both are '
            '"${events[i].type.name}" at timeMs ${events[i].timeMs}',
            path: path,
            conflictingIndices: [i, j],
          );
        }
      }
    }
  }

  /// Two chord segments whose `[startMs, endMs)` ranges intersect are a
  /// typed overlap failure (ADR 0359 D3); segments that merely touch at a
  /// boundary (one's `endMs` equals the other's `startMs`) do not overlap.
  void _checkChordSegmentOverlaps(
    List<AnnotationChordSegment> segments,
    String path,
  ) {
    for (var i = 0; i < segments.length; i++) {
      for (var j = i + 1; j < segments.length; j++) {
        final left = segments[i];
        final right = segments[j];
        if (left.startMs < right.endMs && right.startMs < left.endMs) {
          throw RecognitionAnnotationParseException(
            RecognitionAnnotationParseErrorKind.overlappingEvents,
            'chord segments at indices $i and $j overlap in time',
            path: path,
            conflictingIndices: [i, j],
          );
        }
      }
    }
  }

  // --- typed field access helpers -----------------------------------

  void _checkKeys(Map<String, Object?> json, Set<String> allowed, String path) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        throw RecognitionAnnotationParseException(
          RecognitionAnnotationParseErrorKind.unknownField,
          'unrecognised field "$key"',
          path: '$path.$key',
        );
      }
    }
  }

  Object? _requireField(Map<String, Object?> json, String key, String path) {
    if (!json.containsKey(key)) {
      throw RecognitionAnnotationParseException(
        RecognitionAnnotationParseErrorKind.missingField,
        '"$key" is required',
        path: '$path.$key',
      );
    }
    return json[key];
  }

  String _requireString(Map<String, Object?> json, String key, String path) =>
      _asString(_requireField(json, key, path), '$path.$key');

  int _requireInt(Map<String, Object?> json, String key, String path) =>
      _asInt(_requireField(json, key, path), '$path.$key');

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
    throw RecognitionAnnotationParseException(
      RecognitionAnnotationParseErrorKind.malformedValue,
      'unrecognised value "$raw" (expected one of '
      '${values.map(nameOf).join(', ')})',
      path: path,
    );
  }

  Map<String, Object?> _asMap(Object? value, String path) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key as String, v));
    }
    throw RecognitionAnnotationParseException(
      RecognitionAnnotationParseErrorKind.malformedValue,
      'expected an object',
      path: path,
    );
  }

  List<Object?> _asList(Object? value, String path) {
    if (value is List) return value;
    throw RecognitionAnnotationParseException(
      RecognitionAnnotationParseErrorKind.malformedValue,
      'expected an array',
      path: path,
    );
  }

  String _asString(Object? value, String path) {
    if (value is String) return value;
    throw RecognitionAnnotationParseException(
      RecognitionAnnotationParseErrorKind.malformedValue,
      'expected a string',
      path: path,
    );
  }

  int _asInt(Object? value, String path) {
    if (value is int) return value;
    throw RecognitionAnnotationParseException(
      RecognitionAnnotationParseErrorKind.malformedValue,
      'expected an integer',
      path: path,
    );
  }

  T _guard<T>(T Function() build, String path) {
    try {
      return build();
    } on ArgumentError catch (error) {
      throw RecognitionAnnotationParseException(
        RecognitionAnnotationParseErrorKind.malformedValue,
        error.message?.toString() ?? 'invalid value',
        path: path,
      );
    }
  }
}
