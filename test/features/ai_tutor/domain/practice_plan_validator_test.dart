import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_draft.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';
import 'package:strumsight/features/ai_tutor/domain/services/practice_plan_validator.dart';

void main() {
  const validator = PracticePlanValidator();

  group('deterministic practice-plan templates', () {
    for (final minutes in const <int>[5, 10, 20, 30]) {
      test('$minutes-minute template has an exact duration budget', () {
        final draft = PracticePlanDraft.deterministicTemplate(
          targetDuration: Duration(minutes: minutes),
        );

        expect(draft.targetDuration, Duration(minutes: minutes));
        expect(
          draft.blocks.fold<Duration>(
            Duration.zero,
            (total, block) => total + block.duration,
          ),
          draft.targetDuration,
        );
      });

      test(
        '$minutes-minute duration rejects under, exact, and over budgets',
        () {
          final draft = PracticePlanDraft.deterministicTemplate(
            targetDuration: Duration(minutes: minutes),
          );
          final firstBlock = draft.blocks.first;
          final underBudget = draft.copyWith(
            blocks: <PracticePlanBlock>[
              firstBlock.copyWith(
                duration: firstBlock.duration - const Duration(minutes: 1),
              ),
              ...draft.blocks.skip(1),
            ],
          );
          final overBudget = draft.copyWith(
            blocks: <PracticePlanBlock>[
              firstBlock.copyWith(
                duration: firstBlock.duration + const Duration(minutes: 1),
              ),
              ...draft.blocks.skip(1),
            ],
          );

          expect(
            validator.validate(draft, context: _context()).isValid,
            isTrue,
          );
          expect(
            validator.validate(underBudget, context: _context()).codes,
            contains(PracticePlanValidationCode.durationMismatch),
          );
          expect(
            validator.validate(overBudget, context: _context()).codes,
            contains(PracticePlanValidationCode.durationMismatch),
          );
        },
      );
    }
  });

  group('PracticePlanValidator', () {
    test('uses stable codes for every blocked input', () {
      final base = _draft(
        PracticePlanBlock.practiceTarget(
          id: 'target',
          type: PracticePlanBlockType.rhythm,
          duration: const Duration(minutes: 5),
          practiceTargetId: 'target',
        ),
      );

      expect(
        validator
            .validate(
              base.copyWith(
                blocks: <PracticePlanBlock>[
                  base.blocks.single.copyWith(type: 'unsupported'),
                ],
              ),
              context: _context(),
            )
            .codes,
        contains(PracticePlanValidationCode.unsupportedBlockType),
      );
      expect(
        validator
            .validate(
              base.copyWith(
                blocks: <PracticePlanBlock>[
                  base.blocks.single.copyWith(tempoBpm: 301),
                ],
              ),
              context: _context(),
            )
            .codes,
        contains(PracticePlanValidationCode.tempoOutOfRange),
      );

      final songBlock = PracticePlanBlock.song(
        id: 'song',
        duration: const Duration(minutes: 5),
        songId: 'missing-song',
      );
      expect(
        validator.validate(_draft(songBlock), context: _context()).codes,
        contains(PracticePlanValidationCode.songMissing),
      );
      expect(
        validator
            .validate(
              _draft(
                base.blocks.single.copyWith(
                  requiredTuning: const <String>['D2', 'A2'],
                ),
              ),
              context: _context(activeTuning: const <String>['E2', 'A2']),
            )
            .codes,
        contains(PracticePlanValidationCode.tuningMismatch),
      );
      expect(
        validator
            .validate(base, context: _context(userAvoidList: const {'rhythm'}))
            .codes,
        contains(PracticePlanValidationCode.userAvoidConflict),
      );
      expect(
        validator
            .validate(
              _draft(
                base.blocks.single.copyWith(
                  requiredCapabilities: const {
                    PracticePlanCapability.practiceTarget,
                  },
                ),
              ),
              context: _context(),
            )
            .codes,
        contains(PracticePlanValidationCode.capabilityUnavailable),
      );
      expect(
        validator
            .validate(
              _draft(
                base.blocks.single.copyWith(
                  requiredSkillIds: <SkillId>[SkillId('rhythm.pulse')],
                ),
              ),
              context: _context(),
            )
            .codes,
        contains(PracticePlanValidationCode.skillUnavailable),
      );
    });

    test('revalidates a user edit instead of retaining the earlier result', () {
      final original = _draft(
        PracticePlanBlock.practiceTarget(
          id: 'editable-target',
          type: PracticePlanBlockType.rhythm,
          duration: const Duration(minutes: 5),
          practiceTargetId: 'target',
        ),
      );
      final edited = original.copyWith(
        blocks: <PracticePlanBlock>[
          original.blocks.single.copyWith(tempoBpm: 301),
        ],
      );

      expect(validator.validate(original, context: _context()).isValid, isTrue);
      expect(
        validator.validate(edited, context: _context()).codes,
        contains(PracticePlanValidationCode.tempoOutOfRange),
      );
    });
  });
}

PracticePlanValidationContext _context({
  Set<String> songIds = const <String>{},
  Set<String> practiceTargetIds = const <String>{'target'},
  Set<String> userAvoidList = const <String>{},
  List<String> activeTuning = const <String>[],
  Set<PracticePlanCapability> capabilities = const <PracticePlanCapability>{},
  Set<SkillId> availableSkillIds = const <SkillId>{},
}) => PracticePlanValidationContext(
  songIds: songIds,
  practiceTargetIds: practiceTargetIds,
  userAvoidList: userAvoidList,
  activeTuning: activeTuning,
  capabilities: capabilities,
  availableSkillIds: availableSkillIds,
);

PracticePlanDraft _draft(PracticePlanBlock block) => PracticePlanDraft(
  id: 'plan',
  title: 'Plan',
  targetDuration: const Duration(minutes: 5),
  blocks: <PracticePlanBlock>[block],
  goalIds: const <String>[],
  rationale: 'test',
  source: PracticePlanSource.aiSuggestion,
);
