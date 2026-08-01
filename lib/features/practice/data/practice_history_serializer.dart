import 'dart:convert';

import '../../../core/foundation/json_validation.dart';
import '../domain/model/practice_history_entry.dart';
import '../domain/model/practice_metric_snapshot.dart';
import '../domain/model/practice_mode.dart';
import '../domain/model/practice_session_result.dart'
    show practiceFinishReasonFromCode;
import '../domain/model/practice_source.dart';

/// Round-trip JSON (de)serialization for [PracticeHistoryEntry].
///
/// Schema-version is the *document* version (`documentSchemaVersion`), set by
/// [JsonDocumentStore]; the per-record `schemaVersion` field gates record-level
/// upgrades inside a single document. The serializer is responsible for the
/// per-record shape; the document-level envelope is owned by `JsonDocumentStore`.
///
/// Stable invariants:
/// * `toJson → fromJson` is value-equal (A6).
/// * Every persisted enum is matched by stable `code`; unknown codes raise
///   [JsonRecordException] (fallback nélkül).
/// * [Duration] values round-trip with **microsecond** precision.
/// * Records whose `schemaVersion` is missing or higher than
///   [practiceHistorySchemaVersion] are rejected by
///   [JsonDocumentStore] before they reach this decoder.
class PracticeHistorySerializer {
  const PracticeHistorySerializer();

  /// Encode [entry] to a JSON object suitable for the [JsonCollectionStore].
  Map<String, dynamic> toJson(PracticeHistoryEntry entry) {
    return <String, dynamic>{
      'v': practiceHistorySchemaVersion,
      'id': entry.id,
      'mode': entry.modeCode,
      'source': entry.sourceCode,
      'createdAt': entry.createdAt.toUtc().toIso8601String(),
      'definitionId': entry.definitionId,
      'displayTitle': entry.displayTitle,
      'finishReason': entry.finishReasonCode,
      'activeMs': entry.activeDuration.inMicroseconds,
      'pausedMs': entry.pausedDuration.inMicroseconds,
      'attemptsCount': entry.attemptsCount,
      'final': _metricSnapshotToJson(entry.finalMetricSnapshot),
      'totalTargets': entry.totalTargets,
      'resolvedTargets': entry.resolvedTargets,
      'scorePoints': entry.scorePoints,
      'maxCombo': entry.maxCombo,
      'meanOffsetMicros': entry.meanAbsoluteOffset.inMicroseconds,
      'timingBiasMicros': entry.timingBias.inMicroseconds,
      'coachingSummary': entry.coachingSummary,
      'skillTags': entry.skillTags,
      if (entry.highestStableTempoBpm != null)
        'highestStableBpm': entry.highestStableTempoBpm,
      'details': [
        for (final detail in entry.detailAttempts) _detailToJson(detail),
      ],
    };
  }

  /// Decode one persisted record. A missing required field, a wrong shape,
  /// or a code this build does not know raises [JsonRecordException] so the
  /// [JsonCollectionStore] can skip it and keep the rest of the history.
  PracticeHistoryEntry fromJson(Map<String, dynamic> json) {
    final version = requireInt(json, 'v', min: 1);
    if (version > practiceHistorySchemaVersion) {
      // JsonDocumentStore already filters these at the document level, but the
      // record layer is the single source of truth for the version check:
      // an unknown version must not be guessed at.
      throw JsonRecordException(RecordDecodeReason.outOfRange, field: 'v');
    }
    final detailsRaw = optionalList(json, 'details') ?? const <Object?>[];
    if (detailsRaw.length > practiceHistoryDetailLimit) {
      throw JsonRecordException(RecordDecodeReason.tooLong, field: 'details');
    }

    final modeCode = requireString(json, 'mode');
    if (practiceModeFromCode(modeCode) == null) {
      throw JsonRecordException(RecordDecodeReason.unknownEnum, field: 'mode');
    }
    final sourceCode = requireString(json, 'source');
    if (practiceSourceFromCode(sourceCode) == null) {
      throw JsonRecordException(
        RecordDecodeReason.unknownEnum,
        field: 'source',
      );
    }
    final finishReasonCode = requireString(json, 'finishReason');
    if (practiceFinishReasonFromCode(finishReasonCode) == null) {
      throw JsonRecordException(
        RecordDecodeReason.unknownEnum,
        field: 'finishReason',
      );
    }

    return PracticeHistoryEntry(
      id: requireString(json, 'id'),
      modeCode: modeCode,
      sourceCode: sourceCode,
      createdAt: requireDateTime(json, 'createdAt'),
      definitionId: requireString(json, 'definitionId'),
      displayTitle: requireString(json, 'displayTitle', allowEmpty: true),
      finishReasonCode: finishReasonCode,
      activeDuration: Duration(
        microseconds: requireInt(
          json,
          'activeMs',
          min: 0,
          max: _maxDurationMicros,
        ),
      ),
      pausedDuration: Duration(
        microseconds: requireInt(
          json,
          'pausedMs',
          min: 0,
          max: _maxDurationMicros,
        ),
      ),
      attemptsCount: requireInt(json, 'attemptsCount', min: 1),
      finalMetricSnapshot: _metricSnapshotFromJson(
        requireObject(json['final'], field: 'final'),
      ),
      totalTargets: requireInt(json, 'totalTargets', min: 0),
      resolvedTargets: requireInt(json, 'resolvedTargets', min: 0),
      scorePoints: requireInt(json, 'scorePoints', min: 0),
      maxCombo: requireInt(json, 'maxCombo', min: 0),
      meanAbsoluteOffset: Duration(
        microseconds: requireInt(
          json,
          'meanOffsetMicros',
          min: 0,
          max: _maxDurationMicros,
        ),
      ),
      timingBias: Duration(
        microseconds: signedInt(
          json,
          'timingBiasMicros',
          min: -_maxDurationMicros,
          max: _maxDurationMicros,
        ),
      ),
      coachingSummary: _coachingSummaryFromJson(json),
      skillTags: _skillTagsFromJson(json),
      highestStableTempoBpm: optionalDouble(
        json,
        'highestStableBpm',
        min: tempoMinimumBpm,
        max: tempoMaximumBpm,
      ),
      detailAttempts: [
        for (final raw in detailsRaw)
          _detailFromJson(requireObject(raw, field: 'details')),
      ],
    );
  }

  // --- metric snapshot ----------------------------------------------------

  Map<String, dynamic> _metricSnapshotToJson(PracticeMetricSnapshot snapshot) {
    return <String, dynamic>{
      'completion': _dimensionToJson(snapshot.completion),
      'rhythm': _dimensionToJson(snapshot.rhythm),
      'direction': _dimensionToJson(snapshot.direction),
      'chord': _dimensionToJson(snapshot.chord),
      'overall': _dimensionToJson(snapshot.overall),
    };
  }

  PracticeMetricSnapshot _metricSnapshotFromJson(Map<String, dynamic> json) {
    return PracticeMetricSnapshot(
      completion: _dimensionFromJson(
        requireObject(json['completion'], field: 'completion'),
      ),
      rhythm: _dimensionFromJson(
        requireObject(json['rhythm'], field: 'rhythm'),
      ),
      direction: _dimensionFromJson(
        requireObject(json['direction'], field: 'direction'),
      ),
      chord: _dimensionFromJson(requireObject(json['chord'], field: 'chord')),
      overall: _dimensionFromJson(
        requireObject(json['overall'], field: 'overall'),
      ),
    );
  }

  Map<String, dynamic> _dimensionToJson(PracticeMetricDimension dimension) {
    return switch (dimension) {
      PracticeMetricDimensionAvailable(:final value) => <String, dynamic>{
        'kind': dimension.kind,
        'value': value,
      },
      PracticeMetricDimensionNotApplicable() => <String, dynamic>{
        'kind': dimension.kind,
      },
      PracticeMetricDimensionInsufficientData(:final reasonCode) =>
        <String, dynamic>{'kind': dimension.kind, 'reason': reasonCode},
    };
  }

  PracticeMetricDimension _dimensionFromJson(Map<String, dynamic> json) {
    final kind = requireString(json, 'kind');
    return switch (kind) {
      'available' => PracticeMetricDimensionAvailable(
        requireDouble(json, 'value', min: 0, max: 1),
      ),
      'notApplicable' => const PracticeMetricDimensionNotApplicable(),
      'insufficientData' => PracticeMetricDimensionInsufficientData(
        requireString(json, 'reason'),
      ),
      _ => throw JsonRecordException(
        RecordDecodeReason.unknownEnum,
        field: 'kind',
      ),
    };
  }

  // --- detail attempts ----------------------------------------------------

  Map<String, dynamic> _detailToJson(PracticeAttemptDetail detail) {
    return <String, dynamic>{
      'index': detail.index,
      'metrics': _metricSnapshotToJson(detail.metricSnapshot),
    };
  }

  PracticeAttemptDetail _detailFromJson(Map<String, dynamic> json) {
    return PracticeAttemptDetail(
      index: requireInt(json, 'index', min: 0),
      metricSnapshot: _metricSnapshotFromJson(
        requireObject(json['metrics'], field: 'metrics'),
      ),
    );
  }

  // --- string lists -------------------------------------------------------

  List<String> _coachingSummaryFromJson(Map<String, dynamic> json) {
    final raw = json['coachingSummary'];
    if (raw == null) return const <String>[];
    if (raw is! List) {
      throw JsonRecordException(
        RecordDecodeReason.notAList,
        field: 'coachingSummary',
      );
    }
    if (raw.length > 64) {
      throw JsonRecordException(
        RecordDecodeReason.tooLong,
        field: 'coachingSummary',
      );
    }
    return <String>[
      for (final entry in raw)
        if (entry is String)
          entry
        else
          throw JsonRecordException(
            RecordDecodeReason.notAString,
            field: 'coachingSummary',
          ),
    ];
  }

  List<String> _skillTagsFromJson(Map<String, dynamic> json) {
    final raw = json['skillTags'];
    if (raw == null) return const <String>[];
    if (raw is! List) {
      throw JsonRecordException(
        RecordDecodeReason.notAList,
        field: 'skillTags',
      );
    }
    if (raw.length > 32) {
      throw JsonRecordException(RecordDecodeReason.tooLong, field: 'skillTags');
    }
    return <String>[
      for (final entry in raw)
        if (entry is String)
          entry
        else
          throw JsonRecordException(
            RecordDecodeReason.notAString,
            field: 'skillTags',
          ),
    ];
  }
}

/// The contract that [PracticeHistorySerializer] assumes the rest of the
/// codebase respects. Exposed for the test suite.
const int practiceHistoryDetailLimitForTests = practiceHistoryDetailLimit;
const double tempoMinimumBpm = 30.0;
const double tempoMaximumBpm = 300.0;

// A safe upper bound for duration micros (≈ 35 years) — enough for any
// real practice session and well below Dart's `int` ceiling.
const int _maxDurationMicros = 1 << 50;

/// Optional list field: absent stays `null`, present is shape-validated.
List<Object?>? optionalList(
  Map<String, dynamic> json,
  String field, {
  int maxLength = 1 << 16,
}) {
  final value = json[field];
  if (value == null) return null;
  if (value is! List) {
    throw JsonRecordException(RecordDecodeReason.notAList, field: field);
  }
  if (value.length > maxLength) {
    throw JsonRecordException(RecordDecodeReason.tooLong, field: field);
  }
  return value;
}

/// A signed integer in [min, max]. Used for `timingBiasMicros`, which is
/// negative for early, positive for late.
int signedInt(
  Map<String, dynamic> json,
  String field, {
  required int min,
  required int max,
}) {
  final value = json[field];
  if (value == null) {
    throw JsonRecordException(RecordDecodeReason.missing, field: field);
  }
  if (value is! int) {
    // Reject doubles for the bias — its microsecond field is conceptually
    // an integer offset; coercing would let a corrupt record drift one
    // microsecond per round-trip.
    throw JsonRecordException(RecordDecodeReason.notANumber, field: field);
  }
  if (value < min || value > max) {
    throw JsonRecordException(RecordDecodeReason.outOfRange, field: field);
  }
  return value;
}

/// Defensive check that the bytes look like a JSON object. Used by tests.
bool looksLikeJsonObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>;
  } on FormatException {
    return false;
  }
}
