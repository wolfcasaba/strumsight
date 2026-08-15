import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/data/local/generation_request_serializer.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/learner_constraints.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_enums.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_generation_request.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_goal.dart';
import 'package:strumsight/features/practice_generator/domain/model/weekly_availability.dart';

const _serializer = GenerationRequestSerializer();

PracticeGenerationRequest buildRequest({
  String id = 'req-1',
  DateTime? createdAt,
  int planHorizonDays = 14,
  GenerationMode generationMode = GenerationMode.starter,
}) => PracticeGenerationRequest(
  id: GenerationRequestId(id),
  createdAt: createdAt ?? DateTime.utc(2026, 8, 15, 9, 30),
  locale: 'en',
  generationMode: generationMode,
  planHorizonDays: planHorizonDays,
  goals: [
    PracticeGoal(
      id: GoalId('goal-1'),
      type: PracticeGoalType.chordChanges,
      priority: GoalPriority.primary,
      status: PracticeGoalStatus.proposed,
      createdAt: DateTime.utc(2026, 8, 1),
      targetDate: LocalDate(2026, 9, 1),
      skillIds: const ['skill:open-chords'],
      songReference: 'song-42',
      metricTarget: MetricTarget(
        metricCode: 'timing.error.ms',
        direction: MetricDirection.atMost,
        threshold: 20,
        measurementCapability: 'timingEvidenceV1',
        minimumConfidence: 0.8,
        minimumSampleCount: 12,
        targetDate: LocalDate(2026, 9, 1),
      ),
      userNote: 'Focus on smooth transitions.',
    ),
  ],
  availability: WeeklyAvailability([
    DailyAvailability(
      date: LocalDate(2026, 8, 17),
      status: AvailabilityStatus.available,
      minimumMinutes: 10,
      targetMinutes: 20,
      maximumMinutes: 30,
      maximumStrength: ConstraintStrength.soft,
      preferredStartMinute: 480,
      note: 'Morning slot',
      softExcessMinuteCost: 2,
    ),
    DailyAvailability(
      date: LocalDate(2026, 8, 18),
      status: AvailabilityStatus.unavailable,
      minimumMinutes: 0,
      targetMinutes: 0,
      maximumMinutes: 0,
      maximumStrength: ConstraintStrength.hard,
    ),
  ]),
  constraints: LearnerConstraints([
    LearnerConstraint(
      category: ConstraintCategory.equipment,
      strength: ConstraintStrength.hard,
      code: 'no-capo',
      value: 'true',
    ),
    LearnerConstraint(
      category: ConstraintCategory.comfort,
      strength: ConstraintStrength.soft,
      code: 'avoid-barre',
      value: 'true',
      softViolationCost: 5,
    ),
  ]),
);

/// Deep-copies a JSON value, rebuilding every nested [Map] with its keys in
/// reverse insertion order. The content is unchanged — only the on-disk
/// field order differs.
Object? _reorderKeysDeep(Object? value) {
  if (value is Map<String, dynamic>) {
    final reversedKeys = value.keys.toList().reversed;
    return <String, dynamic>{
      for (final key in reversedKeys) key: _reorderKeysDeep(value[key]),
    };
  }
  if (value is List) {
    return [for (final item in value) _reorderKeysDeep(item)];
  }
  return value;
}

void main() {
  group('GenerationRequestSerializer round trip', () {
    test('JSON round-trip is lossless (A1)', () {
      final request = buildRequest();
      final json = _serializer.toJson(request);
      final decoded = _serializer.fromJson(json);

      expect(decoded, request);
      expect(decoded.id, request.id);
      expect(decoded.createdAt, request.createdAt);
      expect(decoded.locale, request.locale);
      expect(decoded.generationMode, request.generationMode);
      expect(decoded.planHorizonDays, request.planHorizonDays);
      expect(
        decoded.goals.single.metricTarget,
        request.goals.single.metricTarget,
      );
      expect(decoded.availability.days.length, 2);
      expect(decoded.constraints.constraints.length, 2);
    });

    test('the same request content yields the same hash and seed (A2)', () {
      final a = buildRequest();
      final b = buildRequest();

      expect(a.seed, b.seed);
      expect(a.contentHash, b.contentHash);
    });

    test('id and createdAt do not affect the hash/seed (A2)', () {
      final a = buildRequest(id: 'req-1', createdAt: DateTime.utc(2026, 1, 1));
      final b = buildRequest(id: 'req-2', createdAt: DateTime.utc(2030, 6, 6));

      expect(a.seed, b.seed);
      expect(a.contentHash, b.contentHash);
    });

    test('a content change does change the hash and seed (A2 sanity)', () {
      final a = buildRequest(planHorizonDays: 14);
      final b = buildRequest(planHorizonDays: 21);

      expect(a.seed, isNot(b.seed));
      expect(a.contentHash, isNot(b.contentHash));
    });

    test('reordering the persisted JSON fields does not change the decoded '
        'hash/seed (A3 — canonical hash cell)', () {
      final request = buildRequest();
      final canonicalJson = _serializer.toJson(request);
      final reordered = _reorderKeysDeep(canonicalJson) as Map<String, dynamic>;

      final decodedCanonical = _serializer.fromJson(canonicalJson);
      final decodedReordered = _serializer.fromJson(reordered);

      expect(decodedReordered, decodedCanonical);
      expect(decodedReordered.seed, decodedCanonical.seed);
      expect(decodedReordered.contentHash, decodedCanonical.contentHash);
    });
  });

  group('GenerationRequestSerializer schema migration (§6.1 three cells)', () {
    test('an older (v1) schema document migrates and is readable (A4)', () {
      final v1Json = <String, dynamic>{
        'schemaVersion': 1,
        'id': 'req-legacy',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'locale': 'en',
        'mode': 'starter',
        'horizonWeeks': 2,
        'goals': const <dynamic>[],
        'availability': const <dynamic>[],
        'constraints': const <dynamic>[],
      };

      final decoded = _serializer.fromJson(v1Json);

      expect(decoded.generationMode, GenerationMode.starter);
      expect(decoded.planHorizonDays, 14);
      expect(decoded.id, GenerationRequestId('req-legacy'));
    });

    test('a document at the current (boundary) schema version is readable '
        'without migration', () {
      final request = buildRequest();
      final json = _serializer.toJson(request);
      expect(
        json['schemaVersion'],
        GenerationRequestSerializer.currentSchemaVersion,
      );

      final decoded = _serializer.fromJson(json);
      expect(decoded, request);
    });

    test('a future (newer) schema version is a controlled rejection, not a '
        'best-effort read (A5)', () {
      final request = buildRequest();
      final futureJson = <String, dynamic>{
        ..._serializer.toJson(request),
        'schemaVersion': GenerationRequestSerializer.currentSchemaVersion + 1,
      };

      expect(
        () => _serializer.fromJson(futureJson),
        throwsA(isA<GenerationRequestSerializerException>()),
      );
    });

    test('a missing schemaVersion is a controlled rejection', () {
      final json = _serializer.toJson(buildRequest())..remove('schemaVersion');
      expect(
        () => _serializer.fromJson(json),
        throwsA(isA<GenerationRequestSerializerException>()),
      );
    });
  });
}
