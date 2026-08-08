/// Deterministic persistence codec for privacy-safe Vision session summaries.
///
/// The DTO below is intentionally assembled field-by-field from
/// `VisionSessionResult`. It is not a generic domain serialization boundary:
/// adding a raw-media field to a domain type cannot make it to disk unless this
/// explicit allowlist is changed and its privacy-snapshot test is updated.
library;

import 'dart:convert';

import '../../../../core/foundation/json_validation.dart';
import '../../application/calibration_loss_machine.dart';
import '../../domain/feedback/feedback_policy.dart';
import '../../domain/feedback/insight_code.dart';
import '../../domain/quality/vision_frame_quality.dart';
import '../../domain/vision_session_result.dart';

/// Current schema version of one item inside the history document.
const int visionSessionShapeSchemaVersion = 1;

/// Persisted, aggregate-only representation of a completed Vision session.
final class VisionSessionHistoryEntry {
  VisionSessionHistoryEntry({
    required this.sessionId,
    required DateTime startedAt,
    required DateTime endedAt,
    required this.endReason,
    required this.quality,
    required this.calibrationState,
    required List<VisionInsightSnapshot> insights,
    required this.observedFrameCount,
  }) : startedAt = startedAt.toUtc(),
       endedAt = endedAt.toUtc(),
       insights = List<VisionInsightSnapshot>.unmodifiable(insights) {
    if (sessionId.trim().isEmpty || observedFrameCount < 0) {
      throw ArgumentError(
        'A session id and non-negative frame count are required.',
      );
    }
  }

  final String sessionId;
  final DateTime startedAt;
  final DateTime endedAt;
  final VisionSessionEndReason endReason;
  final VisionQualitySnapshot quality;
  final CalibrationLossState calibrationState;
  final List<VisionInsightSnapshot> insights;
  final int observedFrameCount;
}

/// Enum-only quality aggregate. Numeric per-frame measurements are excluded.
final class VisionQualitySnapshot {
  const VisionQualitySnapshot({
    required this.frameCount,
    required this.framing,
    required this.lighting,
    required this.blur,
    required this.stability,
    required this.roiCoverage,
    required this.overall,
    required this.setupCue,
  });

  final int frameCount;
  final VisionMetricState framing;
  final VisionLighting lighting;
  final VisionMetricState blur;
  final VisionMetricState stability;
  final VisionMetricState roiCoverage;
  final VisionMetricState overall;
  final VisionSetupCue setupCue;
}

/// The allowlisted, non-raw portion of one feedback insight.
final class VisionInsightSnapshot {
  VisionInsightSnapshot({
    required this.code,
    required this.policyVersion,
    required List<String> evidenceIds,
    required this.confidence,
    required this.priority,
    required this.direction,
    required this.capability,
  }) : evidenceIds = List<String>.unmodifiable(evidenceIds) {
    if (policyVersion.trim().isEmpty ||
        evidenceIds.isEmpty ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1) {
      throw ArgumentError('A valid insight snapshot is required.');
    }
  }

  final InsightCode code;
  final String policyVersion;
  final List<String> evidenceIds;
  final double confidence;
  final int priority;
  final InsightDirection direction;
  final FeedbackCapability capability;
}

/// Stateless codec with a forward-compatible shape-version dispatch.
final class VisionSessionCodec {
  const VisionSessionCodec();

  static const int currentSchemaVersion = visionSessionShapeSchemaVersion;

  VisionSessionHistoryEntry fromResult(VisionSessionResult result) =>
      VisionSessionHistoryEntry(
        sessionId: result.session.id.value,
        startedAt: result.session.startedAt,
        endedAt: result.endedAt,
        endReason: result.endReason,
        quality: VisionQualitySnapshot(
          frameCount: result.qualitySummary.frameCount,
          framing: result.qualitySummary.framing,
          lighting: result.qualitySummary.lighting,
          blur: result.qualitySummary.blur,
          stability: result.qualitySummary.stability,
          roiCoverage: result.qualitySummary.roiCoverage,
          overall: result.qualitySummary.overall,
          setupCue: result.qualitySummary.setupCue,
        ),
        calibrationState: result.calibrationState,
        insights: result.sessionSummary
            .map(
              (insight) => VisionInsightSnapshot(
                code: insight.code,
                policyVersion: insight.policyVersion,
                evidenceIds: insight.evidenceIds,
                confidence: insight.confidence,
                priority: insight.priority,
                direction: insight.direction,
                capability:
                    FeedbackPolicies.catalog[insight.code]!.requiredCapability,
              ),
            )
            .toList(growable: false),
        observedFrameCount: result.observedFrameCount,
      );

  /// JSON-ready map with canonical insertion order.
  Map<String, dynamic> encodeToMap(VisionSessionHistoryEntry entry) =>
      _encodeEntry(entry);

  List<int> encode(VisionSessionHistoryEntry entry) =>
      utf8.encode(jsonEncode(encodeToMap(entry)));

  VisionSessionHistoryEntry decodeFromMap(Object? json) {
    final map = requireObject(json);
    final version = _readShapeVersion(map);
    return _decodeCurrent(_migrateToCurrent(map, version));
  }

  static int _readShapeVersion(Map<String, dynamic> json) {
    final value = json['schemaVersion'];
    if (value is! int) {
      throw JsonRecordException(
        RecordDecodeReason.notANumber,
        field: 'schemaVersion',
      );
    }
    return value;
  }

  Map<String, dynamic> _migrateToCurrent(
    Map<String, dynamic> json,
    int version,
  ) {
    switch (version) {
      case currentSchemaVersion:
        return json;
      default:
        throw JsonRecordException(
          RecordDecodeReason.unknownEnum,
          field: 'schemaVersion',
        );
    }
  }

  static Map<String, dynamic> _encodeEntry(VisionSessionHistoryEntry entry) =>
      <String, dynamic>{
        'schemaVersion': currentSchemaVersion,
        'sessionId': entry.sessionId,
        'startedAt': entry.startedAt.toIso8601String(),
        'endedAt': entry.endedAt.toIso8601String(),
        'endReason': entry.endReason.name,
        'quality': <String, dynamic>{
          'frameCount': entry.quality.frameCount,
          'framing': entry.quality.framing.name,
          'lighting': entry.quality.lighting.name,
          'blur': entry.quality.blur.name,
          'stability': entry.quality.stability.name,
          'roiCoverage': entry.quality.roiCoverage.name,
          'overall': entry.quality.overall.name,
          'setupCue': entry.quality.setupCue.name,
        },
        'calibrationState': entry.calibrationState.name,
        'insights': <Map<String, dynamic>>[
          for (final insight in entry.insights)
            <String, dynamic>{
              'code': insight.code.name,
              'policyVersion': insight.policyVersion,
              'evidenceIds': insight.evidenceIds,
              'confidence': insight.confidence,
              'priority': insight.priority,
              'direction': insight.direction.name,
              'capability': insight.capability.name,
            },
        ],
        'observedFrameCount': entry.observedFrameCount,
      };

  VisionSessionHistoryEntry _decodeCurrent(Map<String, dynamic> json) {
    final quality = requireObject(json['quality']);
    final insights = json['insights'];
    if (insights is! List) {
      throw JsonRecordException(RecordDecodeReason.notAList, field: 'insights');
    }
    return VisionSessionHistoryEntry(
      sessionId: requireString(json, 'sessionId'),
      startedAt: requireDateTime(json, 'startedAt'),
      endedAt: requireDateTime(json, 'endedAt'),
      endReason: _enumByName(
        VisionSessionEndReason.values,
        requireString(json, 'endReason'),
        'endReason',
      ),
      quality: VisionQualitySnapshot(
        frameCount: requireInt(quality, 'frameCount', min: 0),
        framing: _enumByName(
          VisionMetricState.values,
          requireString(quality, 'framing'),
          'quality.framing',
        ),
        lighting: _enumByName(
          VisionLighting.values,
          requireString(quality, 'lighting'),
          'quality.lighting',
        ),
        blur: _enumByName(
          VisionMetricState.values,
          requireString(quality, 'blur'),
          'quality.blur',
        ),
        stability: _enumByName(
          VisionMetricState.values,
          requireString(quality, 'stability'),
          'quality.stability',
        ),
        roiCoverage: _enumByName(
          VisionMetricState.values,
          requireString(quality, 'roiCoverage'),
          'quality.roiCoverage',
        ),
        overall: _enumByName(
          VisionMetricState.values,
          requireString(quality, 'overall'),
          'quality.overall',
        ),
        setupCue: _enumByName(
          VisionSetupCue.values,
          requireString(quality, 'setupCue'),
          'quality.setupCue',
        ),
      ),
      calibrationState: _enumByName(
        CalibrationLossState.values,
        requireString(json, 'calibrationState'),
        'calibrationState',
      ),
      insights: <VisionInsightSnapshot>[
        for (final item in insights) _decodeInsight(requireObject(item)),
      ],
      observedFrameCount: requireInt(json, 'observedFrameCount', min: 0),
    );
  }

  VisionInsightSnapshot _decodeInsight(Map<String, dynamic> json) {
    final ids = json['evidenceIds'];
    if (ids is! List) {
      throw JsonRecordException(
        RecordDecodeReason.notAList,
        field: 'evidenceIds',
      );
    }
    return VisionInsightSnapshot(
      code: _enumByName(
        InsightCode.values,
        requireString(json, 'code'),
        'code',
      ),
      policyVersion: requireString(json, 'policyVersion'),
      evidenceIds: <String>[for (final id in ids) _requireListString(id)],
      confidence: requireDouble(json, 'confidence', min: 0, max: 1),
      priority: requireInt(json, 'priority'),
      direction: _enumByName(
        InsightDirection.values,
        requireString(json, 'direction'),
        'direction',
      ),
      capability: _enumByName(
        FeedbackCapability.values,
        requireString(json, 'capability'),
        'capability',
      ),
    );
  }

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    String name,
    String field,
  ) => values.firstWhere(
    (value) => value.name == name,
    orElse: () =>
        throw JsonRecordException(RecordDecodeReason.unknownEnum, field: field),
  );

  static String _requireListString(Object? value) {
    if (value is! String) {
      throw JsonRecordException(RecordDecodeReason.notAString);
    }
    return value;
  }
}
