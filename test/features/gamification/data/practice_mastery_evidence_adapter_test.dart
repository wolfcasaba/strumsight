// E16-R02 §6 A9 (ADR 0500 §5.5) — the practice-history → mastery-evidence
// adapter drops unmeasurable sessions instead of fabricating a 0 or an
// assumed difficulty, and maps the measurable ones from real fields only.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice/public.dart';

final _catalog = const BuiltinPracticeCatalog().all();

PracticeDefinition _definition(String id) =>
    _catalog.firstWhere((definition) => definition.id == id);

MasteryMilestone _chordMilestone({
  MasteryDifficulty difficulty = MasteryDifficulty.beginner,
}) => MasteryMilestone(
  id: 'mastery_chord_transition_v1',
  catalogVersion: 1,
  skill: MasterySkill.chordTransition,
  metric: MasteryMetric.accuracy,
  minimumThreshold: 0.8,
  difficulty: difficulty,
  tempoRange: MasteryTempoRange(minBpm: 40, maxBpm: 240),
  minEvidenceSessions: 3,
  titleKey: 'masteryChordTransitionTitle',
  descriptionKey: 'masteryChordTransitionDescription',
);

PracticeMetricSnapshot _snapshot({
  PracticeMetricDimension? chord,
  PracticeMetricDimension? rhythm,
  PracticeMetricDimension? direction,
}) => PracticeMetricSnapshot(
  completion: const PracticeMetricDimensionNotApplicable(),
  rhythm: rhythm ?? const PracticeMetricDimensionNotApplicable(),
  direction: direction ?? const PracticeMetricDimensionNotApplicable(),
  chord: chord ?? const PracticeMetricDimensionNotApplicable(),
  overall: const PracticeMetricDimensionNotApplicable(),
);

PracticeHistoryEntry _entry({
  String id = 'session-1',
  String definitionId = 'builtin.quarterDownstrokes.v1',
  DateTime? createdAt,
  required PracticeMetricSnapshot snapshot,
}) => PracticeHistoryEntry(
  id: id,
  modeCode: 'practice.mode.strumPattern',
  sourceCode: 'builtin',
  createdAt: createdAt ?? DateTime.utc(2026, 8, 1),
  definitionId: definitionId,
  displayTitle: '',
  finishReasonCode: PracticeFinishReason.completedAllTargets.code,
  activeDuration: const Duration(seconds: 30),
  pausedDuration: Duration.zero,
  attemptsCount: 1,
  finalMetricSnapshot: snapshot,
  totalTargets: 4,
  resolvedTargets: 4,
  scorePoints: 100,
  maxCombo: 4,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
  coachingSummary: const <String>[],
  skillTags: const <String>[],
);

void main() {
  group('masteryEvidenceFromPracticeHistoryEntry — A9', () {
    test(
      'a measured, known-definition session maps to real MasteryEvidence fields',
      () {
        final entry = _entry(
          id: 'session-77',
          definitionId: 'builtin.quarterDownstrokes.v1',
          createdAt: DateTime.utc(2026, 8, 5, 10),
          snapshot: _snapshot(chord: PracticeMetricDimension.available(0.91)),
        );

        final evidence = masteryEvidenceFromPracticeHistoryEntry(
          entry: entry,
          milestone: _chordMilestone(),
          practiceCatalog: _catalog,
        );

        expect(evidence, isNotNull);
        expect(evidence!.sessionId, 'session-77');
        expect(evidence.origin, MasteryEvidenceOrigin.device);
        expect(evidence.difficulty, MasteryDifficulty.beginner);
        expect(
          evidence.tempoBpm,
          _definition('builtin.quarterDownstrokes.v1').defaultTempo.bpm,
        );
        expect(evidence.metricValue, 0.91);
        expect(evidence.observedAt, DateTime.utc(2026, 8, 5, 10));
        expect(evidence.confidence, isNull);
      },
    );

    test(
      'an intermediate definition maps to MasteryDifficulty.intermediate',
      () {
        final entry = _entry(
          definitionId: 'builtin.cGAmFProgression.v1',
          snapshot: _snapshot(chord: PracticeMetricDimension.available(0.85)),
        );

        final evidence = masteryEvidenceFromPracticeHistoryEntry(
          entry: entry,
          milestone: _chordMilestone(),
          practiceCatalog: _catalog,
        );

        expect(evidence!.difficulty, MasteryDifficulty.intermediate);
      },
    );

    test(
      'a notApplicable dimension yields NO evidence — never a 0 metricValue',
      () {
        final entry = _entry(
          snapshot: _snapshot(
            chord: const PracticeMetricDimensionNotApplicable(),
          ),
        );

        final evidence = masteryEvidenceFromPracticeHistoryEntry(
          entry: entry,
          milestone: _chordMilestone(),
          practiceCatalog: _catalog,
        );

        expect(evidence, isNull);
      },
    );

    test('an insufficientData dimension yields NO evidence', () {
      final entry = _entry(
        snapshot: _snapshot(
          chord: const PracticeMetricDimensionInsufficientData(
            'practice.metric.no_signal',
          ),
        ),
      );

      final evidence = masteryEvidenceFromPracticeHistoryEntry(
        entry: entry,
        milestone: _chordMilestone(),
        practiceCatalog: _catalog,
      );

      expect(evidence, isNull);
    });

    test(
      'an unknown definitionId yields NO evidence — never a "beginner" guess',
      () {
        final entry = _entry(
          definitionId: 'builtin.doesNotExist.v1',
          snapshot: _snapshot(chord: PracticeMetricDimension.available(0.95)),
        );

        final evidence = masteryEvidenceFromPracticeHistoryEntry(
          entry: entry,
          milestone: _chordMilestone(),
          practiceCatalog: _catalog,
        );

        expect(evidence, isNull);
      },
    );

    test(
      'a skill with no mapped PracticeMetricSnapshot dimension (tempoStability) '
      'never produces evidence, regardless of what the snapshot carries',
      () {
        final tempoStabilityMilestone = MasteryMilestone(
          id: 'mastery_tempo_stability_probe',
          catalogVersion: 1,
          skill: MasterySkill.tempoStability,
          metric: MasteryMetric.tempoAdherence,
          minimumThreshold: 0.8,
          difficulty: MasteryDifficulty.beginner,
          tempoRange: MasteryTempoRange(minBpm: 40, maxBpm: 240),
          minEvidenceSessions: 3,
          titleKey: 'probeTitle',
          descriptionKey: 'probeDescription',
        );
        final entry = _entry(
          snapshot: _snapshot(
            chord: PracticeMetricDimension.available(0.99),
            rhythm: PracticeMetricDimension.available(0.99),
            direction: PracticeMetricDimension.available(0.99),
          ),
        );

        final evidence = masteryEvidenceFromPracticeHistoryEntry(
          entry: entry,
          milestone: tempoStabilityMilestone,
          practiceCatalog: _catalog,
        );

        expect(evidence, isNull);
      },
    );

    test('rhythmAccuracy reads the .rhythm dimension, not .chord', () {
      final milestone = MasteryMilestone(
        id: 'mastery_rhythm_accuracy_v1',
        catalogVersion: 1,
        skill: MasterySkill.rhythmAccuracy,
        metric: MasteryMetric.accuracy,
        minimumThreshold: 0.8,
        difficulty: MasteryDifficulty.beginner,
        tempoRange: MasteryTempoRange(minBpm: 40, maxBpm: 240),
        minEvidenceSessions: 3,
        titleKey: 'masteryRhythmAccuracyTitle',
        descriptionKey: 'masteryRhythmAccuracyDescription',
      );
      final entry = _entry(
        snapshot: _snapshot(
          chord: PracticeMetricDimension.available(0.1),
          rhythm: PracticeMetricDimension.available(0.87),
        ),
      );

      final evidence = masteryEvidenceFromPracticeHistoryEntry(
        entry: entry,
        milestone: milestone,
        practiceCatalog: _catalog,
      );

      expect(evidence!.metricValue, 0.87);
    });
  });

  group('masteryEvidenceFromPracticeHistory — batch mapping', () {
    test(
      'keeps only measurable entries, in input order, dropping the rest',
      () {
        final history = <PracticeHistoryEntry>[
          _entry(
            id: 'measured-1',
            createdAt: DateTime.utc(2026, 8, 1),
            snapshot: _snapshot(chord: PracticeMetricDimension.available(0.9)),
          ),
          _entry(
            id: 'not-applicable',
            createdAt: DateTime.utc(2026, 8, 2),
            snapshot: _snapshot(
              chord: const PracticeMetricDimensionNotApplicable(),
            ),
          ),
          _entry(
            id: 'unknown-definition',
            definitionId: 'builtin.doesNotExist.v1',
            createdAt: DateTime.utc(2026, 8, 3),
            snapshot: _snapshot(chord: PracticeMetricDimension.available(0.9)),
          ),
          _entry(
            id: 'measured-2',
            createdAt: DateTime.utc(2026, 8, 4),
            snapshot: _snapshot(chord: PracticeMetricDimension.available(0.95)),
          ),
        ];

        final evidence = masteryEvidenceFromPracticeHistory(
          history: history,
          milestone: _chordMilestone(),
          practiceCatalog: _catalog,
        );

        expect(
          evidence.map((sample) => sample.sessionId),
          orderedEquals(<String>['measured-1', 'measured-2']),
        );
      },
    );

    test('an empty history yields empty evidence, not a synthetic sample', () {
      final evidence = masteryEvidenceFromPracticeHistory(
        history: const <PracticeHistoryEntry>[],
        milestone: _chordMilestone(),
        practiceCatalog: _catalog,
      );

      expect(evidence, isEmpty);
    });
  });
}
