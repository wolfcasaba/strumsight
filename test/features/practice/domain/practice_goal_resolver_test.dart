// E18-R01 emulator finding F6 — the goal → practice lookup behind the hub's
// "Browse by goal" chips.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/data/builtin_practice_catalog.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_goal_resolver.dart';

PracticeDefinition _def(
  String id, {
  required PracticeMode mode,
  PracticeDifficulty difficulty = PracticeDifficulty.beginner,
  List<String> skillTags = const [],
}) => PracticeDefinition(
  id: id,
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestSingleTitle',
  descriptionKey: 'practiceCatalogTestSingleDescription',
  mode: mode,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(80),
  totalBeats: const BeatPosition(4 * BeatPosition.ticksPerBeat),
  events: const [],
  scoringProfile: ScoringProfile.freePracticeOpen,
  skillTags: skillTags,
  difficulty: difficulty,
);

void main() {
  test('the built-in catalogue serves warm-up, chords and rhythm — and '
      'nothing else (no scales/technique content yet)', () {
    final entries = resolvePracticeGoals(BuiltinPracticeCatalog().all());
    final byGoal = {for (final e in entries) e.goal: e.definitionId};

    expect(byGoal, {
      PracticeGoal.warmup: 'builtin.quarterDownstrokes.v1',
      PracticeGoal.chords: 'builtin.gToDChanges.v1',
      PracticeGoal.rhythm: 'builtin.rhythmOnlyQuarters.v1',
    });
  });

  test('the easiest matching definition wins within a goal', () {
    final entries = resolvePracticeGoals([
      _def(
        'adv',
        mode: PracticeMode.chordChanges,
        difficulty: PracticeDifficulty.advanced,
      ),
      _def(
        'mid',
        mode: PracticeMode.chordProgression,
        difficulty: PracticeDifficulty.intermediate,
      ),
      _def('easy', mode: PracticeMode.chordChanges),
    ]);
    expect(entries.single.goal, PracticeGoal.chords);
    expect(entries.single.definitionId, 'easy');
  });

  test('scales and technique resolve by skill tag when content exists', () {
    final entries = resolvePracticeGoals([
      _def('s', mode: PracticeMode.freePractice, skillTags: ['scales']),
      _def('t', mode: PracticeMode.freePractice, skillTags: ['technique']),
    ]);
    expect(
      {for (final e in entries) e.goal: e.definitionId},
      {PracticeGoal.scales: 's', PracticeGoal.technique: 't'},
    );
  });

  test('an empty catalogue resolves to no goals at all', () {
    expect(resolvePracticeGoals(const []), isEmpty);
  });

  test('goals come out in the hub\'s display order', () {
    final entries = resolvePracticeGoals(BuiltinPracticeCatalog().all());
    expect(entries.map((e) => e.goal), [
      PracticeGoal.warmup,
      PracticeGoal.chords,
      PracticeGoal.rhythm,
    ]);
  });
}
