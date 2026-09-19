/// The producer for [PracticePlanTargetInput] — the one
/// [PracticePlanCompilationContext] input that had NO source in `lib/`
/// (WP-H2, 2026-09-06; measured in `docs/ui/remaining-wiring-blockers.md` §2).
///
/// It binds the block skeleton of a [PracticePlanDraft] to REAL, shipped
/// practice definitions and produces the matching [PracticeSessionConfig] for
/// each bound block. Two real sources feed it, both read through public
/// feature boundaries:
///
/// * **`practice/public.dart` → the built-in practice catalog** — the shipped
///   [PracticeDefinition] list (`BuiltinPracticeCatalog`). This is the ONLY
///   inventory of runnable exercises in the app, so a plan block can only ever
///   name one of these.
/// * **`practice/public.dart` → the practice history repository** — the
///   learner's finished sessions ([PracticeHistoryEntry]). Two measured facts
///   are used, never invented: (a) when a definition was last practiced, which
///   orders otherwise-equal candidates least-recently-practiced first, and
///   (b) [PracticeHistoryEntry.highestStableTempoBpm], which becomes the
///   block's effective tempo instead of the catalog default.
///
/// The learner's ACTIVE [LearningGoal]s (the tutor profile surface) steer the
/// choice: [_goalCatalogTags] is the explicit, declared mapping between the
/// goal taxonomy and the catalog's own `skillTags` vocabulary. Two goal
/// categories map to the EMPTY set on purpose — the shipped catalog contains
/// no pitch-accuracy and no theory exercise, and inventing one would be
/// exactly the fabrication this producer exists to avoid.
///
/// ## What is honestly absent
///
/// * A block type with no runnable mode (`reflection`, `rest`, `songRange`)
///   is left as a plain timer block ([PracticePlanBlockAdapter.none]) — the
///   compiler then produces a block with no definition and no config, which
///   is the truth: there is nothing to launch for it.
/// * When the catalog yields no candidate for a block, the block also stays a
///   plain timer block and [PracticePlanInputCode.practiceTargetsAbsent] is
///   reported.
/// * `requiredSkillIds` is always empty. Measured: the catalog's `skillTags`
///   vocabulary (`'downstrokes'`, `'quarterNotes'`, `'chordChanges'`, …) and
///   the tutor's `SkillTaxonomy.initial` ids (`'strum.downStroke'`,
///   `'rhythm.pulse'`, …) are DISJOINT — there is no mapping table between
///   them anywhere in the tree. Declaring a required skill would therefore be
///   a guess, so no block declares one.
library;

import 'package:strumsight/features/practice/public.dart';

import '../../domain/models/learning_goal.dart';
import '../../domain/models/practice_plan_block.dart';
import 'practice_plan_compiler.dart';

/// Stable, machine-readable codes for a compilation input this build cannot
/// supply. They are reported, never silently defaulted away.
abstract final class PracticePlanInputCode {
  /// No ACTIVE learning goal exists, so nothing steers the block choice.
  static const String goalsAbsent = 'practicePlanInput.goals.absent';

  /// The practice history is empty — no measured tempo, no recency order.
  static const String historyAbsent = 'practicePlanInput.history.absent';

  /// The practice history could not be READ (storage failure). Distinct from
  /// [historyAbsent]: an empty songbook is a fact, a failed read is an error.
  static const String historyUnavailable =
      'practicePlanInput.history.unavailable';

  /// The songbook is empty, so no song block can be validated or compiled.
  static const String songsAbsent = 'practicePlanInput.songs.absent';

  /// At least one block could not be bound to a runnable practice target.
  static const String practiceTargetsAbsent =
      'practicePlanInput.practiceTargets.absent';

  /// No active tuning is recorded on the guitar profile.
  static const String tuningAbsent = 'practicePlanInput.tuning.absent';
}

/// The bound blocks plus the target map they reference.
final class PracticePlanTargetSelection {
  PracticePlanTargetSelection({
    required List<PracticePlanBlock> blocks,
    required Map<String, PracticePlanTargetInput> targets,
    required Set<String> absentInputs,
  }) : blocks = List<PracticePlanBlock>.unmodifiable(blocks),
       targets = Map<String, PracticePlanTargetInput>.unmodifiable(targets),
       absentInputs = Set<String>.unmodifiable(absentInputs);

  /// The input blocks, with every bindable one replaced by a
  /// [PracticePlanBlockAdapter.practiceTarget] block.
  final List<PracticePlanBlock> blocks;

  /// Keyed by [PracticeDefinition.id] — the value the bound blocks carry in
  /// [PracticePlanBlock.practiceTargetId].
  final Map<String, PracticePlanTargetInput> targets;

  /// [PracticePlanInputCode] values this producer measured as absent.
  final Set<String> absentInputs;
}

/// Binds plan blocks to real catalog definitions. Pure: every input is
/// supplied by the caller, there is no wall clock and no storage access.
final class PracticePlanTargetSource {
  const PracticePlanTargetSource();

  /// Rebinds [templateBlocks] onto the catalog.
  ///
  /// A definition is used at most once per plan: a ten-minute plan that
  /// prescribed the same exercise twice would be a worse plan, and the
  /// per-definition [PracticeSessionConfig] carries the block's own duration
  /// as its `sessionTimeout`, so one definition cannot serve two durations.
  PracticePlanTargetSelection bind({
    required List<PracticePlanBlock> templateBlocks,
    required List<PracticeDefinition> catalog,
    required List<PracticeHistoryEntry> history,
    required List<LearningGoal> activeGoals,
  }) {
    final goalTags = <String>{
      for (final goal in activeGoals) ..._goalCatalogTags[goal.category]!,
    };
    final lastPracticed = _lastPracticedByDefinition(history);
    final bestTempo = _bestStableTempoByDefinition(history);

    final used = <String>{};
    final blocks = <PracticePlanBlock>[];
    final targets = <String, PracticePlanTargetInput>{};
    var unboundBlocks = 0;

    for (final block in templateBlocks) {
      final definition = _pick(
        blockType: block.type,
        catalog: catalog,
        goalTags: goalTags,
        lastPracticed: lastPracticed,
        used: used,
      );
      if (definition == null) {
        if (_runnableModes.containsKey(block.type)) unboundBlocks++;
        blocks.add(block);
        continue;
      }
      used.add(definition.id);
      final tempo = _effectiveTempo(definition, bestTempo[definition.id]);
      targets[definition.id] = PracticePlanTargetInput(
        definition: definition,
        config: _configFor(
          definition: definition,
          tempo: tempo,
          sessionTimeout: block.duration,
        ),
      );
      blocks.add(
        PracticePlanBlock.practiceTarget(
          id: block.id,
          type: block.type,
          duration: block.duration,
          practiceTargetId: definition.id,
          tempoBpm: tempo.bpm,
          requiredCapabilities: const <PracticePlanCapability>{
            PracticePlanCapability.practiceTarget,
          },
        ),
      );
    }

    return PracticePlanTargetSelection(
      blocks: blocks,
      targets: targets,
      absentInputs: <String>{
        if (activeGoals.isEmpty) PracticePlanInputCode.goalsAbsent,
        if (history.isEmpty) PracticePlanInputCode.historyAbsent,
        if (unboundBlocks > 0) PracticePlanInputCode.practiceTargetsAbsent,
      },
    );
  }

  PracticeDefinition? _pick({
    required String blockType,
    required List<PracticeDefinition> catalog,
    required Set<String> goalTags,
    required Map<String, DateTime> lastPracticed,
    required Set<String> used,
  }) {
    final modes = _runnableModes[blockType];
    if (modes == null) return null;

    final candidates = <_Candidate>[];
    for (var index = 0; index < catalog.length; index++) {
      final definition = catalog[index];
      if (used.contains(definition.id)) continue;
      final modeRank = modes.indexOf(definition.mode);
      if (modeRank < 0) continue;
      candidates.add(
        _Candidate(
          definition: definition,
          modeRank: modeRank,
          goalOverlap: definition.skillTags.where(goalTags.contains).length,
          lastPracticed: lastPracticed[definition.id],
          catalogIndex: index,
        ),
      );
    }
    if (candidates.isEmpty) return null;
    candidates.sort(_compareCandidates);
    return candidates.first.definition;
  }

  Tempo _effectiveTempo(PracticeDefinition definition, double? measuredBpm) {
    if (measuredBpm == null) return definition.defaultTempo;
    final measured = Tempo(measuredBpm);
    // The domain never clamps a tempo, so an out-of-range measurement falls
    // back to the catalog default instead of producing an invalid block.
    return measured.validate().isEmpty ? measured : definition.defaultTempo;
  }

  /// Seeds the session config from the definition, exactly like the Practice
  /// Setup screen does, with two plan-specific overrides: the effective tempo
  /// (measured when the history has one) and the session timeout (the block's
  /// own duration, not a fixed five minutes).
  PracticeSessionConfig _configFor({
    required PracticeDefinition definition,
    required Tempo tempo,
    required Duration sessionTimeout,
  }) => PracticeSessionConfig(
    definitionId: definition.id,
    definitionSnapshotVersion: definition.schemaVersion,
    effectiveTempo: tempo,
    countInBars: 1,
    loopCount: 1,
    metronomeEnabled: true,
    accentEnabled: true,
    backingEnabled: false,
    scoringProfileId: definition.scoringProfile.id,
    inputLatency: Duration.zero,
    visualLatency: Duration.zero,
    expectedChordHintEnabled: true,
    sessionTimeout: sessionTimeout,
    reducedMotion: false,
  );
}

final class _Candidate {
  const _Candidate({
    required this.definition,
    required this.modeRank,
    required this.goalOverlap,
    required this.lastPracticed,
    required this.catalogIndex,
  });

  final PracticeDefinition definition;
  final int modeRank;
  final int goalOverlap;
  final DateTime? lastPracticed;
  final int catalogIndex;
}

int _compareCandidates(_Candidate left, _Candidate right) {
  // 1. The learner's active goals win.
  if (left.goalOverlap != right.goalOverlap) {
    return right.goalOverlap.compareTo(left.goalOverlap);
  }
  // 2. The mode the block type prefers.
  if (left.modeRank != right.modeRank) {
    return left.modeRank.compareTo(right.modeRank);
  }
  // 3. Least recently practiced first; never practiced is "longest ago".
  final leftAt = left.lastPracticed;
  final rightAt = right.lastPracticed;
  if (leftAt == null && rightAt != null) return -1;
  if (leftAt != null && rightAt == null) return 1;
  if (leftAt != null && rightAt != null && leftAt != rightAt) {
    return leftAt.compareTo(rightAt);
  }
  // 4. Catalog declaration order — the documented stable tie-break.
  return left.catalogIndex.compareTo(right.catalogIndex);
}

Map<String, DateTime> _lastPracticedByDefinition(
  List<PracticeHistoryEntry> history,
) {
  final result = <String, DateTime>{};
  for (final entry in history) {
    final current = result[entry.definitionId];
    if (current == null || entry.createdAt.isAfter(current)) {
      result[entry.definitionId] = entry.createdAt;
    }
  }
  return result;
}

Map<String, double> _bestStableTempoByDefinition(
  List<PracticeHistoryEntry> history,
) {
  final result = <String, double>{};
  for (final entry in history) {
    final bpm = entry.highestStableTempoBpm;
    if (bpm == null) continue;
    final current = result[entry.definitionId];
    if (current == null || bpm > current) {
      result[entry.definitionId] = bpm;
    }
  }
  return result;
}

/// The practice modes that can honestly run one plan block type, best first.
/// A block type absent from this map has no runnable exercise by design
/// (`reflection` and `rest` are not exercises; `songRange` is served by the
/// compiler's song adapter, not by a catalog definition).
const Map<String, List<PracticeMode>>
_runnableModes = <String, List<PracticeMode>>{
  PracticePlanBlockType.warmup: <PracticeMode>[
    PracticeMode.strumPattern,
    PracticeMode.rhythmOnly,
  ],
  PracticePlanBlockType.technique: <PracticeMode>[
    PracticeMode.chordChanges,
    PracticeMode.chordProgression,
  ],
  PracticePlanBlockType.rhythm: <PracticeMode>[
    PracticeMode.rhythmOnly,
    PracticeMode.strumPattern,
  ],
  PracticePlanBlockType.chordChange: <PracticeMode>[PracticeMode.chordChanges],
  PracticePlanBlockType.speedBuilder: <PracticeMode>[PracticeMode.strumPattern],
  PracticePlanBlockType.freePractice: <PracticeMode>[PracticeMode.freePractice],
};

/// The declared bridge between the goal taxonomy and the catalog's own
/// `skillTags` vocabulary. The two EMPTY entries are measured facts, not
/// oversights: the shipped catalog has no pitch-accuracy and no theory
/// exercise, so those goals cannot steer the choice at all.
const Map<LearningGoalCategory, Set<String>> _goalCatalogTags =
    <LearningGoalCategory, Set<String>>{
      LearningGoalCategory.improveRhythm: <String>{
        'rhythm',
        'rhythmOnly',
        'quarterNotes',
        'eighthNotes',
        'offBeat',
        'syncopation',
      },
      LearningGoalCategory.cleanChordChanges: <String>{
        'chordChanges',
        'openChords',
        'minorChords',
      },
      LearningGoalCategory.learnSong: <String>{
        'chordProgression',
        'pop',
        'fourChords',
      },
      LearningGoalCategory.increaseStableTempo: <String>{
        'quarterNotes',
        'rhythmOnly',
        'alternating',
      },
      LearningGoalCategory.buildPracticeHabit: <String>{'freePlay', 'open'},
      LearningGoalCategory.improvePitchAccuracy: <String>{},
      LearningGoalCategory.understandTheory: <String>{},
    };
