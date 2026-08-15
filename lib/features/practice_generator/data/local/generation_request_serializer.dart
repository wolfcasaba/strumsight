/// Round-trip JSON codec for [PracticeGenerationRequest], with upward-only
/// schema migration (ADR 0259 §4).
library;

import '../../domain/id/planner_ids.dart' show GoalId;
import '../../domain/model/learner_constraints.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/practice_generation_request.dart';
import '../../domain/model/practice_goal.dart';
import '../../domain/model/weekly_availability.dart';

/// Stable, machine-readable codes for [GenerationRequestSerializerException].
abstract final class GenerationRequestSerializerErrorCode {
  static const String schemaVersionMissing =
      'generationRequest.serializer.schemaVersion.missing';

  /// Either newer than the code knows, or older than migration reaches back
  /// to — both are a controlled rejection, never a best-effort read.
  static const String schemaVersionUnknown =
      'generationRequest.serializer.schemaVersion.unknown';
  static const String idMissing = 'generationRequest.serializer.id.missing';
  static const String createdAtMissing =
      'generationRequest.serializer.createdAt.missing';
  static const String createdAtInvalid =
      'generationRequest.serializer.createdAt.invalid';
  static const String localeMissing =
      'generationRequest.serializer.locale.missing';
  static const String generationModeMissing =
      'generationRequest.serializer.generationMode.missing';
  static const String planHorizonInvalid =
      'generationRequest.serializer.planHorizonDays.invalid';
  static const String goalsInvalid =
      'generationRequest.serializer.goals.invalid';
  static const String availabilityInvalid =
      'generationRequest.serializer.availability.invalid';
  static const String constraintsInvalid =
      'generationRequest.serializer.constraints.invalid';
  static const String requestInvalid =
      'generationRequest.serializer.request.invalid';
}

/// Thrown by [GenerationRequestSerializer] on any malformed, corrupt, or
/// unrecognised-schema payload. Always carries a stable [code]; never the
/// offending value — a request can carry a user note.
class GenerationRequestSerializerException implements Exception {
  GenerationRequestSerializerException(this.code, {this.field});

  final String code;
  final String? field;

  @override
  String toString() =>
      'GenerationRequestSerializerException($code'
      '${field == null ? '' : ', field: $field'})';
}

/// Round-trip JSON codec for [PracticeGenerationRequest].
///
/// - [currentSchemaVersion] is what [toJson] always writes and what
///   [fromJson] always returns in memory: a decoded request is never left
///   half-migrated.
/// - A document at [oldestSupportedSchemaVersion] migrates forward
///   transparently (see [_migrateV1ToV2]).
/// - A document newer than [currentSchemaVersion] is a controlled
///   [GenerationRequestSerializerException] — never a best-effort read
///   (ADR 0259 §4, mirrors ADR 0257 §4's unknown-enum-code policy).
class GenerationRequestSerializer {
  const GenerationRequestSerializer();

  /// The schema version this build writes and reads natively.
  static const int currentSchemaVersion = 2;

  /// The oldest schema version this build can still migrate from.
  static const int oldestSupportedSchemaVersion = 1;

  Map<String, dynamic> toJson(PracticeGenerationRequest request) =>
      <String, dynamic>{
        'schemaVersion': currentSchemaVersion,
        ..._bodyToJson(request),
      };

  PracticeGenerationRequest fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.schemaVersionMissing,
        field: 'schemaVersion',
      );
    }
    if (schemaVersion > currentSchemaVersion ||
        schemaVersion < oldestSupportedSchemaVersion) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.schemaVersionUnknown,
        field: 'schemaVersion',
      );
    }
    final body = schemaVersion == oldestSupportedSchemaVersion
        ? _migrateV1ToV2(json)
        : json;
    try {
      return _bodyFromJson(body);
    } on ArgumentError catch (e) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.requestInvalid,
        field: e.name ?? 'body',
      );
    }
  }

  // ---------------------------------------------------------------------
  // v1 -> v2 migration
  // ---------------------------------------------------------------------

  /// v1 named the mode field `mode` (not `generationMode`) and expressed
  /// the horizon in whole `horizonWeeks` (not `planHorizonDays`); every
  /// other field is unchanged. This is a real content transformation, not a
  /// version-number relabel.
  Map<String, dynamic> _migrateV1ToV2(Map<String, dynamic> json) {
    final modeRaw = json['mode'];
    final horizonWeeksRaw = json['horizonWeeks'];
    if (modeRaw is! String) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.generationModeMissing,
        field: 'mode',
      );
    }
    if (horizonWeeksRaw is! num) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.planHorizonInvalid,
        field: 'horizonWeeks',
      );
    }
    final migrated = Map<String, dynamic>.of(json)
      ..remove('mode')
      ..remove('horizonWeeks');
    migrated['generationMode'] = modeRaw;
    migrated['planHorizonDays'] = (horizonWeeksRaw * 7).round();
    return migrated;
  }

  // ---------------------------------------------------------------------
  // v2 body
  // ---------------------------------------------------------------------

  Map<String, dynamic> _bodyToJson(PracticeGenerationRequest request) =>
      <String, dynamic>{
        'id': request.id.toJson(),
        'createdAt': request.createdAt.toIso8601String(),
        'locale': request.locale,
        'generationMode': request.generationMode.code,
        'planHorizonDays': request.planHorizonDays,
        'goals': <Map<String, dynamic>>[
          for (final goal in request.goals) _goalToJson(goal),
        ],
        'availability': <Map<String, dynamic>>[
          for (final day in request.availability.days)
            _dailyAvailabilityToJson(day),
        ],
        'constraints': <Map<String, dynamic>>[
          for (final constraint in request.constraints.constraints)
            _constraintToJson(constraint),
        ],
      };

  PracticeGenerationRequest _bodyFromJson(Map<String, dynamic> json) {
    final idValue = json['id'];
    if (idValue is! String) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.idMissing,
        field: 'id',
      );
    }
    final createdAtRaw = json['createdAt'];
    if (createdAtRaw is! String) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.createdAtMissing,
        field: 'createdAt',
      );
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.createdAtInvalid,
        field: 'createdAt',
      );
    }
    final locale = json['locale'];
    if (locale is! String || locale.trim().isEmpty) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.localeMissing,
        field: 'locale',
      );
    }
    final modeCode = json['generationMode'];
    if (modeCode is! String) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.generationModeMissing,
        field: 'generationMode',
      );
    }
    final GenerationMode generationMode;
    try {
      generationMode = GenerationMode.fromCode(modeCode);
    } on ArgumentError {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.generationModeMissing,
        field: 'generationMode',
      );
    }
    final horizonRaw = json['planHorizonDays'];
    if (horizonRaw is! num || horizonRaw < 1) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.planHorizonInvalid,
        field: 'planHorizonDays',
      );
    }
    final goalsRaw = json['goals'];
    if (goalsRaw is! List) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.goalsInvalid,
        field: 'goals',
      );
    }
    final availabilityRaw = json['availability'];
    if (availabilityRaw is! List) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.availabilityInvalid,
        field: 'availability',
      );
    }
    final constraintsRaw = json['constraints'];
    if (constraintsRaw is! List) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.constraintsInvalid,
        field: 'constraints',
      );
    }

    return PracticeGenerationRequest(
      id: GenerationRequestId.fromJson(idValue),
      createdAt: createdAt,
      locale: locale,
      generationMode: generationMode,
      planHorizonDays: horizonRaw.round(),
      availability: WeeklyAvailability(<DailyAvailability>[
        for (final entry in availabilityRaw)
          _dailyAvailabilityFromJson(_asMap(entry)),
      ]),
      constraints: LearnerConstraints(<LearnerConstraint>[
        for (final entry in constraintsRaw) _constraintFromJson(_asMap(entry)),
      ]),
      goals: <PracticeGoal>[
        for (final entry in goalsRaw) _goalFromJson(_asMap(entry)),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Goal
  // ---------------------------------------------------------------------

  Map<String, dynamic> _goalToJson(PracticeGoal goal) => <String, dynamic>{
    'id': goal.id.value,
    'type': goal.type.code,
    'priority': goal.priority.code,
    'status': goal.status.code,
    'createdAt': goal.createdAt.toIso8601String(),
    'targetDate': goal.targetDate == null
        ? null
        : _dateToJson(goal.targetDate!),
    'skillIds': goal.skillIds,
    'songReference': goal.songReference,
    'metricTarget': goal.metricTarget == null
        ? null
        : _metricTargetToJson(goal.metricTarget!),
    'userNote': goal.userNote,
    'normalizedTargetId': goal.normalizedTargetId,
  };

  PracticeGoal _goalFromJson(Map<String, dynamic> json) {
    final idValue = json['id'];
    final typeCode = json['type'];
    final priorityCode = json['priority'];
    final statusCode = json['status'];
    final createdAtRaw = json['createdAt'];
    if (idValue is! String ||
        typeCode is! String ||
        priorityCode is! String ||
        statusCode is! String ||
        createdAtRaw is! String) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.goalsInvalid,
        field: 'goals',
      );
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.goalsInvalid,
        field: 'goals.createdAt',
      );
    }
    final targetDateRaw = json['targetDate'];
    final metricTargetRaw = json['metricTarget'];
    return PracticeGoal(
      id: GoalId(idValue),
      type: PracticeGoalType.fromCode(typeCode),
      priority: GoalPriority.fromCode(priorityCode),
      status: PracticeGoalStatus.fromCode(statusCode),
      createdAt: createdAt,
      targetDate: targetDateRaw is String ? _dateFromJson(targetDateRaw) : null,
      skillIds: <String>[
        for (final entry in (json['skillIds'] as List?) ?? const <Object?>[])
          if (entry is String) entry,
      ],
      songReference: json['songReference'] as String?,
      metricTarget: metricTargetRaw is Map
          ? _metricTargetFromJson(_asMap(metricTargetRaw))
          : null,
      userNote: json['userNote'] as String?,
      normalizedTargetId: json['normalizedTargetId'] as String?,
    );
  }

  Map<String, dynamic> _metricTargetToJson(MetricTarget target) =>
      <String, dynamic>{
        'metricCode': target.metricCode,
        'direction': target.direction.code,
        'threshold': target.threshold,
        'measurementCapability': target.measurementCapability,
        'minimumConfidence': target.minimumConfidence,
        'minimumSampleCount': target.minimumSampleCount,
        'targetDate': target.targetDate == null
            ? null
            : _dateToJson(target.targetDate!),
      };

  MetricTarget _metricTargetFromJson(Map<String, dynamic> json) {
    final metricCode = json['metricCode'];
    final directionRaw = json['direction'];
    final threshold = json['threshold'];
    final measurementCapability = json['measurementCapability'];
    final minimumConfidence = json['minimumConfidence'];
    final minimumSampleCount = json['minimumSampleCount'];
    if (metricCode is! String ||
        directionRaw is! String ||
        threshold is! num ||
        measurementCapability is! String ||
        minimumConfidence is! num ||
        minimumSampleCount is! num) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.goalsInvalid,
        field: 'goals.metricTarget',
      );
    }
    final targetDateRaw = json['targetDate'];
    return MetricTarget(
      metricCode: metricCode,
      direction: MetricDirection.fromCode(directionRaw),
      threshold: threshold.toDouble(),
      measurementCapability: measurementCapability,
      minimumConfidence: minimumConfidence.toDouble(),
      minimumSampleCount: minimumSampleCount.round(),
      targetDate: targetDateRaw is String ? _dateFromJson(targetDateRaw) : null,
    );
  }

  // ---------------------------------------------------------------------
  // Availability
  // ---------------------------------------------------------------------

  Map<String, dynamic> _dailyAvailabilityToJson(DailyAvailability day) =>
      <String, dynamic>{
        'date': _dateToJson(day.date),
        'status': day.status.code,
        'minimumMinutes': day.minimumMinutes,
        'targetMinutes': day.targetMinutes,
        'maximumMinutes': day.maximumMinutes,
        'maximumStrength': day.maximumStrength.code,
        'preferredStartMinute': day.preferredStartMinute,
        'note': day.note,
        'softExcessMinuteCost': day.softExcessMinuteCost,
      };

  DailyAvailability _dailyAvailabilityFromJson(Map<String, dynamic> json) {
    final dateRaw = json['date'];
    final statusRaw = json['status'];
    final minMinutes = json['minimumMinutes'];
    final targetMinutes = json['targetMinutes'];
    final maxMinutes = json['maximumMinutes'];
    final maxStrengthRaw = json['maximumStrength'];
    if (dateRaw is! String ||
        statusRaw is! String ||
        minMinutes is! num ||
        targetMinutes is! num ||
        maxMinutes is! num ||
        maxStrengthRaw is! String) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.availabilityInvalid,
        field: 'availability',
      );
    }
    return DailyAvailability(
      date: _dateFromJson(dateRaw),
      status: AvailabilityStatus.fromCode(statusRaw),
      minimumMinutes: minMinutes.round(),
      targetMinutes: targetMinutes.round(),
      maximumMinutes: maxMinutes.round(),
      maximumStrength: ConstraintStrength.fromCode(maxStrengthRaw),
      preferredStartMinute: (json['preferredStartMinute'] as num?)?.round(),
      note: json['note'] as String?,
      softExcessMinuteCost:
          (json['softExcessMinuteCost'] as num?)?.round() ?? 0,
    );
  }

  // ---------------------------------------------------------------------
  // Constraint
  // ---------------------------------------------------------------------

  Map<String, dynamic> _constraintToJson(LearnerConstraint constraint) =>
      <String, dynamic>{
        'category': constraint.category.code,
        'strength': constraint.strength.code,
        'code': constraint.code,
        'value': constraint.value,
        'softViolationCost': constraint.softViolationCost,
      };

  LearnerConstraint _constraintFromJson(Map<String, dynamic> json) {
    final categoryRaw = json['category'];
    final strengthRaw = json['strength'];
    final codeRaw = json['code'];
    final valueRaw = json['value'];
    if (categoryRaw is! String ||
        strengthRaw is! String ||
        codeRaw is! String ||
        valueRaw is! String) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.constraintsInvalid,
        field: 'constraints',
      );
    }
    return LearnerConstraint(
      category: ConstraintCategory.fromCode(categoryRaw),
      strength: ConstraintStrength.fromCode(strengthRaw),
      code: codeRaw,
      value: valueRaw,
      softViolationCost: (json['softViolationCost'] as num?)?.round() ?? 0,
    );
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw GenerationRequestSerializerException(
      GenerationRequestSerializerErrorCode.requestInvalid,
    );
  }

  String _dateToJson(LocalDate date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  LocalDate _dateFromJson(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.requestInvalid,
        field: 'date',
      );
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      throw GenerationRequestSerializerException(
        GenerationRequestSerializerErrorCode.requestInvalid,
        field: 'date',
      );
    }
    return LocalDate(year, month, day);
  }
}
