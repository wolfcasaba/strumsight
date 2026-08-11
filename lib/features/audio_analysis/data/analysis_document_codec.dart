import 'dart:convert';

import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../public.dart';

/// Deterministic JSON boundary for the versioned audio-analysis document.
final class AnalysisDocumentCodec {
  const AnalysisDocumentCodec();

  static const int schemaVersion = analysisDocumentSchemaVersion;

  /// Encodes fields in a fixed insertion order for byte-stable persistence.
  String encode(AnalysisDocument document) {
    if (document.schemaVersion != schemaVersion) {
      throw ArgumentError.value(
        document.schemaVersion,
        'document.schemaVersion',
        'must be supported by this codec',
      );
    }
    final json = _documentToJson(document);
    _ensureFiniteJson(json);
    return jsonEncode(json);
  }

  /// Decodes untrusted persisted JSON without letting malformed records escape.
  AppResult<AnalysisDocument> decode(String source) {
    try {
      final root = jsonDecode(source);
      return AppResult.success(_documentFromJson(_object(root)));
    } on Object {
      return const AppResult.failure(
        ValidationFailure(code: _AnalysisDocumentCodecFailure.invalidDocument),
      );
    }
  }

  static Map<String, Object?> _documentToJson(AnalysisDocument value) =>
      <String, Object?>{
        'schemaVersion': value.schemaVersion,
        'id': value.id,
        'createdAt': value.createdAt.toUtc().toIso8601String(),
        'mode': value.mode.name,
        'input': _inputToJson(value.input),
        'provenance': _provenanceToJson(value.provenance),
        'signalQuality': _signalQualityToJson(value.signalQuality),
        'capabilities': value.capabilities.map(_capabilityToJson).toList(),
        'timeline': _timelineToJson(value.timeline),
        'metrics': value.metrics.map(_metricToJson).toList(),
        'hotspots': value.hotspots.map(_hotspotToJson).toList(),
        'insights': value.insights.map(_insightToJson).toList(),
        'warnings': value.warnings.map(_warningToJson).toList(),
        'completion': _completionToJson(value.completion),
      };

  static AnalysisDocument _documentFromJson(Map<String, Object?> json) {
    _ensureFiniteJson(json);
    if (_int(json, 'schemaVersion') != schemaVersion) {
      throw const FormatException();
    }
    return AnalysisDocument(
      id: _string(json, 'id'),
      schemaVersion: schemaVersion,
      createdAt: _dateTime(json, 'createdAt'),
      mode: _enumByName(_string(json, 'mode'), AnalysisMode.values),
      input: _inputFromJson(_fieldObject(json, 'input')),
      provenance: _provenanceFromJson(_fieldObject(json, 'provenance')),
      signalQuality: _signalQualityFromJson(
        _fieldObject(json, 'signalQuality'),
      ),
      capabilities: _list(
        json,
        'capabilities',
      ).map((e) => _capabilityFromJson(_object(e))).toList(),
      timeline: _timelineFromJson(_fieldObject(json, 'timeline')),
      metrics: _list(
        json,
        'metrics',
      ).map((e) => _metricFromJson(_object(e))).toList(),
      hotspots: _list(
        json,
        'hotspots',
      ).map((e) => _hotspotFromJson(_object(e))).toList(),
      insights: _list(
        json,
        'insights',
      ).map((e) => _insightFromJson(_object(e))).toList(),
      warnings: _list(
        json,
        'warnings',
      ).map((e) => _warningFromJson(_object(e))).toList(),
      completion: _completionFromJson(_fieldObject(json, 'completion')),
    );
  }

  static Map<String, Object?> _inputToJson(AnalysisInputSummary value) =>
      <String, Object?>{
        'source': value.source.name,
        'durationUs': value.duration.inMicroseconds,
        'sampleRate': value.sampleRate,
        'channelCount': value.channelCount,
        'fingerprint': value.fingerprint,
        'sourceName': value.sourceName,
        'originalAudioRetained': value.originalAudioRetained,
      };

  static AnalysisInputSummary _inputFromJson(Map<String, Object?> json) =>
      AnalysisInputSummary(
        source: _enumByName(
          _string(json, 'source'),
          AnalysisInputSource.values,
        ),
        duration: Duration(microseconds: _int(json, 'durationUs')),
        sampleRate: _int(json, 'sampleRate'),
        channelCount: _int(json, 'channelCount'),
        fingerprint: _string(json, 'fingerprint'),
        sourceName: _nullableString(json, 'sourceName'),
        originalAudioRetained: _bool(json, 'originalAudioRetained'),
      );

  static Map<String, Object?> _provenanceToJson(AnalysisProvenance value) =>
      <String, Object?>{
        'appVersion': value.appVersion,
        'analyzerVersion': value.analyzerVersion,
        'pipelineVersion': value.pipelineVersion,
        'stageVersions': value.stageVersions,
        'dspConfigHash': value.dspConfigHash,
        'modelManifestIds': value.modelManifestIds,
        'inputFingerprint': value.inputFingerprint,
        'platform': value.platform,
        'targetVersion': value.targetVersion,
        'featureFlagSnapshot': value.featureFlagSnapshot,
      };

  static AnalysisProvenance _provenanceFromJson(Map<String, Object?> json) =>
      AnalysisProvenance(
        appVersion: _string(json, 'appVersion'),
        analyzerVersion: _string(json, 'analyzerVersion'),
        pipelineVersion: _string(json, 'pipelineVersion'),
        stageVersions: _stringMap(json, 'stageVersions'),
        dspConfigHash: _string(json, 'dspConfigHash'),
        modelManifestIds: _stringList(json, 'modelManifestIds'),
        inputFingerprint: _string(json, 'inputFingerprint'),
        platform: _string(json, 'platform'),
        targetVersion: _nullableString(json, 'targetVersion'),
        featureFlagSnapshot: _boolMap(json, 'featureFlagSnapshot'),
      );

  static Map<String, Object?> _signalQualityToJson(SignalQualityReport value) =>
      <String, Object?>{
        'overall': value.overall,
        'peakDbfs': value.peakDbfs,
        'rmsDbfs': value.rmsDbfs,
        'noiseFloorDbfs': value.noiseFloorDbfs,
        'clippedSampleRatio': value.clippedSampleRatio,
        'silentRatio': value.silentRatio,
        'tonalness': value.tonalness,
        'measured': value.measured,
        'warnings': value.warnings.map(_warningToJson).toList(),
      };

  static SignalQualityReport _signalQualityFromJson(
    Map<String, Object?> json,
  ) => SignalQualityReport(
    overall: _double(json, 'overall'),
    peakDbfs: _double(json, 'peakDbfs'),
    rmsDbfs: _double(json, 'rmsDbfs'),
    noiseFloorDbfs: _double(json, 'noiseFloorDbfs'),
    clippedSampleRatio: _double(json, 'clippedSampleRatio'),
    silentRatio: _double(json, 'silentRatio'),
    tonalness: _double(json, 'tonalness'),
    measured: json.containsKey('measured') ? _bool(json, 'measured') : true,
    warnings: _list(
      json,
      'warnings',
    ).map((e) => _warningFromJson(_object(e))).toList(),
  );

  static Map<String, Object?> _capabilityToJson(CapabilityReport value) =>
      <String, Object?>{
        'capability': value.capability.name,
        'status': value.status.name,
        'confidence': value.confidence,
        'reason': value.reason?.name,
        'details': value.details,
      };

  static CapabilityReport _capabilityFromJson(Map<String, Object?> json) =>
      CapabilityReport(
        capability: _enumByName(
          _string(json, 'capability'),
          AnalysisCapability.values,
        ),
        status: _enumByName(_string(json, 'status'), CapabilityStatus.values),
        confidence: _double(json, 'confidence'),
        reason: _nullableEnumByName(
          _nullableString(json, 'reason'),
          CapabilityUnavailableReason.values,
        ),
        details: _details(json, 'details'),
      );

  static Map<String, Object?> _timelineToJson(AnalysisTimeline value) =>
      <String, Object?>{
        'durationUs': value.duration.inMicroseconds,
        'events': value.events.map(_eventToJson).toList(),
        'chordSegments': value.chordSegments.map(_chordSegmentToJson).toList(),
        'beats': value.beats.map(_beatToJson).toList(),
        'barsUs': value.bars.map((e) => e.inMicroseconds).toList(),
        'tempoPoints': value.tempoPoints
            .map(
              (e) => <String, Object?>{
                'timeUs': e.time.inMicroseconds,
                'bpm': e.bpm,
              },
            )
            .toList(),
        'pitchSegments': value.pitchSegments.map(_pitchSegmentToJson).toList(),
        'dynamicPoints': value.dynamicPoints
            .map(
              (e) => <String, Object?>{
                'timeUs': e.time.inMicroseconds,
                'dbfs': e.dbfs,
              },
            )
            .toList(),
      };

  static AnalysisTimeline _timelineFromJson(Map<String, Object?> json) =>
      AnalysisTimeline(
        duration: Duration(microseconds: _int(json, 'durationUs')),
        events: _list(
          json,
          'events',
        ).map((e) => _eventFromJson(_object(e))).toList(),
        chordSegments: _list(
          json,
          'chordSegments',
        ).map((e) => _chordSegmentFromJson(_object(e))).toList(),
        beats: _list(
          json,
          'beats',
        ).map((e) => _beatFromJson(_object(e))).toList(),
        bars: _list(
          json,
          'barsUs',
        ).map((e) => Duration(microseconds: _intValue(e))).toList(),
        tempoPoints: _list(json, 'tempoPoints').map((e) {
          final p = _object(e);
          return TempoPoint(
            time: Duration(microseconds: _int(p, 'timeUs')),
            bpm: _double(p, 'bpm'),
          );
        }).toList(),
        pitchSegments: _list(
          json,
          'pitchSegments',
        ).map((e) => _pitchSegmentFromJson(_object(e))).toList(),
        dynamicPoints: _list(json, 'dynamicPoints').map((e) {
          final p = _object(e);
          return DynamicPoint(
            time: Duration(microseconds: _int(p, 'timeUs')),
            dbfs: _double(p, 'dbfs'),
          );
        }).toList(),
      );

  static Map<String, Object?> _eventToJson(AnalysisEvent value) {
    final json = _eventBaseToJson(value);
    switch (value) {
      case OnsetEvent():
        json['type'] = 'onset';
      case StrumEvent(:final direction):
        json
          ..['type'] = 'strum'
          ..['direction'] = direction.name;
      case ChordChangeEvent(:final label):
        json
          ..['type'] = 'chordChange'
          ..['label'] = label;
      case BeatEvent(:final beatIndex):
        json
          ..['type'] = 'beat'
          ..['beatIndex'] = beatIndex;
      case NoteOnsetEvent(:final midiNote):
        json
          ..['type'] = 'noteOnset'
          ..['midiNote'] = midiNote;
      case SilenceRegionEvent(:final end):
        json
          ..['type'] = 'silenceRegion'
          ..['endUs'] = end.inMicroseconds;
      case ClippingRegionEvent(:final end):
        json
          ..['type'] = 'clippingRegion'
          ..['endUs'] = end.inMicroseconds;
    }
    return json;
  }

  static Map<String, Object?> _eventBaseToJson(AnalysisEvent value) =>
      <String, Object?>{
        'id': value.id,
        'timeUs': value.time.inMicroseconds,
        'confidence': value.confidence,
        'sampleIndex': value.sampleIndex,
      };

  static AnalysisEvent _eventFromJson(Map<String, Object?> json) {
    final id = _string(json, 'id');
    final time = Duration(microseconds: _int(json, 'timeUs'));
    final confidence = _double(json, 'confidence');
    final sampleIndex = _nullableInt(json, 'sampleIndex');
    return switch (_string(json, 'type')) {
      'onset' => OnsetEvent(
        id: id,
        time: time,
        confidence: confidence,
        sampleIndex: sampleIndex,
      ),
      'strum' => StrumEvent(
        id: id,
        time: time,
        confidence: confidence,
        sampleIndex: sampleIndex,
        direction: _enumByName(
          _string(json, 'direction'),
          StrumDirection.values,
        ),
      ),
      'chordChange' => ChordChangeEvent(
        id: id,
        time: time,
        confidence: confidence,
        sampleIndex: sampleIndex,
        label: _string(json, 'label'),
      ),
      'beat' => BeatEvent(
        id: id,
        time: time,
        confidence: confidence,
        sampleIndex: sampleIndex,
        beatIndex: _int(json, 'beatIndex'),
      ),
      'noteOnset' => NoteOnsetEvent(
        id: id,
        time: time,
        confidence: confidence,
        sampleIndex: sampleIndex,
        midiNote: _int(json, 'midiNote'),
      ),
      'silenceRegion' => SilenceRegionEvent(
        id: id,
        time: time,
        confidence: confidence,
        sampleIndex: sampleIndex,
        end: Duration(microseconds: _int(json, 'endUs')),
      ),
      'clippingRegion' => ClippingRegionEvent(
        id: id,
        time: time,
        confidence: confidence,
        sampleIndex: sampleIndex,
        end: Duration(microseconds: _int(json, 'endUs')),
      ),
      _ => throw const FormatException(),
    };
  }

  static Map<String, Object?> _chordSegmentToJson(ChordSegment value) =>
      <String, Object?>{
        'startUs': value.start.inMicroseconds,
        'endUs': value.end.inMicroseconds,
        'confidence': value.confidence,
        'label': value.label,
      };
  static ChordSegment _chordSegmentFromJson(Map<String, Object?> json) =>
      ChordSegment(
        start: Duration(microseconds: _int(json, 'startUs')),
        end: Duration(microseconds: _int(json, 'endUs')),
        confidence: _double(json, 'confidence'),
        label: _string(json, 'label'),
      );
  static Map<String, Object?> _pitchSegmentToJson(PitchSegment value) =>
      <String, Object?>{
        'startUs': value.start.inMicroseconds,
        'endUs': value.end.inMicroseconds,
        'confidence': value.confidence,
        'midiNote': value.midiNote,
      };
  static PitchSegment _pitchSegmentFromJson(Map<String, Object?> json) =>
      PitchSegment(
        start: Duration(microseconds: _int(json, 'startUs')),
        end: Duration(microseconds: _int(json, 'endUs')),
        confidence: _double(json, 'confidence'),
        midiNote: _int(json, 'midiNote'),
      );
  static Map<String, Object?> _beatToJson(BeatEvent value) => <String, Object?>{
    'id': value.id,
    'timeUs': value.time.inMicroseconds,
    'confidence': value.confidence,
    'sampleIndex': value.sampleIndex,
    'beatIndex': value.beatIndex,
  };
  static BeatEvent _beatFromJson(Map<String, Object?> json) => BeatEvent(
    id: _string(json, 'id'),
    time: Duration(microseconds: _int(json, 'timeUs')),
    confidence: _double(json, 'confidence'),
    sampleIndex: _nullableInt(json, 'sampleIndex'),
    beatIndex: _int(json, 'beatIndex'),
  );

  static Map<String, Object?> _metricToJson(AnalysisMetricResult value) =>
      <String, Object?>{
        'id': value.id,
        'version': value.version,
        'status': value.status.name,
        'confidence': value.confidence,
        'value': value.value == null ? null : _metricValueToJson(value.value!),
        'unit': value.unit,
        'sampleCount': value.sampleCount,
        'evidence': value.evidence,
        'unavailableReason': value.unavailableReason?.name,
      };

  static AnalysisMetricResult _metricFromJson(Map<String, Object?> json) =>
      AnalysisMetricResult(
        id: _string(json, 'id'),
        version: _int(json, 'version'),
        status: _enumByName(_string(json, 'status'), CapabilityStatus.values),
        confidence: _double(json, 'confidence'),
        value: json['value'] == null
            ? null
            : _metricValueFromJson(_object(json['value'])),
        unit: _string(json, 'unit'),
        sampleCount: _int(json, 'sampleCount'),
        evidence: _stringList(json, 'evidence'),
        unavailableReason: _nullableEnumByName(
          _nullableString(json, 'unavailableReason'),
          CapabilityUnavailableReason.values,
        ),
      );

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

  static Map<String, Object?> _hotspotToJson(AnalysisHotspot value) =>
      <String, Object?>{
        'id': value.id,
        'kind': value.kind.name,
        'startUs': value.start.inMicroseconds,
        'endUs': value.end.inMicroseconds,
        'severity': value.severity.name,
        'confidence': value.confidence,
        'metricIds': value.metricIds,
        'evidenceIds': value.evidenceIds,
      };
  static AnalysisHotspot _hotspotFromJson(Map<String, Object?> json) =>
      AnalysisHotspot(
        id: _string(json, 'id'),
        kind: _enumByName(_string(json, 'kind'), AnalysisHotspotKind.values),
        start: Duration(microseconds: _int(json, 'startUs')),
        end: Duration(microseconds: _int(json, 'endUs')),
        severity: _enumByName(
          _string(json, 'severity'),
          AnalysisHotspotSeverity.values,
        ),
        confidence: _double(json, 'confidence'),
        metricIds: _stringList(json, 'metricIds'),
        evidenceIds: _stringList(json, 'evidenceIds'),
      );
  static Map<String, Object?> _insightToJson(AnalysisInsight value) =>
      <String, Object?>{
        'id': value.id,
        'ruleId': value.ruleId,
        'ruleVersion': value.ruleVersion,
        'priority': value.priority.name,
        'kind': value.kind.name,
        'factIds': value.factIds,
        'messageKey': value.messageKey,
        'messageArgs': value.messageArgs,
        'recommendedAction': value.recommendedAction.name,
      };
  static AnalysisInsight _insightFromJson(Map<String, Object?> json) =>
      AnalysisInsight(
        id: _string(json, 'id'),
        ruleId: _string(json, 'ruleId'),
        ruleVersion: _string(json, 'ruleVersion'),
        priority: _enumByName(
          _string(json, 'priority'),
          AnalysisInsightPriority.values,
        ),
        kind: _enumByName(_string(json, 'kind'), AnalysisInsightKind.values),
        factIds: _stringList(json, 'factIds'),
        messageKey: _string(json, 'messageKey'),
        messageArgs: _stringMap(json, 'messageArgs'),
        recommendedAction: _enumByName(
          _string(json, 'recommendedAction'),
          AnalysisRecommendedAction.values,
        ),
      );
  static Map<String, Object?> _warningToJson(AnalysisWarning value) =>
      <String, Object?>{
        'kind': value.kind.name,
        'severity': value.severity.name,
        'messageKey': value.messageKey,
        'messageArgs': value.messageArgs,
      };
  static AnalysisWarning _warningFromJson(Map<String, Object?> json) =>
      AnalysisWarning(
        kind: _enumByName(_string(json, 'kind'), AnalysisWarningKind.values),
        severity: _enumByName(
          _string(json, 'severity'),
          AnalysisWarningSeverity.values,
        ),
        messageKey: _string(json, 'messageKey'),
        messageArgs: _stringMap(json, 'messageArgs'),
      );
  static Map<String, Object?> _completionToJson(AnalysisCompletion value) =>
      <String, Object?>{
        'status': value.status.name,
        'failureCode': value.failureCode,
      };
  static AnalysisCompletion _completionFromJson(Map<String, Object?> json) =>
      AnalysisCompletion(
        status: _enumByName(
          _string(json, 'status'),
          AnalysisCompletionStatus.values,
        ),
        failureCode: _nullableString(json, 'failureCode'),
      );

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

  static int _int(Map<String, Object?> json, String key) =>
      _intValue(json[key]);
  static int _intValue(Object? value) {
    if (value is! int) throw const FormatException();
    return value;
  }

  static int? _nullableInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value != null && value is! int) throw const FormatException();
    return value as int?;
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
  static List<String> _stringList(Map<String, Object?> json, String key) =>
      _list(json, key).map((value) {
        if (value is! String) throw const FormatException();
        return value;
      }).toList();
  static Map<String, String> _stringMap(
    Map<String, Object?> json,
    String key,
  ) => _object(json[key]).map((key, value) {
    if (value is! String) throw const FormatException();
    return MapEntry(key, value);
  });
  static Map<String, bool> _boolMap(Map<String, Object?> json, String key) =>
      _object(json[key]).map((key, value) {
        if (value is! bool) throw const FormatException();
        return MapEntry(key, value);
      });
  static Map<String, Object?> _details(Map<String, Object?> json, String key) =>
      _object(json[key]);

  /// Domain constructors guard most measurements, but a capability's detail
  /// bag is intentionally open-ended. Validate the completed JSON tree here
  /// so malformed numeric metadata can never enter persisted output.
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

abstract final class _AnalysisDocumentCodecFailure {
  static const String invalidDocument = 'analysis.document.codec.invalid';
}
