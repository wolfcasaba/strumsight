import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

void main() {
  group('GenerationOrchestrator', () {
    test('A1/A2: cancellation before assembly activates no plan', () async {
      final activation = _RecordingActivation();
      final orchestrator = GenerationOrchestrator(activation: activation);
      late final StreamSubscription<GenerationProgress> subscription;
      subscription = orchestrator.progress.listen((progress) {
        if (progress.stage == GenerationStage.assembling) {
          orchestrator.cancel(progress.requestId);
        }
      });

      final result = await orchestrator.generate(_input());

      await subscription.cancel();
      expect(result, isA<Failure<AdaptivePracticePlan>>());
      expect(result.failureOrNull, isA<CancelledFailure>());
      expect(activation.calls, isZero);
    });

    test(
      'A2 boundary: cancellation before activation activates no plan',
      () async {
        final activation = _RecordingActivation();
        final orchestrator = GenerationOrchestrator(activation: activation);
        late final StreamSubscription<GenerationProgress> subscription;
        subscription = orchestrator.progress.listen((progress) {
          if (progress.stage == GenerationStage.activating) {
            orchestrator.cancel(progress.requestId);
          }
        });

        final result = await orchestrator.generate(_input());

        await subscription.cancel();
        expect(result.failureOrNull, isA<CancelledFailure>());
        expect(activation.calls, isZero);
      },
    );

    test('A2 late: cancellation after activation is a no-op', () async {
      final activation = _RecordingActivation();
      final orchestrator = GenerationOrchestrator(activation: activation);
      final input = _input();

      final result = await orchestrator.generate(input);
      orchestrator.cancel(input.request.id);

      expect(result, isA<Success<AdaptivePracticePlan>>());
      expect(activation.calls, 1);
      expect(
        (result as Success<AdaptivePracticePlan>).value.status,
        PlanStatus.active,
      );
    });

    test(
      'A3/A4: failed assembly is mapped and never activates a partial plan',
      () async {
        final candidate = buildCandidate();
        final activation = _RecordingActivation();
        final orchestrator = GenerationOrchestrator(activation: activation);

        final result = await orchestrator.generate(
          _input(
            catalogCandidates: <ExerciseCandidate>[candidate],
            scheduledIdentity: 'practiceCatalog:missing:content.v1',
          ),
        );

        expect(result, isA<Failure<AdaptivePracticePlan>>());
        expect(result.failureOrNull, isA<UnknownFailure>());
        expect(activation.calls, isZero);
      },
    );

    test(
      'A3: unrepairable validation failure never activates a partial plan',
      () async {
        final candidates = <ExerciseCandidate>[
          for (var index = 0; index < 4; index++)
            buildCandidate(exerciseId: 'exercise.rhythm.$index'),
        ];
        final activation = _RecordingActivation();
        final orchestrator = GenerationOrchestrator(
          activation: activation,
          repairer: const PlanRepairer(maxIterations: 3),
        );

        final result = await orchestrator.generate(
          _input(
            catalogCandidates: candidates,
            hardAvoidIdentities: candidates.map(identityOf),
            scheduledCandidates: candidates
                .map(
                  (candidate) => ScheduleCandidate(
                    identity: candidate.sortKey,
                    focus: CandidateFocus.primaryFocus,
                    materialKind: CandidateMaterialKind.newMaterial,
                    loadLevel: LoadLevel.low,
                    duration: const Duration(minutes: 5),
                    skillTargets: candidate.skillTargets,
                  ),
                )
                .toList(),
          ),
        );

        expect(result, isA<Failure<AdaptivePracticePlan>>());
        expect(result.failureOrNull, isA<ValidationFailure>());
        expect(activation.calls, isZero);
      },
    );

    test('A5: retry starts clean after a failed request', () async {
      final candidate = buildCandidate();
      final activation = _RecordingActivation();
      final orchestrator = GenerationOrchestrator(activation: activation);
      final failed = await orchestrator.generate(
        _input(
          catalogCandidates: <ExerciseCandidate>[candidate],
          scheduledIdentity: 'practiceCatalog:missing:content.v1',
        ),
      );
      final retried = await orchestrator.generate(_input());

      expect(failed, isA<Failure<AdaptivePracticePlan>>());
      expect(retried, isA<Success<AdaptivePracticePlan>>());
      expect(activation.calls, 1);
    });

    test('A6: duplicate request returns the in-flight run', () async {
      final activation = _CompletingActivation();
      final orchestrator = GenerationOrchestrator(activation: activation);
      final input = _input();
      final first = orchestrator.generate(input);
      await activation.started.future;
      final second = orchestrator.generate(input);

      expect(identical(first, second), isTrue);
      activation.complete();
      expect(await first, isA<Success<AdaptivePracticePlan>>());
      expect(activation.calls, 1);
    });
  });
}

GenerationPlanInput _input({
  Iterable<ExerciseCandidate>? catalogCandidates,
  Iterable<String> hardAvoidIdentities = const <String>[],
  Iterable<ScheduleCandidate>? scheduledCandidates,
  String? scheduledIdentity,
}) {
  final candidate = buildCandidate();
  final availability = buildAvailability();
  final request = PracticeGenerationRequest(
    id: GenerationRequestId('request.1'),
    createdAt: DateTime.utc(2026, 8, 18),
    locale: 'en',
    generationMode: GenerationMode.starter,
    planHorizonDays: 1,
    availability: availability,
    constraints: LearnerConstraints(const <LearnerConstraint>[]),
    goals: <PracticeGoal>[buildGoal()],
  );
  final scheduled = ScheduleCandidate(
    identity: scheduledIdentity ?? candidate.sortKey,
    focus: CandidateFocus.primaryFocus,
    materialKind: CandidateMaterialKind.newMaterial,
    loadLevel: LoadLevel.low,
    duration: const Duration(minutes: 5),
    skillTargets: candidate.skillTargets,
  );
  final decision = WeeklyScheduleDecision(
    dayDecisions: <DaySchedulingDecision>[
      DaySchedulingDecision(
        date: availability.days.single.date,
        phase: SchedulingPhase.none,
        selectedCandidates:
            scheduledCandidates ?? <ScheduleCandidate>[scheduled],
        reasonCodes: const <String>['schedule.decision.selected'],
      ),
    ],
    deferredCandidates: const <DeferredCandidate>[],
    policyVersion: SchedulingPolicy.defaultPolicy.version,
    policy: SchedulingPolicy.defaultPolicy,
  );
  return GenerationPlanInput(
    request: request,
    schedule: decision,
    validationContext: buildContext(
      availability: availability,
      catalog: buildCatalog(
        candidates: catalogCandidates ?? <ExerciseCandidate>[candidate],
      ),
      hardAvoidIdentities: hardAvoidIdentities,
    ),
    planId: PlanId('plan.1'),
    initialRevisionId: RevisionId('revision.1'),
  );
}

final class _RecordingActivation implements GenerationPlanActivation {
  int calls = 0;

  @override
  Future<void> activate(AdaptivePracticePlan plan) async {
    calls += 1;
  }
}

final class _CompletingActivation implements GenerationPlanActivation {
  final Completer<void> started = Completer<void>();
  final Completer<void> _completion = Completer<void>();
  int calls = 0;

  @override
  Future<void> activate(AdaptivePracticePlan plan) {
    calls += 1;
    started.complete();
    return _completion.future;
  }

  void complete() => _completion.complete();
}
