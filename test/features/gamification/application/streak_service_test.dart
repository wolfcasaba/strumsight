import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  group('A1 and A8 — inclusive qualified-day thresholds', () {
    final service = StreakService();
    const day = 20500;

    test(
      '119s, 120s, and 121s stay on their intended sides of the boundary',
      () {
        final below = service.evaluate(_request(day: day, seconds: 119));
        final at = service.evaluate(_request(day: day, seconds: 120));
        final above = service.evaluate(_request(day: day, seconds: 121));

        expect(below.state.current, 0);
        expect(below.reason, StreakEvaluationReason.insufficientActivity);
        expect(at.state.current, 1);
        expect(at.reason, StreakEvaluationReason.qualified);
        expect(above.state.current, 1);
        expect(above.reason, StreakEvaluationReason.qualified);
      },
    );

    test(
      'a single immutable configuration changes both applicable thresholds',
      () {
        final service = StreakService(
          qualificationPolicy: DefaultStreakPolicy(
            config: DefaultStreakPolicyConfig(
              minQualifiedDuration: const Duration(seconds: 2),
              minRecoveryDuration: const Duration(seconds: 1),
            ),
          ),
        );

        expect(
          service.evaluate(_request(day: day, seconds: 1)).reason,
          StreakEvaluationReason.insufficientActivity,
        );
        expect(
          service.evaluate(_request(day: day, seconds: 2)).reason,
          StreakEvaluationReason.qualified,
        );
        expect(
          service
              .evaluate(_request(day: day, seconds: 1, recoveryEligible: true))
              .reason,
          StreakEvaluationReason.recoveryQualified,
        );
      },
    );
  });

  group('A9 — explicit recovery only', () {
    final service = StreakService();
    const day = 20500;

    test('59s, 60s, and 61s honour the explicit recovery boundary', () {
      expect(
        service
            .evaluate(_request(day: day, seconds: 59, recoveryEligible: true))
            .reason,
        StreakEvaluationReason.insufficientActivity,
      );
      expect(
        service
            .evaluate(_request(day: day, seconds: 60, recoveryEligible: true))
            .reason,
        StreakEvaluationReason.recoveryQualified,
      );
      expect(
        service
            .evaluate(_request(day: day, seconds: 61, recoveryEligible: true))
            .reason,
        StreakEvaluationReason.recoveryQualified,
      );
      expect(
        service.evaluate(_request(day: day, seconds: 60)).reason,
        StreakEvaluationReason.insufficientActivity,
      );
    });

    test('invalid threshold configurations fail closed', () {
      expect(
        () => DefaultStreakPolicyConfig(
          minQualifiedDuration: const Duration(seconds: 1),
          minRecoveryDuration: const Duration(seconds: 2),
        ),
        throwsArgumentError,
      );
      expect(
        () => DefaultStreakPolicyConfig(
          minQualifiedDuration: const Duration(seconds: -1),
          minRecoveryDuration: Duration.zero,
        ),
        throwsArgumentError,
      );
    });
  });

  group('A2, A6, and A10 — planned rest uses the public schedule contract', () {
    final service = StreakService();
    final restDate = LocalDate(2026, 8, 20);
    final restDay = _shippingLocalMidnightEpochDay(restDate);

    test('a real typed rest decision protects the streak without a freeze', () {
      final previous = _state(
        current: 4,
        longest: 4,
        lastQualifiedDay: restDay - 1,
        totalQualifiedDays: 4,
        freezes: 1,
      );
      final rest = service.evaluate(
        StreakEvaluationRequest(
          previous: previous,
          epochDay: restDay,
          weeklySchedule: _restSchedule(restDate),
        ),
      );
      final nextDay = service.evaluate(
        _request(previous: rest.state, day: restDay + 1, seconds: 120),
      );

      expect(rest.reason, StreakEvaluationReason.plannedRest);
      expect(rest.state.current, 4);
      expect(rest.state.freezes, 1);
      expect(rest.state.plannedRestDays, contains(restDay));
      expect(nextDay.reason, StreakEvaluationReason.qualified);
      expect(nextDay.state.current, 5);
      expect(nextDay.state.freezes, 1);
    });

    test(
      'a local-midnight request epoch day recognizes the typed planned rest',
      () {
        final shippingRestDay = _shippingLocalMidnightEpochDay(restDate);
        final result = service.evaluate(
          StreakEvaluationRequest(
            previous: _state(
              current: 4,
              longest: 4,
              lastQualifiedDay: shippingRestDay - 1,
              totalQualifiedDays: 4,
            ),
            epochDay: shippingRestDay,
            weeklySchedule: _restSchedule(restDate),
          ),
        );

        expect(result.reason, StreakEvaluationReason.plannedRest);
      },
    );

    test(
      'the service reads the typed public rest reason without a string guess',
      () {
        final source = File(
          'lib/features/gamification/infrastructure/default_streak_policy.dart',
        ).readAsStringSync();

        expect(
          source,
          contains(
            "package:strumsight/features/practice_generator/public.dart",
          ),
        );
        expect(source, contains('ScheduleDecisionReason.restDay.code'));
        expect(source, isNot(contains('schedule.decision.restDay')));
        expect(source, isNot(contains('domain/model/schedule_decision.dart')));
      },
    );
  });

  group('A3, A4, A5, and A7 — state transitions remain compassionate', () {
    final service = StreakService();

    test('five qualified events on one day are idempotent', () {
      var result = service.evaluate(_request(day: 20500, seconds: 120));
      final firstState = result.state;
      for (var index = 0; index < 4; index++) {
        result = service.evaluate(
          _request(
            previous: result.state,
            day: 20500,
            seconds: 120,
            eventId: 'same-day-$index',
          ),
        );
      }

      expect(result.reason, StreakEvaluationReason.alreadyQualified);
      expect(result.state, firstState);
    });

    test('a clock rollback is an identity no-op with a typed reason', () {
      final previous = _state(lastQualifiedDay: 20500, current: 3, longest: 5);
      final result = service.evaluate(
        _request(previous: previous, day: 20499, seconds: 120),
      );

      expect(identical(result.state, previous), isTrue);
      expect(result.reason, StreakEvaluationReason.clockAnomaly);
    });

    test('grace, freeze-covered, and broken paths have distinct reasons', () {
      final prior = _state(
        current: 3,
        longest: 5,
        lastQualifiedDay: 20500,
        totalQualifiedDays: 3,
      );
      final grace = service.evaluate(
        StreakEvaluationRequest(previous: prior, epochDay: 20501),
      );
      final frozen = service.evaluate(
        _request(
          previous: prior.copyWith(freezes: 1),
          day: 20502,
          seconds: 120,
        ),
      );
      final broken = service.evaluate(
        _request(previous: prior, day: 20502, seconds: 120),
      );

      expect(grace.reason, StreakEvaluationReason.grace);
      expect(frozen.reason, StreakEvaluationReason.freezeCovered);
      expect(frozen.state.freezes, 0);
      expect(broken.reason, StreakEvaluationReason.broken);
      expect(broken.state.longest, 5);
      expect(broken.state.totalQualifiedDays, 4);
    });

    test('weekly consistency is a separate inclusive seven-day projection', () {
      final state = _state(current: 0, longest: 8, totalQualifiedDays: 50);

      expect(
        service.weeklyConsistency(
          endingEpochDay: 20506,
          qualifiedDayHistory: <int>[20499, 20500, 20501, 20501, 20505, 20506],
        ),
        4,
      );
      expect(state.current, 0, reason: 'daily state is not an input');
    });

    test('the application service has no XP or ledger dependency', () {
      final source = File(
        'lib/features/gamification/application/streak_service.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('ExperiencePoints')));
      expect(source, isNot(contains('RewardLedger')));
      expect(source, isNot(contains('DateTime.now')));
    });
  });
}

StreakEvaluationRequest _request({
  StreakState? previous,
  required int day,
  required int seconds,
  bool recoveryEligible = false,
  String eventId = 'event',
}) => StreakEvaluationRequest(
  previous: previous ?? _state(),
  epochDay: day,
  activity: PracticeActivityEvent(
    eventId: eventId,
    occurredAt: DateTime.utc(2026, 8, 20),
    epochDay: day,
    source: ActivitySource.practice,
    trust: EvidenceTrust.scored,
    schemaVersion: learningActivityEventSchemaVersion,
    duration: Duration(seconds: seconds),
    score: 1,
  ),
  recoveryEligible: recoveryEligible,
);

WeeklyScheduleDecision _restSchedule(LocalDate restDate) =>
    WeeklyScheduleDecision(
      dayDecisions: <DaySchedulingDecision>[
        DaySchedulingDecision(
          date: restDate,
          phase: SchedulingPhase.none,
          selectedCandidates: const <ScheduleCandidate>[],
          reasonCodes: <String>[ScheduleDecisionReason.restDay.code],
        ),
      ],
      deferredCandidates: const <DeferredCandidate>[],
      policyVersion: SchedulingPolicy.defaultPolicy.version,
      policy: SchedulingPolicy.defaultPolicy,
    );

int _shippingLocalMidnightEpochDay(LocalDate date) =>
    DateTime(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

StreakState _state({
  int current = 0,
  int longest = 0,
  int lastQualifiedDay = -1,
  int totalQualifiedDays = 0,
  int freezes = 0,
}) => StreakState(
  current: current,
  longest: longest,
  lastQualifiedDay: lastQualifiedDay,
  totalQualifiedDays: totalQualifiedDays,
  freezes: freezes,
);
