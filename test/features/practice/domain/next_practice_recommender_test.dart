// The "what next" rule set (learner-loop round): a pure, deterministic
// function of the catalog and the history. Every reason has one cell, and
// the boundary of the consolidation threshold is measured inclusively.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/next_practice_recommendation.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/next_practice_recommender.dart';

PracticeDefinition _def(
  String id, {
  PracticeDifficulty difficulty = PracticeDifficulty.beginner,
}) => PracticeDefinition(
  id: id,
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestSingleTitle',
  descriptionKey: 'practiceCatalogTestSingleDescription',
  mode: PracticeMode.strumPattern,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(80),
  totalBeats: const BeatPosition(4 * BeatPosition.ticksPerBeat),
  events: const [],
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: const ['test'],
  difficulty: difficulty,
);

PracticeHistoryEntry _entry(
  String id, {
  required String definitionId,
  required int resolved,
  int total = 10,
  DateTime? at,
}) => PracticeHistoryEntry(
  id: id,
  modeCode: PracticeMode.strumPattern.code,
  sourceCode: PracticeSource.builtin.code,
  createdAt: at ?? DateTime.utc(2026, 9, 1, 12),
  definitionId: definitionId,
  displayTitle: '',
  finishReasonCode: 'completedAllTargets',
  activeDuration: const Duration(seconds: 30),
  pausedDuration: Duration.zero,
  attemptsCount: 1,
  finalMetricSnapshot: const PracticeMetricSnapshot(
    completion: PracticeMetricDimensionAvailable(0.9),
    rhythm: PracticeMetricDimensionAvailable(0.85),
    direction: PracticeMetricDimensionAvailable(0.95),
    chord: PracticeMetricDimensionNotApplicable(),
    overall: PracticeMetricDimensionAvailable(0.9),
  ),
  totalTargets: total,
  resolvedTargets: resolved,
  scorePoints: 0,
  maxCombo: 0,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
  coachingSummary: const [],
  skillTags: const [],
);

void main() {
  final a = _def('a');
  final b = _def('b');
  final hard = _def('hard', difficulty: PracticeDifficulty.advanced);
  // Deliberately NOT easiest-first in catalog order: the recommender must
  // sort by difficulty itself.
  final catalog = [hard, a, b];

  test('an empty catalog yields no recommendation', () {
    expect(recommendNextPractice(catalog: const [], history: const []), isNull);
  });

  test('no history: the easiest catalog entry, as the first session', () {
    final rec = recommendNextPractice(catalog: catalog, history: const [])!;
    expect(rec.definition.id, 'a');
    expect(rec.reason, NextPracticeReason.firstSession);
    expect(rec.basedOn, isNull);
  });

  test('a weak last session repeats the same definition', () {
    final rec = recommendNextPractice(
      catalog: catalog,
      history: [_entry('s1', definitionId: 'a', resolved: 6)],
    )!;
    expect(rec.definition.id, 'a');
    expect(rec.reason, NextPracticeReason.repeatToConsolidate);
    expect(rec.basedOn?.id, 's1');
  });

  test('the consolidation threshold is inclusive: exactly 70% advances', () {
    final rec = recommendNextPractice(
      catalog: catalog,
      history: [_entry('s1', definitionId: 'a', resolved: 7)],
    )!;
    expect(rec.definition.id, 'b');
    expect(rec.reason, NextPracticeReason.advance);
  });

  test('a cleared session advances to the easiest unplayed definition', () {
    final rec = recommendNextPractice(
      catalog: catalog,
      history: [
        _entry('s1', definitionId: 'a', resolved: 10),
        _entry(
          's2',
          definitionId: 'b',
          resolved: 10,
          at: DateTime.utc(2026, 9, 2),
        ),
      ],
    )!;
    expect(rec.definition.id, 'hard');
    expect(rec.reason, NextPracticeReason.advance);
  });

  test('everything played: the weakest latest coverage wins', () {
    final rec = recommendNextPractice(
      catalog: catalog,
      history: [
        _entry('s1', definitionId: 'a', resolved: 8),
        _entry(
          's2',
          definitionId: 'b',
          resolved: 9,
          at: DateTime.utc(2026, 9, 2),
        ),
        // 'b' was weak once but its LATEST session is strong.
        _entry(
          's0',
          definitionId: 'b',
          resolved: 1,
          at: DateTime.utc(2026, 8, 1),
        ),
        _entry(
          's3',
          definitionId: 'hard',
          resolved: 10,
          at: DateTime.utc(2026, 9, 3),
        ),
      ],
    )!;
    expect(rec.definition.id, 'a');
    expect(rec.reason, NextPracticeReason.revisitWeakest);
    expect(rec.basedOn?.id, 's1');
  });

  test('the latest (not yet persisted) session decides, not the history', () {
    final rec = recommendNextPractice(
      catalog: catalog,
      history: [_entry('s1', definitionId: 'a', resolved: 10)],
      latest: _entry(
        's2',
        definitionId: 'b',
        resolved: 2,
        at: DateTime.utc(2026, 9, 2),
      ),
    )!;
    expect(rec.definition.id, 'b');
    expect(rec.reason, NextPracticeReason.repeatToConsolidate);
  });

  test('a latest entry already in the history is not counted twice', () {
    final s1 = _entry('s1', definitionId: 'a', resolved: 10);
    final rec = recommendNextPractice(
      catalog: catalog,
      history: [s1],
      latest: s1,
    )!;
    expect(rec.definition.id, 'b');
    expect(rec.reason, NextPracticeReason.advance);
  });

  test('a session with no scored targets neither passes nor fails', () {
    final rec = recommendNextPractice(
      catalog: catalog,
      history: [_entry('s1', definitionId: 'a', resolved: 0, total: 0)],
    )!;
    expect(rec.definition.id, 'b');
    expect(rec.reason, NextPracticeReason.advance);
  });

  test('a history entry for a definition no longer in the catalog is ignored '
      'as a target but still counts as "played"', () {
    final rec = recommendNextPractice(
      catalog: [a],
      history: [_entry('s1', definitionId: 'gone', resolved: 1)],
    )!;
    expect(rec.definition.id, 'a');
    expect(rec.reason, NextPracticeReason.advance);
  });
}
