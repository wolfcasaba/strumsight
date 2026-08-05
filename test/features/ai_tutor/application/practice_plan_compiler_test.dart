import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/ai_tutor/application/planning/practice_plan_compiler.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_draft.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';
import 'package:strumsight/features/ai_tutor/domain/services/practice_plan_validator.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/songs/public.dart';

void main() {
  const compiler = PracticePlanCompiler();

  group('PracticePlanCompiler', () {
    test('cannot compile or launch an invalid draft', () {
      final draft = _draft(
        PracticePlanBlock.basic(
          id: 'unsupported',
          type: 'unsupported',
          duration: const Duration(minutes: 5),
        ),
      );

      final result = compiler.compile(draft: draft, context: _context());

      expect(result, isA<Failure<CompiledPracticePlan>>());
      final failure = (result as Failure<CompiledPracticePlan>).error;
      expect(failure.code, FailureCode.validationInvalidInput);
      expect(failure.cause, isA<PracticePlanValidationResult>());
      expect(
        (failure.cause! as PracticePlanValidationResult).codes,
        contains(PracticePlanValidationCode.unsupportedBlockType),
      );
    });

    test(
      'practice-target adapter is bit-stable with compilePracticeTarget',
      () {
        final definition = _definition();
        final config = _config(definition);
        final draft = _draft(
          PracticePlanBlock.practiceTarget(
            id: 'target',
            type: PracticePlanBlockType.rhythm,
            duration: const Duration(minutes: 5),
            practiceTargetId: 'target',
            requiredCapabilities: const {PracticePlanCapability.practiceTarget},
          ),
        );

        final compiled = _success(
          compiler.compile(
            draft: draft,
            context: _context(
              practiceTargets: <String, PracticePlanTargetInput>{
                'target': PracticePlanTargetInput(
                  definition: definition,
                  config: config,
                ),
              },
              capabilities: const {PracticePlanCapability.practiceTarget},
            ),
          ),
        );
        final direct = _target(
          compilePracticeTarget(definition: definition, config: config),
        );

        expect(compiled.blocks.single.compiledTarget, direct);
      },
    );

    test('song adapter is bit-stable with compilePracticeTarget', () {
      const song = Song(
        id: 'song',
        name: 'Song',
        chords: <String>['C', 'G'],
        pattern: <StrumDirection?>[
          StrumDirection.down,
          null,
          StrumDirection.up,
          null,
          StrumDirection.down,
          null,
          StrumDirection.up,
          null,
        ],
        bpm: 120,
      );
      final draft = _draft(
        PracticePlanBlock.song(
          id: 'song-range',
          duration: const Duration(minutes: 5),
          songId: song.id,
          requiredCapabilities: const {PracticePlanCapability.songRange},
        ),
      );

      final compiled = _success(
        compiler.compile(
          draft: draft,
          context: _context(
            songs: const <Song>[song],
            capabilities: const {PracticePlanCapability.songRange},
          ),
        ),
      );
      final block = compiled.blocks.single;
      final direct = _target(
        compilePracticeTarget(
          definition: block.definition!,
          config: block.config!,
        ),
      );

      expect(block.compiledTarget, direct);
      expect(compiled.isOfflineRunnable, isTrue);
    });

    test('marks a valid asset-missing plan as not offline-runnable', () {
      final draft = _draft(
        PracticePlanBlock.basic(
          id: 'online-only',
          type: PracticePlanBlockType.reflection,
          duration: const Duration(minutes: 5),
          assetAvailableLocally: false,
        ),
      );

      final compiled = _success(
        compiler.compile(draft: draft, context: _context()),
      );

      expect(compiled.isOfflineRunnable, isFalse);
    });
  });
}

CompiledPracticePlan _success(AppResult<CompiledPracticePlan> result) =>
    (result as Success<CompiledPracticePlan>).value;

CompiledPracticeTarget _target(AppResult<CompiledPracticeTarget> result) =>
    (result as Success<CompiledPracticeTarget>).value;

PracticePlanCompilationContext _context({
  List<Song> songs = const <Song>[],
  Map<String, PracticePlanTargetInput> practiceTargets =
      const <String, PracticePlanTargetInput>{},
  Set<PracticePlanCapability> capabilities = const <PracticePlanCapability>{},
}) => PracticePlanCompilationContext(
  songs: songs,
  practiceTargets: practiceTargets,
  userAvoidList: const <String>{},
  activeTuning: const <String>[],
  capabilities: capabilities,
  availableSkillIds: const <SkillId>{},
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

PracticeDefinition _definition() => const PracticeDefinition(
  id: 'definition',
  schemaVersion: 1,
  titleKey: 'practice.title',
  descriptionKey: 'practice.description',
  mode: PracticeMode.strumPattern,
  source: PracticeSource.builtin,
  meter: Meter(beatsPerBar: 4),
  defaultTempo: Tempo(120),
  totalBeats: BeatPosition(1920),
  events: <PracticeEvent>[
    PracticeEvent(
      id: 'event',
      position: BeatPosition(0),
      direction: StrumDirection.down,
    ),
  ],
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: <String>[],
);

PracticeSessionConfig _config(PracticeDefinition definition) =>
    PracticeSessionConfig(
      definitionId: definition.id,
      definitionSnapshotVersion: definition.schemaVersion,
      effectiveTempo: definition.defaultTempo,
      countInBars: 1,
      loopCount: 1,
      metronomeEnabled: true,
      accentEnabled: true,
      backingEnabled: false,
      scoringProfileId: definition.scoringProfile.id,
      inputLatency: Duration.zero,
      visualLatency: Duration.zero,
      expectedChordHintEnabled: true,
      sessionTimeout: const Duration(minutes: 5),
      reducedMotion: false,
    );
