/// Manifest-JSON → [RecognitionEvaluationReport] runner (E14-R08, ADR
/// 0509), matching the repo's established harness shape
/// (`…/audio_analysis/data/evaluation/evaluation_runner.dart` +
/// `evaluation_manifest_parser.dart`, ADR 0249). Every rejection surfaces
/// as a typed [RecognitionManifestParseException] — the caller never sees a
/// raw [TypeError] or [FormatException] bubble out of [parseJsonString].
/// This file is `dart:io`-free: reading the manifest off disk is the CLI's
/// job (`tool/recognition_evaluate.dart`).
library;

import 'dart:convert';

import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';

enum RecognitionManifestParseErrorKind {
  missingField,
  unknownField,
  invalidSchemaVersion,
  malformedValue,
}

final class RecognitionManifestParseException implements Exception {
  const RecognitionManifestParseException(this.kind, this.message, {this.path});

  final RecognitionManifestParseErrorKind kind;
  final String message;
  final String? path;

  @override
  String toString() =>
      'RecognitionManifestParseException(${kind.name})'
      '${path == null ? '' : ' at $path'}: $message';
}

const String supportedRecognitionManifestSchemaVersion = '1.0';

const _rootKeys = <String>{'schemaVersion', 'cases'};
const _caseKeys = <String>{
  'caseId',
  'player',
  'device',
  'guitar',
  'room',
  'durationMs',
  'expectedEvents',
  'detectedEvents',
  'confidenceObservations',
  'detectionLatenciesMs',
};
const _expectedEventKeys = <String>{
  'timeMs',
  'kind',
  'direction',
  'chordLabel',
};
const _detectedEventKeys = <String>{
  'timeMs',
  'kind',
  'accepted',
  'confidence',
  'direction',
  'chordLabel',
};
const _confidenceObservationKeys = <String>{'rawScore', 'correct'};

/// Parses a recognition manifest and computes its [RecognitionEvaluationReport].
final class RecognitionEvaluationRunner {
  const RecognitionEvaluationRunner();

  RecognitionEvaluationReport run(RecognitionManifest manifest) =>
      RecognitionEvaluationReport(
        manifestSchemaVersion: manifest.schemaVersion,
        caseCount: manifest.cases.length,
        overall: computeRecognitionMetrics(manifest.cases),
      );

  RecognitionEvaluationReport runFromJsonString(String source) =>
      run(parseManifestJsonString(source));

  RecognitionManifest parseManifestJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw RecognitionManifestParseException(
        RecognitionManifestParseErrorKind.malformedValue,
        'manifest is not valid JSON: ${error.message}',
      );
    }
    return parseManifest(_asMap(decoded, 'manifest'));
  }

  RecognitionManifest parseManifest(Map<String, Object?> json) {
    _checkKeys(json, _rootKeys, 'manifest');
    final schemaVersion = _requireString(json, 'schemaVersion', 'manifest');
    if (schemaVersion != supportedRecognitionManifestSchemaVersion) {
      throw RecognitionManifestParseException(
        RecognitionManifestParseErrorKind.invalidSchemaVersion,
        'unsupported schemaVersion "$schemaVersion" '
        '(expected "$supportedRecognitionManifestSchemaVersion")',
        path: 'manifest.schemaVersion',
      );
    }
    final rawCases = _asList(
      _requireField(json, 'cases', 'manifest'),
      'manifest.cases',
    );
    final cases = <RecognitionCase>[
      for (var i = 0; i < rawCases.length; i++)
        _parseCase(
          _asMap(rawCases[i], 'manifest.cases[$i]'),
          'manifest.cases[$i]',
        ),
    ];
    return RecognitionManifest(schemaVersion: schemaVersion, cases: cases);
  }

  RecognitionCase _parseCase(Map<String, Object?> json, String path) {
    _checkKeys(json, _caseKeys, path);
    final caseId = _requireString(json, 'caseId', path);
    final durationMs = _requireInt(json, 'durationMs', path);

    final expectedEvents = <RecognitionExpectedEvent>[];
    final rawExpected = json['expectedEvents'];
    if (rawExpected != null) {
      final list = _asList(rawExpected, '$path.expectedEvents');
      for (var i = 0; i < list.length; i++) {
        expectedEvents.add(
          _parseExpectedEvent(
            _asMap(list[i], '$path.expectedEvents[$i]'),
            '$path.expectedEvents[$i]',
          ),
        );
      }
    }

    final detectedEvents = <RecognitionDetectedEvent>[];
    final rawDetected = json['detectedEvents'];
    if (rawDetected != null) {
      final list = _asList(rawDetected, '$path.detectedEvents');
      for (var i = 0; i < list.length; i++) {
        detectedEvents.add(
          _parseDetectedEvent(
            _asMap(list[i], '$path.detectedEvents[$i]'),
            '$path.detectedEvents[$i]',
          ),
        );
      }
    }

    final confidenceObservations = <RecognitionConfidenceObservation>[];
    final rawConfidence = json['confidenceObservations'];
    if (rawConfidence != null) {
      final list = _asList(rawConfidence, '$path.confidenceObservations');
      for (var i = 0; i < list.length; i++) {
        confidenceObservations.add(
          _parseConfidenceObservation(
            _asMap(list[i], '$path.confidenceObservations[$i]'),
            '$path.confidenceObservations[$i]',
          ),
        );
      }
    }

    final detectionLatenciesMs = <int>[];
    final rawLatencies = json['detectionLatenciesMs'];
    if (rawLatencies != null) {
      final list = _asList(rawLatencies, '$path.detectionLatenciesMs');
      for (var i = 0; i < list.length; i++) {
        detectionLatenciesMs.add(
          _asInt(list[i], '$path.detectionLatenciesMs[$i]'),
        );
      }
    }

    return RecognitionCase(
      caseId: caseId,
      player: _optionalString(json, 'player'),
      device: _optionalString(json, 'device'),
      guitar: _optionalString(json, 'guitar'),
      room: _optionalString(json, 'room'),
      durationMs: durationMs,
      expectedEvents: expectedEvents,
      detectedEvents: detectedEvents,
      confidenceObservations: confidenceObservations,
      detectionLatenciesMs: detectionLatenciesMs,
    );
  }

  RecognitionExpectedEvent _parseExpectedEvent(
    Map<String, Object?> json,
    String path,
  ) {
    _checkKeys(json, _expectedEventKeys, path);
    final timeMs = _requireInt(json, 'timeMs', path);
    final kind = _requireEventKind(json, path);
    final direction = _optionalDirection(json, path);
    final chordLabel = _optionalString(json, 'chordLabel');
    _requireKindFields(kind, direction, chordLabel, path);
    return RecognitionExpectedEvent(
      timeMs: timeMs,
      kind: kind,
      direction: direction,
      chordLabel: chordLabel,
    );
  }

  RecognitionDetectedEvent _parseDetectedEvent(
    Map<String, Object?> json,
    String path,
  ) {
    _checkKeys(json, _detectedEventKeys, path);
    final timeMs = _requireInt(json, 'timeMs', path);
    final kind = _requireEventKind(json, path);
    final accepted = _requireBool(json, 'accepted', path);
    final confidence = _requireDouble(json, 'confidence', path);
    final direction = _optionalDirection(json, path);
    final chordLabel = _optionalString(json, 'chordLabel');
    _requireKindFields(kind, direction, chordLabel, path);
    return RecognitionDetectedEvent(
      timeMs: timeMs,
      kind: kind,
      accepted: accepted,
      confidence: confidence,
      direction: direction,
      chordLabel: chordLabel,
    );
  }

  void _requireKindFields(
    RecognitionEventKind kind,
    StrumDirection? direction,
    String? chordLabel,
    String path,
  ) {
    if (kind == RecognitionEventKind.strum && direction == null) {
      throw RecognitionManifestParseException(
        RecognitionManifestParseErrorKind.missingField,
        'strum event requires a direction',
        path: '$path.direction',
      );
    }
    if (kind == RecognitionEventKind.chord && chordLabel == null) {
      throw RecognitionManifestParseException(
        RecognitionManifestParseErrorKind.missingField,
        'chord event requires a chordLabel',
        path: '$path.chordLabel',
      );
    }
  }

  RecognitionConfidenceObservation _parseConfidenceObservation(
    Map<String, Object?> json,
    String path,
  ) {
    _checkKeys(json, _confidenceObservationKeys, path);
    return RecognitionConfidenceObservation(
      rawScore: _requireDouble(json, 'rawScore', path),
      correct: _requireBool(json, 'correct', path),
    );
  }

  RecognitionEventKind _requireEventKind(
    Map<String, Object?> json,
    String path,
  ) {
    final raw = _requireString(json, 'kind', path);
    for (final value in RecognitionEventKind.values) {
      if (value.name == raw) return value;
    }
    throw RecognitionManifestParseException(
      RecognitionManifestParseErrorKind.malformedValue,
      'unrecognised kind "$raw" (expected one of '
      '${RecognitionEventKind.values.map((v) => v.name).join(', ')})',
      path: '$path.kind',
    );
  }

  StrumDirection? _optionalDirection(Map<String, Object?> json, String path) {
    final raw = json['direction'];
    if (raw == null) return null;
    final value = _asString(raw, '$path.direction');
    for (final direction in StrumDirection.values) {
      if (direction.name == value) return direction;
    }
    throw RecognitionManifestParseException(
      RecognitionManifestParseErrorKind.malformedValue,
      'unrecognised direction "$value" (expected one of '
      '${StrumDirection.values.map((v) => v.name).join(', ')})',
      path: '$path.direction',
    );
  }

  String? _optionalString(Map<String, Object?> json, String key) {
    final raw = json[key];
    if (raw == null) return null;
    return raw as String;
  }

  // --- typed field access helpers -----------------------------------

  void _checkKeys(Map<String, Object?> json, Set<String> allowed, String path) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        throw RecognitionManifestParseException(
          RecognitionManifestParseErrorKind.unknownField,
          'unrecognised field "$key"',
          path: '$path.$key',
        );
      }
    }
  }

  Object? _requireField(Map<String, Object?> json, String key, String path) {
    if (!json.containsKey(key)) {
      throw RecognitionManifestParseException(
        RecognitionManifestParseErrorKind.missingField,
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

  bool _requireBool(Map<String, Object?> json, String key, String path) {
    final value = _requireField(json, key, path);
    if (value is bool) return value;
    throw RecognitionManifestParseException(
      RecognitionManifestParseErrorKind.malformedValue,
      'expected a boolean',
      path: '$path.$key',
    );
  }

  double _requireDouble(Map<String, Object?> json, String key, String path) {
    final value = _requireField(json, key, path);
    if (value is num) return value.toDouble();
    throw RecognitionManifestParseException(
      RecognitionManifestParseErrorKind.malformedValue,
      'expected a number',
      path: '$path.$key',
    );
  }

  Map<String, Object?> _asMap(Object? value, String path) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key as String, v));
    }
    throw RecognitionManifestParseException(
      RecognitionManifestParseErrorKind.malformedValue,
      'expected an object',
      path: path,
    );
  }

  List<Object?> _asList(Object? value, String path) {
    if (value is List) return value;
    throw RecognitionManifestParseException(
      RecognitionManifestParseErrorKind.malformedValue,
      'expected an array',
      path: path,
    );
  }

  String _asString(Object? value, String path) {
    if (value is String) return value;
    throw RecognitionManifestParseException(
      RecognitionManifestParseErrorKind.malformedValue,
      'expected a string',
      path: path,
    );
  }

  int _asInt(Object? value, String path) {
    if (value is int) return value;
    throw RecognitionManifestParseException(
      RecognitionManifestParseErrorKind.malformedValue,
      'expected an integer',
      path: path,
    );
  }
}
