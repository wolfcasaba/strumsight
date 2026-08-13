import 'dart:convert';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/export/analysis_export.dart';
import '../../public.dart';

/// Deterministic JSON boundary for the redacted [AnalysisExport] contract
/// (ADR 0247). Fields are encoded in a fixed insertion order so two exports
/// of the same document byte-for-byte match — the "no hidden randomness"
/// guarantee the round-trip test relies on.
final class AnalysisExportCodec {
  const AnalysisExportCodec();

  static const int schemaVersion = analysisExportSchemaVersion;

  String encode(AnalysisExport export) {
    if (export.exportSchemaVersion != schemaVersion) {
      throw ArgumentError.value(
        export.exportSchemaVersion,
        'export.exportSchemaVersion',
        'must be supported by this codec',
      );
    }
    final json = _exportToJson(export);
    _ensureFiniteJson(json);
    return jsonEncode(json);
  }

  AppResult<AnalysisExport> decode(String source) {
    try {
      final root = jsonDecode(source);
      return AppResult.success(_exportFromJson(_object(root)));
    } on Object {
      return const AppResult.failure(
        ValidationFailure(code: _AnalysisExportCodecFailure.invalidExport),
      );
    }
  }

  static Map<String, Object?> _exportToJson(AnalysisExport value) =>
      <String, Object?>{
        'exportSchemaVersion': value.exportSchemaVersion,
        'documentId': value.documentId,
        'createdAt': value.createdAt.toUtc().toIso8601String(),
        'mode': value.mode.name,
        'input': <String, Object?>{
          'source': value.input.source.name,
          'durationUs': value.input.duration.inMicroseconds,
          'sampleRate': value.input.sampleRate,
          'channelCount': value.input.channelCount,
        },
        'signalQuality': <String, Object?>{
          'overall': value.signalQuality.overall,
          'peakDbfs': value.signalQuality.peakDbfs,
          'rmsDbfs': value.signalQuality.rmsDbfs,
          'noiseFloorDbfs': value.signalQuality.noiseFloorDbfs,
          'clippedSampleRatio': value.signalQuality.clippedSampleRatio,
          'silentRatio': value.signalQuality.silentRatio,
          'tonalness': value.signalQuality.tonalness,
          'measured': value.signalQuality.measured,
        },
        'capabilities': value.capabilities
            .map(
              (c) => <String, Object?>{
                'capability': c.capability.name,
                'status': c.status.name,
                'confidence': c.confidence,
                'reason': c.reason?.name,
              },
            )
            .toList(),
        'metrics': value.metrics
            .map(
              (m) => <String, Object?>{
                'id': m.id,
                'version': m.version,
                'status': m.status.name,
                'confidence': m.confidence,
                'value': m.value == null ? null : _metricValueToJson(m.value!),
                'unit': m.unit,
                'sampleCount': m.sampleCount,
                'unavailableReason': m.unavailableReason?.name,
              },
            )
            .toList(),
        'hotspots': value.hotspots
            .map(
              (h) => <String, Object?>{
                'kind': h.kind.name,
                'startUs': h.start.inMicroseconds,
                'endUs': h.end.inMicroseconds,
                'severity': h.severity.name,
                'confidence': h.confidence,
              },
            )
            .toList(),
        'insights': value.insights
            .map(
              (i) => <String, Object?>{
                'id': i.id,
                'ruleId': i.ruleId,
                'ruleVersion': i.ruleVersion,
                'priority': i.priority.name,
                'kind': i.kind.name,
                'messageKey': i.messageKey,
                'messageArgs': i.messageArgs,
                'recommendedAction': i.recommendedAction.name,
              },
            )
            .toList(),
        'warnings': value.warnings
            .map(
              (w) => <String, Object?>{
                'kind': w.kind.name,
                'severity': w.severity.name,
                'messageKey': w.messageKey,
                'messageArgs': w.messageArgs,
              },
            )
            .toList(),
        'completion': <String, Object?>{
          'status': value.completion.status.name,
          'failureCode': value.completion.failureCode,
        },
      };

  static AnalysisExport _exportFromJson(Map<String, Object?> json) {
    _ensureFiniteJson(json);
    if (_int(json, 'exportSchemaVersion') != schemaVersion) {
      throw const FormatException();
    }
    final input = _fieldObject(json, 'input');
    final signalQuality = _fieldObject(json, 'signalQuality');
    final completion = _fieldObject(json, 'completion');
    return AnalysisExport(
      exportSchemaVersion: schemaVersion,
      documentId: _string(json, 'documentId'),
      createdAt: _dateTime(json, 'createdAt'),
      mode: _enumByName(_string(json, 'mode'), AnalysisMode.values),
      input: AnalysisExportInput(
        source: _enumByName(
          _string(input, 'source'),
          AnalysisInputSource.values,
        ),
        duration: Duration(microseconds: _int(input, 'durationUs')),
        sampleRate: _int(input, 'sampleRate'),
        channelCount: _int(input, 'channelCount'),
      ),
      signalQuality: AnalysisExportSignalQuality(
        overall: _double(signalQuality, 'overall'),
        peakDbfs: _double(signalQuality, 'peakDbfs'),
        rmsDbfs: _double(signalQuality, 'rmsDbfs'),
        noiseFloorDbfs: _double(signalQuality, 'noiseFloorDbfs'),
        clippedSampleRatio: _double(signalQuality, 'clippedSampleRatio'),
        silentRatio: _double(signalQuality, 'silentRatio'),
        tonalness: _double(signalQuality, 'tonalness'),
        measured: _bool(signalQuality, 'measured'),
      ),
      capabilities: _list(json, 'capabilities').map((e) {
        final c = _object(e);
        return AnalysisExportCapability(
          capability: _enumByName(
            _string(c, 'capability'),
            AnalysisCapability.values,
          ),
          status: _enumByName(_string(c, 'status'), CapabilityStatus.values),
          confidence: _double(c, 'confidence'),
          reason: _nullableEnumByName(
            _nullableString(c, 'reason'),
            CapabilityUnavailableReason.values,
          ),
        );
      }).toList(),
      metrics: _list(json, 'metrics').map((e) {
        final m = _object(e);
        return AnalysisExportMetric(
          id: _string(m, 'id'),
          version: _int(m, 'version'),
          status: _enumByName(_string(m, 'status'), CapabilityStatus.values),
          confidence: _double(m, 'confidence'),
          value: m['value'] == null
              ? null
              : _metricValueFromJson(_object(m['value'])),
          unit: _string(m, 'unit'),
          sampleCount: _int(m, 'sampleCount'),
          unavailableReason: _nullableEnumByName(
            _nullableString(m, 'unavailableReason'),
            CapabilityUnavailableReason.values,
          ),
        );
      }).toList(),
      hotspots: _list(json, 'hotspots').map((e) {
        final h = _object(e);
        return AnalysisExportHotspot(
          kind: _enumByName(_string(h, 'kind'), AnalysisHotspotKind.values),
          start: Duration(microseconds: _int(h, 'startUs')),
          end: Duration(microseconds: _int(h, 'endUs')),
          severity: _enumByName(
            _string(h, 'severity'),
            AnalysisHotspotSeverity.values,
          ),
          confidence: _double(h, 'confidence'),
        );
      }).toList(),
      insights: _list(json, 'insights').map((e) {
        final i = _object(e);
        return AnalysisExportInsight(
          id: _string(i, 'id'),
          ruleId: _string(i, 'ruleId'),
          ruleVersion: _string(i, 'ruleVersion'),
          priority: _enumByName(
            _string(i, 'priority'),
            AnalysisInsightPriority.values,
          ),
          kind: _enumByName(_string(i, 'kind'), AnalysisInsightKind.values),
          messageKey: _string(i, 'messageKey'),
          messageArgs: _stringMap(i, 'messageArgs'),
          recommendedAction: _enumByName(
            _string(i, 'recommendedAction'),
            AnalysisRecommendedAction.values,
          ),
        );
      }).toList(),
      warnings: _list(json, 'warnings').map((e) {
        final w = _object(e);
        return AnalysisExportWarning(
          kind: _enumByName(_string(w, 'kind'), AnalysisWarningKind.values),
          severity: _enumByName(
            _string(w, 'severity'),
            AnalysisWarningSeverity.values,
          ),
          messageKey: _string(w, 'messageKey'),
          messageArgs: _stringMap(w, 'messageArgs'),
        );
      }).toList(),
      completion: AnalysisExportCompletion(
        status: _enumByName(
          _string(completion, 'status'),
          AnalysisCompletionStatus.values,
        ),
        failureCode: _nullableString(completion, 'failureCode'),
      ),
    );
  }

  static Map<String, Object?> _metricValueToJson(AnalysisMetricValue value) =>
      switch (value) {
        ScalarMetricValue(:final value) => <String, Object?>{
          'type': 'scalar',
          'value': value,
        },
        PercentageMetricValue(:final value) => <String, Object?>{
          'type': 'percentage',
          'value': value,
        },
        DurationMetricValue(:final value) => <String, Object?>{
          'type': 'duration',
          'valueUs': value.inMicroseconds,
        },
        DistributionMetricValue(:final values) => <String, Object?>{
          'type': 'distribution',
          'values': values,
        },
        TimeSeriesMetricValue(:final points) => <String, Object?>{
          'type': 'timeSeries',
          'points': points
              .map(
                (e) => <String, Object?>{
                  'timeUs': e.time.inMicroseconds,
                  'value': e.value,
                },
              )
              .toList(),
        },
        CategoryMetricValue(:final value) => <String, Object?>{
          'type': 'category',
          'value': value,
        },
        ScoreMetricValue(:final value) => <String, Object?>{
          'type': 'score',
          'value': value,
        },
      };

  static AnalysisMetricValue _metricValueFromJson(Map<String, Object?> json) =>
      switch (_string(json, 'type')) {
        'scalar' => ScalarMetricValue(_double(json, 'value')),
        'percentage' => PercentageMetricValue(_double(json, 'value')),
        'duration' => DurationMetricValue(
          Duration(microseconds: _int(json, 'valueUs')),
        ),
        'distribution' => DistributionMetricValue(
          _list(json, 'values').map(_finiteDouble).toList(),
        ),
        'timeSeries' => TimeSeriesMetricValue(
          _list(json, 'points').map((e) {
            final p = _object(e);
            return MetricTimePoint(
              time: Duration(microseconds: _int(p, 'timeUs')),
              value: _double(p, 'value'),
            );
          }).toList(),
        ),
        'category' => CategoryMetricValue(_string(json, 'value')),
        'score' => ScoreMetricValue(_double(json, 'value')),
        _ => throw const FormatException(),
      };

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map) throw const FormatException();
    return Map<String, Object?>.from(value);
  }

  static Map<String, Object?> _fieldObject(
    Map<String, Object?> json,
    String key,
  ) => _object(json[key]);

  static List<Object?> _list(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! List) throw const FormatException();
    return List<Object?>.from(value);
  }

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) throw const FormatException();
    return value;
  }

  static String? _nullableString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value != null && value is! String) throw const FormatException();
    return value as String?;
  }

  static int _int(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) throw const FormatException();
    return value;
  }

  static bool _bool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! bool) throw const FormatException();
    return value;
  }

  static double _double(Map<String, Object?> json, String key) =>
      _finiteDouble(json[key]);

  static double _finiteDouble(Object? value) {
    if (value is! num || !value.isFinite) throw const FormatException();
    return value.toDouble();
  }

  static DateTime _dateTime(Map<String, Object?> json, String key) {
    final value = DateTime.tryParse(_string(json, key));
    if (value == null) throw const FormatException();
    return value.toUtc();
  }

  static T _enumByName<T extends Enum>(String name, List<T> values) =>
      values.firstWhere((value) => value.name == name);

  static T? _nullableEnumByName<T extends Enum>(String? name, List<T> values) =>
      name == null ? null : _enumByName(name, values);

  static Map<String, String> _stringMap(
    Map<String, Object?> json,
    String key,
  ) => _object(json[key]).map((key, value) {
    if (value is! String) throw const FormatException();
    return MapEntry(key, value);
  });

  /// Guards the completed JSON tree so malformed numeric metadata can never
  /// enter the exported output (mirrors [AnalysisDocumentCodec]).
  static void _ensureFiniteJson(Object? value) {
    switch (value) {
      case num() when !value.isFinite:
        throw ArgumentError.value(
          value,
          'json',
          'must not contain NaN/Infinity',
        );
      case Map<Object?, Object?>():
        for (final entry in value.entries) {
          if (entry.key is! String) {
            throw ArgumentError.value(
              entry.key,
              'json key',
              'must be a string',
            );
          }
          _ensureFiniteJson(entry.value);
        }
      case Iterable<Object?>():
        for (final entry in value) {
          _ensureFiniteJson(entry);
        }
      case null || bool() || String() || num():
        return;
      default:
        throw ArgumentError.value(value, 'json', 'must be JSON-compatible');
    }
  }
}

abstract final class _AnalysisExportCodecFailure {
  static const String invalidExport = 'analysis.export.codec.invalid';
}
