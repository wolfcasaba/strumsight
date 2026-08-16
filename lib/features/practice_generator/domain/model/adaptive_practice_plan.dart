/// Canonical, versioned adaptive practice-plan document (SDD Ch8 §16.1).
library;

import '../id/planner_ids.dart';
import 'plan_enums.dart';
import 'practice_block.dart';
import 'practice_day.dart';
import 'practice_generation_request.dart';
import 'practice_goal.dart';
import 'weekly_availability.dart';

final class AdaptivePracticePlan {
  AdaptivePracticePlan({
    required this.id,
    required int schemaVersion,
    required this.status,
    required String title,
    required DateTime createdAt,
    required this.startDate,
    required this.endDate,
    required Iterable<PracticeGoal> goals,
    required Iterable<PracticeDay> days,
    required this.activeRevisionId,
    required this.generationProvenance,
    required Map<String, String> policyVersions,
  }) : schemaVersion = _positive(schemaVersion, 'schemaVersion'),
       title = _text(title, 'title'),
       createdAt = createdAt.toUtc(),
       goals = List<PracticeGoal>.unmodifiable(goals),
       days = List<PracticeDay>.unmodifiable(days),
       policyVersions = Map<String, String>.unmodifiable(
         policyVersions.map(
           (key, value) => MapEntry(
             _text(key, 'policyVersions key'),
             _text(value, 'policyVersions value'),
           ),
         ),
       ) {
    if (startDate.compareTo(endDate) > 0) {
      throw ArgumentError('startDate must not be after endDate');
    }
    _requireUnique(this.goals.map((goal) => goal.id), 'goals');
    _requireUnique(this.days.map((day) => day.id), 'days');
  }

  final PlanId id;
  final int schemaVersion;
  final PlanStatus status;
  final String title;
  final DateTime createdAt;
  final LocalDate startDate;
  final LocalDate endDate;
  final List<PracticeGoal> goals;
  final List<PracticeDay> days;
  final RevisionId activeRevisionId;
  final GenerationRequestId generationProvenance;
  final Map<String, String> policyVersions;

  AdaptivePracticePlan copyWith({
    String? title,
    PlanStatus? status,
    Iterable<PracticeDay>? days,
    RevisionId? activeRevisionId,
  }) => AdaptivePracticePlan(
    id: id,
    schemaVersion: schemaVersion,
    status: status ?? this.status,
    title: title ?? this.title,
    createdAt: createdAt,
    startDate: startDate,
    endDate: endDate,
    goals: goals,
    days: days ?? this.days,
    activeRevisionId: activeRevisionId ?? this.activeRevisionId,
    generationProvenance: generationProvenance,
    policyVersions: policyVersions,
  );

  PracticePlanSummary toSummary() => PracticePlanSummary(
    id: id,
    title: title,
    status: status,
    startDate: startDate,
    endDate: endDate,
    activeRevisionId: activeRevisionId,
    dayCount: days.length,
    goalCount: goals.length,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id.toJson(),
    'status': status.code,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'startDate': _dateToJson(startDate),
    'endDate': _dateToJson(endDate),
    'goals': [for (final goal in goals) _goalToJson(goal)],
    'days': [for (final day in days) day.toJson()],
    'activeRevisionId': activeRevisionId.toJson(),
    'generationProvenance': generationProvenance.toJson(),
    'policyVersions': policyVersions,
  };

  static AdaptivePracticePlan fromJson(
    Map<String, Object?> json, {
    required ExerciseCandidateResolver resolveCandidate,
  }) {
    final rawGoals = _list(json['goals'], 'goals');
    final rawDays = _list(json['days'], 'days');
    final policyVersions = _object(json['policyVersions'], 'policyVersions');
    return AdaptivePracticePlan(
      id: PlanId.fromJson(json['id']),
      schemaVersion: _integer(json['schemaVersion'], 'schemaVersion'),
      status: PlanStatus.fromCode(_text(json['status'], 'status')),
      title: _text(json['title'], 'title'),
      createdAt: _dateTime(json['createdAt'], 'createdAt'),
      startDate: _dateFromJson(json['startDate'], 'startDate'),
      endDate: _dateFromJson(json['endDate'], 'endDate'),
      goals: [
        for (final goal in rawGoals) _goalFromJson(_object(goal, 'goals[]')),
      ],
      days: [
        for (final day in rawDays)
          PracticeDay.fromJson(
            _object(day, 'days[]'),
            resolveCandidate: resolveCandidate,
          ),
      ],
      activeRevisionId: RevisionId.fromJson(json['activeRevisionId']),
      generationProvenance: GenerationRequestId.fromJson(
        json['generationProvenance'],
      ),
      policyVersions: <String, String>{
        for (final entry in policyVersions.entries)
          entry.key: _text(entry.value, 'policyVersions.${entry.key}'),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdaptivePracticePlan &&
          id == other.id &&
          schemaVersion == other.schemaVersion &&
          status == other.status &&
          title == other.title &&
          createdAt == other.createdAt &&
          startDate == other.startDate &&
          endDate == other.endDate &&
          _sameList(goals, other.goals) &&
          _sameList(days, other.days) &&
          activeRevisionId == other.activeRevisionId &&
          generationProvenance == other.generationProvenance &&
          _sameMap(policyVersions, other.policyVersions);

  @override
  int get hashCode => Object.hash(
    id,
    schemaVersion,
    status,
    title,
    createdAt,
    startDate,
    endDate,
    Object.hashAll(goals),
    Object.hashAll(days),
    activeRevisionId,
    generationProvenance,
    Object.hashAll(policyVersions.entries),
  );
}

/// Presentation-safe overview. It intentionally omits all goal user notes.
final class PracticePlanSummary {
  const PracticePlanSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.activeRevisionId,
    required this.dayCount,
    required this.goalCount,
  });

  final PlanId id;
  final String title;
  final PlanStatus status;
  final LocalDate startDate;
  final LocalDate endDate;
  final RevisionId activeRevisionId;
  final int dayCount;
  final int goalCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.toJson(),
    'title': title,
    'status': status.code,
    'startDate': _dateToJson(startDate),
    'endDate': _dateToJson(endDate),
    'activeRevisionId': activeRevisionId.toJson(),
    'dayCount': dayCount,
    'goalCount': goalCount,
  };
}

Map<String, int> _dateToJson(LocalDate date) => <String, int>{
  'year': date.year,
  'month': date.month,
  'day': date.day,
};

LocalDate _dateFromJson(Object? value, String name) {
  final json = _object(value, name);
  return LocalDate(
    _integer(json['year'], '$name.year'),
    _integer(json['month'], '$name.month'),
    _integer(json['day'], '$name.day'),
  );
}

Map<String, Object?> _goalToJson(PracticeGoal goal) => <String, Object?>{
  'id': goal.id.toJson(),
  'type': goal.type.code,
  'priority': goal.priority.code,
  'status': goal.status.code,
  'createdAt': goal.createdAt.toIso8601String(),
  'targetDate': goal.targetDate == null ? null : _dateToJson(goal.targetDate!),
  'skillIds': goal.skillIds,
  'songReference': goal.songReference,
  'metricTarget': goal.metricTarget == null
      ? null
      : _metricTargetToJson(goal.metricTarget!),
  'userNote': goal.userNote,
  'normalizedTargetId': goal.normalizedTargetId,
};

PracticeGoal _goalFromJson(Map<String, Object?> json) => PracticeGoal(
  id: GoalId.fromJson(json['id']),
  type: PracticeGoalType.fromCode(_text(json['type'], 'goal.type')),
  priority: GoalPriority.fromCode(_text(json['priority'], 'goal.priority')),
  status: PracticeGoalStatus.fromCode(_text(json['status'], 'goal.status')),
  createdAt: _dateTime(json['createdAt'], 'goal.createdAt'),
  targetDate: json['targetDate'] == null
      ? null
      : _dateFromJson(json['targetDate'], 'goal.targetDate'),
  skillIds: _textList(json['skillIds'], 'goal.skillIds'),
  songReference: _nullableText(json['songReference'], 'goal.songReference'),
  metricTarget: json['metricTarget'] == null
      ? null
      : _metricTargetFromJson(
          _object(json['metricTarget'], 'goal.metricTarget'),
        ),
  userNote: _nullableText(json['userNote'], 'goal.userNote'),
  normalizedTargetId: _nullableText(
    json['normalizedTargetId'],
    'goal.normalizedTargetId',
  ),
);

Map<String, Object?> _metricTargetToJson(MetricTarget target) =>
    <String, Object?>{
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

MetricTarget _metricTargetFromJson(Map<String, Object?> json) => MetricTarget(
  metricCode: _text(json['metricCode'], 'metricTarget.metricCode'),
  direction: MetricDirection.fromCode(
    _text(json['direction'], 'metricTarget.direction'),
  ),
  threshold: _number(json['threshold'], 'metricTarget.threshold'),
  measurementCapability: _text(
    json['measurementCapability'],
    'metricTarget.measurementCapability',
  ),
  minimumConfidence: _number(
    json['minimumConfidence'],
    'metricTarget.minimumConfidence',
  ),
  minimumSampleCount: _integer(
    json['minimumSampleCount'],
    'metricTarget.minimumSampleCount',
  ),
  targetDate: json['targetDate'] == null
      ? null
      : _dateFromJson(json['targetDate'], 'metricTarget.targetDate'),
);

void _requireUnique<T>(Iterable<T> values, String name) {
  final set = <T>{};
  for (final value in values) {
    if (!set.add(value)) {
      throw ArgumentError.value(values, name, 'must be unique');
    }
  }
}

int _positive(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}

String _text(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must be a non-empty String');
  }
  return value.trim();
}

String? _nullableText(Object? value, String name) =>
    value == null ? null : _text(value, name);

int _integer(Object? value, String name) {
  if (value is! num || value.toInt() != value) {
    throw ArgumentError.value(value, name, 'must be an integer');
  }
  return value.toInt();
}

double _number(Object? value, String name) {
  if (value is! num) {
    throw ArgumentError.value(value, name, 'must be numeric');
  }
  return value.toDouble();
}

DateTime _dateTime(Object? value, String name) {
  if (value is! String) {
    throw ArgumentError.value(value, name, 'must be an ISO date');
  }
  return DateTime.parse(value).toUtc();
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) {
    throw ArgumentError.value(value, name, 'must be an object');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, String name) {
  if (value is! List) {
    throw ArgumentError.value(value, name, 'must be a list');
  }
  return List<Object?>.from(value);
}

List<String> _textList(Object? value, String name) {
  if (value is! List) {
    throw ArgumentError.value(value, name, 'must be a list');
  }
  return [for (final entry in value) _text(entry, name)];
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameMap<K, V>(Map<K, V> left, Map<K, V> right) =>
    left.length == right.length &&
    left.entries.every((entry) => right[entry.key] == entry.value);
