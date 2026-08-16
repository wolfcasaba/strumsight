// E07-R11 — PlanValidator: A1, A7, A8, A9, plus the three severity cells
// from the round brief §6.1 (below/on/above the activation boundary).

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

void main() {
  group('severity boundary (§6.1)', () {
    test('below: only warning findings -> plan is activatable', () {
      final candidate = buildCandidate(frettingHandLoad: LoadLevel.high);
      final prescription = buildPrescription(candidate);
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[
          buildBlock(id: 'block.1', order: 1, prescription: prescription),
          buildBlock(id: 'block.2', order: 2, prescription: prescription),
          buildBlock(id: 'block.3', order: 3, prescription: prescription),
        ],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
      );

      final result = const PlanValidator().validate(plan, context);

      expect(result.issues, isNotEmpty);
      expect(result.hasError, isFalse);
      expect(result.hasFatal, isFalse);
      expect(result.isActivatable, isTrue);
    });

    test('on the boundary: exactly one error -> not activatable', () {
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[
          buildBlock(
            id: 'block.1',
            order: 1,
            prescription: buildPrescription(
              buildCandidate(exerciseId: 'exercise.unknown-in-plan'),
            ),
          ),
        ],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      // Catalog only knows about the default candidate — the block's
      // exercise.unknown-in-plan identity is missing from it.
      final context = buildContext();

      final result = const PlanValidator().validate(plan, context);

      final errors = result.issues
          .where((issue) => issue.severity == ValidationSeverity.error)
          .toList();
      expect(errors, hasLength(1));
      expect(errors.single.code, PlanValidationCode.candidateIdentityMissing);
      expect(result.isActivatable, isFalse);
    });

    test('above the boundary: a fatal finding -> not activatable', () {
      final completedBlock = buildBlock(
        id: 'block.1',
        order: 1,
        status: PracticeItemStatus.completed,
      );
      final previousDay = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        status: PracticeItemStatus.completed,
        blocks: <PracticeBlock>[completedBlock],
      );
      final modifiedBlock = buildBlock(
        id: 'block.2',
        order: 1,
        status: PracticeItemStatus.completed,
      );
      final currentDay = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        status: PracticeItemStatus.completed,
        blocks: <PracticeBlock>[modifiedBlock],
      );
      final previousPlan = buildPlan(days: <PracticeDay>[previousDay]);
      final currentPlan = buildPlan(days: <PracticeDay>[currentDay]);
      final context = buildContext(previousSnapshot: previousPlan);

      final result = const PlanValidator().validate(currentPlan, context);

      expect(result.hasFatal, isTrue);
      expect(
        result.issues.first.code,
        PlanValidationCode.completedHistoryModified,
      );
      expect(result.isActivatable, isFalse);
    });
  });

  group('A7: hard-avoid is error, not warning', () {
    test('a hard-avoided identity is reported as error', () {
      final candidate = buildCandidate();
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[
          buildBlock(
            id: 'block.1',
            order: 1,
            prescription: buildPrescription(candidate),
          ),
        ],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        hardAvoidIdentities: <String>[identityOf(candidate)],
      );

      final result = const PlanValidator().validate(plan, context);

      final hardAvoidIssues = result.issues.where(
        (issue) => issue.code == PlanValidationCode.hardAvoidViolated,
      );
      expect(hardAvoidIssues, hasLength(1));
      expect(hardAvoidIssues.single.severity, ValidationSeverity.error);
    });
  });

  group('A8: missing asset / capability / tuning are detected', () {
    test('missing confirmed asset is an error', () {
      final candidate = buildCandidate(
        capabilityOverrides: <ExerciseCapability, CapabilitySupport>{
          ExerciseCapability.requiresSongAsset: CapabilitySupport.supported,
        },
      );
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: <PracticeBlock>[
              buildBlock(
                id: 'block.1',
                order: 1,
                prescription: buildPrescription(candidate),
              ),
            ],
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
      );

      final result = const PlanValidator().validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        contains(PlanValidationCode.assetNotConfirmed),
      );
    });

    test('a confirmed asset identity clears the finding', () {
      final candidate = buildCandidate(
        capabilityOverrides: <ExerciseCapability, CapabilitySupport>{
          ExerciseCapability.requiresSongAsset: CapabilitySupport.supported,
        },
      );
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: <PracticeBlock>[
              buildBlock(
                id: 'block.1',
                order: 1,
                prescription: buildPrescription(candidate),
              ),
            ],
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        confirmedAssetIdentities: <String>[identityOf(candidate)],
      );

      final result = const PlanValidator().validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        isNot(contains(PlanValidationCode.assetNotConfirmed)),
      );
    });

    test('missing confirmed device capability is an error', () {
      final candidate = buildCandidate(
        capabilityOverrides: <ExerciseCapability, CapabilitySupport>{
          ExerciseCapability.requiresMicrophone: CapabilitySupport.supported,
        },
      );
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: <PracticeBlock>[
              buildBlock(
                id: 'block.1',
                order: 1,
                prescription: buildPrescription(candidate),
              ),
            ],
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
      );

      final result = const PlanValidator().validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        contains(PlanValidationCode.deviceCapabilityNotConfirmed),
      );
    });

    test('missing confirmed offline availability is an error', () {
      final candidate = buildCandidate(offlineAvailable: false);
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: <PracticeBlock>[
              buildBlock(
                id: 'block.1',
                order: 1,
                prescription: buildPrescription(candidate),
              ),
            ],
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
      );

      final result = const PlanValidator().validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        contains(PlanValidationCode.offlineNotConfirmed),
      );
    });

    test('missing confirmed tuning/prerequisite is an error', () {
      final candidate = buildCandidate(prerequisites: <String>['guitar.tuned']);
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: <PracticeBlock>[
              buildBlock(
                id: 'block.1',
                order: 1,
                prescription: buildPrescription(candidate),
              ),
            ],
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
      );

      final result = const PlanValidator().validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        contains(PlanValidationCode.tuningNotConfirmed),
      );
    });

    test('a stale content revision is an error', () {
      final catalogCandidate = buildCandidate(contentRevision: 'content.v2');
      final staleCandidate = buildCandidate();
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(
            id: 'day.1',
            localDate: LocalDate(2026, 8, 17),
            blocks: <PracticeBlock>[
              buildBlock(
                id: 'block.1',
                order: 1,
                prescription: buildPrescription(staleCandidate),
              ),
            ],
          ),
        ],
      );
      final context = buildContext(
        catalog: buildCatalog(candidates: [catalogCandidate]),
      );

      final result = const PlanValidator().validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        contains(PlanValidationCode.contentRevisionMismatch),
      );
    });
  });

  group('A9: load sequencing', () {
    test('two consecutive high-load blocks raise no warning', () {
      final candidate = buildCandidate(frettingHandLoad: LoadLevel.high);
      final prescription = buildPrescription(candidate);
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[
          buildBlock(id: 'block.1', order: 1, prescription: prescription),
          buildBlock(id: 'block.2', order: 2, prescription: prescription),
        ],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
      );

      final result = const PlanValidator().validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        isNot(contains(PlanValidationCode.loadSequencingWarning)),
      );
    });

    test('three consecutive high-load blocks raise a warning', () {
      final candidate = buildCandidate(frettingHandLoad: LoadLevel.high);
      final prescription = buildPrescription(candidate);
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[
          buildBlock(id: 'block.1', order: 1, prescription: prescription),
          buildBlock(id: 'block.2', order: 2, prescription: prescription),
          buildBlock(id: 'block.3', order: 3, prescription: prescription),
        ],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
      );

      final result = const PlanValidator().validate(plan, context);

      final warnings = result.issues.where(
        (issue) => issue.code == PlanValidationCode.loadSequencingWarning,
      );
      expect(warnings, hasLength(1));
      expect(warnings.single.severity, ValidationSeverity.warning);
    });

    test('the threshold is an injectable policy parameter', () {
      final candidate = buildCandidate(frettingHandLoad: LoadLevel.high);
      final prescription = buildPrescription(candidate);
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[
          buildBlock(id: 'block.1', order: 1, prescription: prescription),
          buildBlock(id: 'block.2', order: 2, prescription: prescription),
        ],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
      );

      final result = const PlanValidator(
        maxConsecutiveHighFrettingLoad: 1,
      ).validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        contains(PlanValidationCode.loadSequencingWarning),
      );
    });
  });

  group('hard maximum', () {
    test('exceeding the hard daily maximum is an error', () {
      final candidate = buildCandidate();
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[
          buildBlock(
            id: 'block.1',
            order: 1,
            prescription: buildPrescription(candidate),
            estimatedElapsed: const Duration(minutes: 10),
          ),
        ],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        availability: buildAvailability(maximumMinutes: 5),
      );

      final result = const PlanValidator().validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        contains(PlanValidationCode.hardMaximumExceeded),
      );
      expect(result.isActivatable, isFalse);
    });

    test('a soft maximum does not raise the hard-maximum error', () {
      final candidate = buildCandidate();
      final day = buildDay(
        id: 'day.1',
        localDate: LocalDate(2026, 8, 17),
        blocks: <PracticeBlock>[
          buildBlock(
            id: 'block.1',
            order: 1,
            prescription: buildPrescription(candidate),
            estimatedElapsed: const Duration(minutes: 10),
          ),
        ],
      );
      final plan = buildPlan(days: <PracticeDay>[day]);
      final context = buildContext(
        catalog: buildCatalog(candidates: [candidate]),
        availability: buildAvailability(
          maximumMinutes: 5,
          maximumStrength: ConstraintStrength.soft,
        ),
      );

      final result = const PlanValidator().validate(plan, context);

      expect(
        result.issues.map((issue) => issue.code),
        isNot(contains(PlanValidationCode.hardMaximumExceeded)),
      );
    });
  });
}
