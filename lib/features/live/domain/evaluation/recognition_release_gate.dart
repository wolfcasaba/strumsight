/// Fail-closed recognition release gate (E14-R09, ADR 0511).
///
/// Reads a versioned threshold file and evaluates it against a
/// [RecognitionMetrics] instance (the E14-R08 metric set, ADR 0509). A
/// missing metric — one the threshold file names but the report carries as
/// `null` (zero denominator / zero sample) — is a **FAIL**, named in the
/// finding's reason; nothing is skipped or defaulted (ADR 0511 D1). The
/// comparison direction is never declared by the threshold file — it is
/// read from the metric's own `definition.higherIsBetter` at evaluation
/// time (D2), and the boundary belongs to the accepting side: `value >=
/// threshold` when higher is better, `value <= threshold` otherwise, with no
/// rounding or epsilon tolerance (D3). This file never opens a file or a
/// socket — reading the threshold JSON off disk is the CLI's job
/// (`tool/recognition_report.dart`).
library;

import 'dart:convert';

import 'recognition_metrics.dart';

enum RecognitionGateConfigErrorKind {
  malformedValue,
  missingField,
  unknownField,
  unknownSchemaVersion,
  directionDeclared,
  unknownMetricPath,
}

/// A typed threshold-file or evaluation-time configuration failure. Never a
/// bare [FormatException] or [TypeError] — every rejection names its
/// [kind] and, where applicable, the offending JSON [path] (ADR 0511 D6).
final class RecognitionGateConfigException implements Exception {
  const RecognitionGateConfigException(this.kind, this.message, {this.path});

  final RecognitionGateConfigErrorKind kind;
  final String message;
  final String? path;

  @override
  String toString() =>
      'RecognitionGateConfigException(${kind.name})'
      '${path == null ? '' : ' at $path'}: $message';
}

/// The only threshold-file schema version this gate accepts. An unrecognised
/// `schemaVersion` is a typed error, never a silent fall-back to a default
/// threshold set (ADR 0511 D6).
const String supportedRecognitionGateSchemaVersion = '1';

/// Every metric path a threshold file may reference, and how to read its
/// current value and comparison direction off a [RecognitionMetrics]
/// instance. The direction always comes from the metric's own
/// `definition.higherIsBetter` — never a separately maintained constant —
/// so the value and its direction can never drift apart (ADR 0511 D2). Keys
/// are the metric identifiers used both by [RecognitionReleaseGate]
/// (prefixed with `overall.`, see [_gateMetricPathPrefix]) and by
/// `recognition_report_renderer.dart`'s per-scope metric summaries.
final Map<String, RecognitionMetricSample Function(RecognitionMetrics)>
recognitionMetricExtractors =
    <String, RecognitionMetricSample Function(RecognitionMetrics)>{
      'onsetTolerance50Ms.f1': (metrics) => RecognitionMetricSample(
        value: metrics.onsetTolerance50Ms.f1,
        higherIsBetter: metrics.onsetTolerance50Ms.definition.higherIsBetter,
      ),
      'directionF1.value': (metrics) => RecognitionMetricSample(
        value: metrics.directionF1.value,
        higherIsBetter: metrics.directionF1.definition.higherIsBetter,
      ),
      'acceptedAccuracy.value': (metrics) => RecognitionMetricSample(
        value: metrics.acceptedAccuracy.value,
        higherIsBetter: metrics.acceptedAccuracy.definition.higherIsBetter,
      ),
      'coverage.value': (metrics) => RecognitionMetricSample(
        value: metrics.coverage.value,
        higherIsBetter: metrics.coverage.definition.higherIsBetter,
      ),
      'falseVisibleEventsPerMinute.value': (metrics) => RecognitionMetricSample(
        value: metrics.falseVisibleEventsPerMinute.value,
        higherIsBetter:
            metrics.falseVisibleEventsPerMinute.definition.higherIsBetter,
      ),
      'falseVisibleDirectionEventsPerMinute.value': (metrics) =>
          RecognitionMetricSample(
            value: metrics.falseVisibleDirectionEventsPerMinute.value,
            higherIsBetter: metrics
                .falseVisibleDirectionEventsPerMinute
                .definition
                .higherIsBetter,
          ),
      'falseVisibleChordEventsPerMinute.value': (metrics) =>
          RecognitionMetricSample(
            value: metrics.falseVisibleChordEventsPerMinute.value,
            higherIsBetter: metrics
                .falseVisibleChordEventsPerMinute
                .definition
                .higherIsBetter,
          ),
      'latencyP50Ms.value': (metrics) => RecognitionMetricSample(
        value: metrics.latencyP50Ms.value,
        higherIsBetter: metrics.latencyP50Ms.definition.higherIsBetter,
      ),
      'latencyP95Ms.value': (metrics) => RecognitionMetricSample(
        value: metrics.latencyP95Ms.value,
        higherIsBetter: metrics.latencyP95Ms.definition.higherIsBetter,
      ),
      'chordWeightedAccuracy.value': (metrics) => RecognitionMetricSample(
        value: metrics.chordWeightedAccuracy.value,
        higherIsBetter: metrics.chordWeightedAccuracy.definition.higherIsBetter,
      ),
      'chordMacroF1.value': (metrics) => RecognitionMetricSample(
        value: metrics.chordMacroF1.value,
        higherIsBetter: metrics.chordMacroF1.definition.higherIsBetter,
      ),
      'chordNoChordF1.f1': (metrics) => RecognitionMetricSample(
        value: metrics.chordNoChordF1.f1,
        higherIsBetter: metrics.chordNoChordF1.definition.higherIsBetter,
      ),
      'chordUnknownFalseAccept.value': (metrics) => RecognitionMetricSample(
        value: metrics.chordUnknownFalseAccept.value,
        higherIsBetter:
            metrics.chordUnknownFalseAccept.definition.higherIsBetter,
      ),
    };

/// A single metric reading pulled off a [RecognitionMetrics] instance:
/// [value] is `null` exactly when the underlying ratio/scalar had nothing to
/// divide by, and [higherIsBetter] is copied verbatim from that metric's own
/// [RecognitionMetricDefinition].
final class RecognitionMetricSample {
  const RecognitionMetricSample({
    required this.value,
    required this.higherIsBetter,
  });

  final double? value;
  final bool higherIsBetter;
}

/// The only scope this gate currently evaluates: the manifest's aggregate
/// (non-grouped) [RecognitionMetrics]. A threshold entry's `metricPath` must
/// start with this prefix.
const String _gateMetricPathPrefix = 'overall.';

/// One threshold-file entry: a metric path and the boundary value it must
/// meet. Deliberately carries no direction field — declaring one in the
/// source JSON is a typed error (ADR 0511 D2, checked by
/// [RecognitionGateThresholds.parse]).
final class RecognitionGateThresholdEntry {
  const RecognitionGateThresholdEntry({
    required this.metricPath,
    required this.threshold,
    this.label,
  });

  final String metricPath;
  final double threshold;
  final String? label;

  Map<String, Object?> toJson() => <String, Object?>{
    'metricPath': metricPath,
    'threshold': threshold,
    'label': label,
  };
}

/// A parsed, versioned threshold file (ADR 0511 D6). [entries] is always
/// sorted by [RecognitionGateThresholdEntry.metricPath] so the gate's
/// findings come out in a deterministic order regardless of the source
/// JSON's array order (D7).
final class RecognitionGateThresholds {
  const RecognitionGateThresholds({
    required this.schemaVersion,
    required this.thresholdsVersion,
    required this.entries,
  });

  final String schemaVersion;
  final String thresholdsVersion;
  final List<RecognitionGateThresholdEntry> entries;
}

/// A single metric's pass/fail judgement (ADR 0511 D1/D2/D3).
final class RecognitionGateFinding {
  const RecognitionGateFinding({
    required this.metricPath,
    required this.label,
    required this.thresholdsVersion,
    required this.threshold,
    required this.higherIsBetter,
    required this.value,
    required this.passed,
    required this.reason,
  });

  final String metricPath;
  final String? label;
  final String thresholdsVersion;
  final double threshold;
  final bool higherIsBetter;

  /// `null` exactly when the metric was missing/unavailable (denominator or
  /// sample count zero) — in which case [passed] is always `false`.
  final double? value;
  final bool passed;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'metricPath': metricPath,
    'label': label,
    'thresholdsVersion': thresholdsVersion,
    'threshold': threshold,
    'higherIsBetter': higherIsBetter,
    'value': value,
    'passed': passed,
    'reason': reason,
  };
}

/// The overall gate outcome: [passed] is `true` only when every finding
/// passed — one missing or below-threshold metric fails the whole gate.
final class RecognitionGateVerdict {
  const RecognitionGateVerdict({
    required this.schemaVersion,
    required this.thresholdsVersion,
    required this.passed,
    required this.findings,
  });

  final String schemaVersion;
  final String thresholdsVersion;
  final bool passed;
  final List<RecognitionGateFinding> findings;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'thresholdsVersion': thresholdsVersion,
    'passed': passed,
    'findings': <Map<String, Object?>>[
      for (final finding in findings) finding.toJson(),
    ],
  };
}

const _rootKeys = <String>{'schemaVersion', 'thresholdsVersion', 'thresholds'};
const _entryKeys = <String>{'metricPath', 'threshold', 'label'};
const _directionKeys = <String>{'higherIsBetter', 'direction', '>=', '<='};

/// Parses [RecognitionGateThresholds] and evaluates them against a
/// [RecognitionMetrics] instance.
final class RecognitionReleaseGate {
  const RecognitionReleaseGate();

  RecognitionGateThresholds parseThresholdsJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw RecognitionGateConfigException(
        RecognitionGateConfigErrorKind.malformedValue,
        'threshold file is not valid JSON: ${error.message}',
      );
    }
    return parseThresholds(_asMap(decoded, 'thresholds'));
  }

  RecognitionGateThresholds parseThresholds(Map<String, Object?> json) {
    _checkKeys(json, _rootKeys, 'thresholds');
    final schemaVersion = _requireString(json, 'schemaVersion', 'thresholds');
    if (schemaVersion != supportedRecognitionGateSchemaVersion) {
      throw RecognitionGateConfigException(
        RecognitionGateConfigErrorKind.unknownSchemaVersion,
        'unsupported schemaVersion "$schemaVersion" '
        '(expected "$supportedRecognitionGateSchemaVersion")',
        path: 'thresholds.schemaVersion',
      );
    }
    final thresholdsVersion = _requireString(
      json,
      'thresholdsVersion',
      'thresholds',
    );
    final rawEntries = _asList(
      _requireField(json, 'thresholds', 'thresholds'),
      'thresholds.thresholds',
    );
    final entries = <RecognitionGateThresholdEntry>[
      for (var i = 0; i < rawEntries.length; i++)
        _parseEntry(
          _asMap(rawEntries[i], 'thresholds.thresholds[$i]'),
          'thresholds.thresholds[$i]',
        ),
    ]..sort((a, b) => a.metricPath.compareTo(b.metricPath));
    return RecognitionGateThresholds(
      schemaVersion: schemaVersion,
      thresholdsVersion: thresholdsVersion,
      entries: entries,
    );
  }

  RecognitionGateThresholdEntry _parseEntry(
    Map<String, Object?> json,
    String path,
  ) {
    for (final key in json.keys) {
      if (_directionKeys.contains(key)) {
        throw RecognitionGateConfigException(
          RecognitionGateConfigErrorKind.directionDeclared,
          'threshold entry declares a direction via "$key" — the '
          'comparison direction always comes from the report\'s '
          'higherIsBetter, never from the threshold file (ADR 0511 D2)',
          path: '$path.$key',
        );
      }
    }
    _checkKeys(json, _entryKeys, path);
    final metricPath = _requireString(json, 'metricPath', path);
    final threshold = _requireDouble(json, 'threshold', path);
    final label = json['label'] == null
        ? null
        : _asString(json['label'], '$path.label');
    return RecognitionGateThresholdEntry(
      metricPath: metricPath,
      threshold: threshold,
      label: label,
    );
  }

  /// Evaluates [thresholds] against [metrics] (ADR 0511 D1/D2/D3). Every
  /// entry produces exactly one finding — a missing/null metric fails
  /// closed (never skipped), named by its `metricPath`.
  RecognitionGateVerdict evaluate(
    RecognitionMetrics metrics,
    RecognitionGateThresholds thresholds,
  ) {
    final findings = <RecognitionGateFinding>[
      for (final entry in thresholds.entries)
        _evaluateEntry(metrics, thresholds.thresholdsVersion, entry),
    ];
    return RecognitionGateVerdict(
      schemaVersion: thresholds.schemaVersion,
      thresholdsVersion: thresholds.thresholdsVersion,
      passed: findings.every((finding) => finding.passed),
      findings: findings,
    );
  }

  RecognitionGateFinding _evaluateEntry(
    RecognitionMetrics metrics,
    String thresholdsVersion,
    RecognitionGateThresholdEntry entry,
  ) {
    if (!entry.metricPath.startsWith(_gateMetricPathPrefix)) {
      throw RecognitionGateConfigException(
        RecognitionGateConfigErrorKind.unknownMetricPath,
        'metricPath "${entry.metricPath}" must start with '
        '"$_gateMetricPathPrefix" — this gate only evaluates the '
        'manifest-wide aggregate report',
      );
    }
    final metricName = entry.metricPath.substring(_gateMetricPathPrefix.length);
    final extractor = recognitionMetricExtractors[metricName];
    if (extractor == null) {
      throw RecognitionGateConfigException(
        RecognitionGateConfigErrorKind.unknownMetricPath,
        'metricPath "${entry.metricPath}" does not name a known '
        'RecognitionMetrics field',
      );
    }
    final sample = extractor(metrics);
    if (sample.value == null) {
      return RecognitionGateFinding(
        metricPath: entry.metricPath,
        label: entry.label,
        thresholdsVersion: thresholdsVersion,
        threshold: entry.threshold,
        higherIsBetter: sample.higherIsBetter,
        value: null,
        passed: false,
        reason:
            'metric "${entry.metricPath}" is missing (null: zero '
            'denominator or zero sample) — a missing metric fails closed',
      );
    }
    final value = sample.value!;
    final passed = sample.higherIsBetter
        ? value >= entry.threshold
        : value <= entry.threshold;
    return RecognitionGateFinding(
      metricPath: entry.metricPath,
      label: entry.label,
      thresholdsVersion: thresholdsVersion,
      threshold: entry.threshold,
      higherIsBetter: sample.higherIsBetter,
      value: value,
      passed: passed,
      reason: passed
          ? '$value ${sample.higherIsBetter ? '>=' : '<='} '
                '${entry.threshold} (thresholdsVersion '
                '"$thresholdsVersion")'
          : '$value fails ${sample.higherIsBetter ? '>=' : '<='} '
                '${entry.threshold} (thresholdsVersion '
                '"$thresholdsVersion")',
    );
  }

  // --- typed field access helpers -----------------------------------

  void _checkKeys(Map<String, Object?> json, Set<String> allowed, String path) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        throw RecognitionGateConfigException(
          RecognitionGateConfigErrorKind.unknownField,
          'unrecognised field "$key"',
          path: '$path.$key',
        );
      }
    }
  }

  Object? _requireField(Map<String, Object?> json, String key, String path) {
    if (!json.containsKey(key)) {
      throw RecognitionGateConfigException(
        RecognitionGateConfigErrorKind.missingField,
        '"$key" is required',
        path: '$path.$key',
      );
    }
    return json[key];
  }

  String _requireString(Map<String, Object?> json, String key, String path) =>
      _asString(_requireField(json, key, path), '$path.$key');

  double _requireDouble(Map<String, Object?> json, String key, String path) {
    final value = _requireField(json, key, path);
    if (value is num) return value.toDouble();
    throw RecognitionGateConfigException(
      RecognitionGateConfigErrorKind.malformedValue,
      'expected a number',
      path: '$path.$key',
    );
  }

  Map<String, Object?> _asMap(Object? value, String path) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key as String, v));
    }
    throw RecognitionGateConfigException(
      RecognitionGateConfigErrorKind.malformedValue,
      'expected an object',
      path: path,
    );
  }

  List<Object?> _asList(Object? value, String path) {
    if (value is List) return value;
    throw RecognitionGateConfigException(
      RecognitionGateConfigErrorKind.malformedValue,
      'expected an array',
      path: path,
    );
  }

  String _asString(Object? value, String path) {
    if (value is String) return value;
    throw RecognitionGateConfigException(
      RecognitionGateConfigErrorKind.malformedValue,
      'expected a string',
      path: path,
    );
  }
}
