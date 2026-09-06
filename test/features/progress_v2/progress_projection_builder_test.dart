// E16-R02 §6 A3/A4/A6/A12 (ADR 0500 §5.1/§5.2) — the projection builder is
// deterministic, never fabricates a measurement, reads no clock/RNG, and the
// achievement threshold/session-count boundaries are exactly inclusive.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

final _practiceCatalog = const BuiltinPracticeCatalog().all();
const _beginnerDefinitionId = 'builtin.quarterDownstrokes.v1';

String _localize(String key) => key;

PracticeMetricSnapshot _snapshot({PracticeMetricDimension? chord}) =>
    PracticeMetricSnapshot(
      completion: const PracticeMetricDimensionNotApplicable(),
      rhythm: const PracticeMetricDimensionNotApplicable(),
      direction: const PracticeMetricDimensionNotApplicable(),
      chord: chord ?? const PracticeMetricDimensionNotApplicable(),
      overall: chord ?? const PracticeMetricDimensionNotApplicable(),
    );

PracticeHistoryEntry _session({
  required String id,
  required DateTime createdAt,
  String definitionId = _beginnerDefinitionId,
  PracticeMetricDimension? chord,
}) => PracticeHistoryEntry(
  id: id,
  modeCode: 'practice.mode.strumPattern',
  sourceCode: 'builtin',
  createdAt: createdAt,
  definitionId: definitionId,
  displayTitle: '',
  finishReasonCode: PracticeFinishReason.completedAllTargets.code,
  activeDuration: const Duration(seconds: 30),
  pausedDuration: Duration.zero,
  attemptsCount: 1,
  finalMetricSnapshot: _snapshot(chord: chord),
  totalTargets: 4,
  resolvedTargets: 4,
  scorePoints: 100,
  maxCombo: 4,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
  coachingSummary: const <String>[],
  skillTags: const <String>[],
);

List<PracticeHistoryEntry> _chordSessions(int count, double metricValue) => [
  for (var i = 0; i < count; i++)
    _session(
      id: 'chord-$metricValue-$i',
      createdAt: DateTime.utc(2026, 8, 1 + i),
      chord: PracticeMetricDimension.available(metricValue),
    ),
];

MasteryMilestone get _chordMilestone => masteryMilestoneCatalogV1.firstWhere(
  (milestone) => milestone.skill == MasterySkill.chordTransition,
);

void main() {
  final now = DateTime.utc(2026, 8, 20);

  group('A3 — the builder is deterministic', () {
    test('the same history/catalog/now yields the same projection twice', () {
      final history = _chordSessions(3, 0.9);

      final first = buildProgressOverviewProjection(
        milestoneCatalog: masteryMilestoneCatalogV1,
        practiceHistory: history,
        practiceCatalog: _practiceCatalog,
        now: now,
        isOffline: false,
        localize: _localize,
      );
      final second = buildProgressOverviewProjection(
        milestoneCatalog: masteryMilestoneCatalogV1,
        practiceHistory: history,
        practiceCatalog: _practiceCatalog,
        now: now,
        isOffline: false,
        localize: _localize,
      );

      expect(first.milestones.length, second.milestones.length);
      for (var i = 0; i < first.milestones.length; i++) {
        expect(
          first.milestones[i].progress.evidenceSessionCount,
          second.milestones[i].progress.evidenceSessionCount,
        );
        expect(
          first.milestones[i].progress.isAchieved,
          second.milestones[i].progress.isAchieved,
        );
        expect(
          first.milestones[i].hasEvidence,
          second.milestones[i].hasEvidence,
        );
      }
      expect(
        first.trend.points.map((p) => p.value),
        second.trend.points.map((p) => p.value),
      );
      expect(first.isNewUser, second.isNewUser);
    });
  });

  group('A4 — missing measurement is never fabricated as zero', () {
    test(
      'a milestone with only notApplicable evidence has zero evidenceSessionCount, '
      'not a computed-zero ratio',
      () {
        final history = [
          _session(
            id: 'na-1',
            createdAt: DateTime.utc(2026, 8, 1),
            chord: const PracticeMetricDimensionNotApplicable(),
          ),
          _session(
            id: 'na-2',
            createdAt: DateTime.utc(2026, 8, 2),
            chord: const PracticeMetricDimensionNotApplicable(),
          ),
        ];

        final overview = buildProgressOverviewProjection(
          milestoneCatalog: masteryMilestoneCatalogV1,
          practiceHistory: history,
          practiceCatalog: _practiceCatalog,
          now: now,
          isOffline: false,
          localize: _localize,
        );

        final chordEntry = overview.milestones.firstWhere(
          (entry) => entry.milestone.skill == MasterySkill.chordTransition,
        );
        expect(chordEntry.hasEvidence, isFalse);
        expect(chordEntry.progress.evidenceSessionCount, 0);
      },
    );

    test('a sibling milestone with real evidence still measures — proves the '
        'gap is per-milestone, not a global suppression', () {
      final history = [
        _session(
          id: 'na-1',
          createdAt: DateTime.utc(2026, 8, 1),
          chord: const PracticeMetricDimensionNotApplicable(),
        ),
        ..._chordSessions(3, 0.9),
      ];

      final overview = buildProgressOverviewProjection(
        milestoneCatalog: masteryMilestoneCatalogV1,
        practiceHistory: history,
        practiceCatalog: _practiceCatalog,
        now: now,
        isOffline: false,
        localize: _localize,
      );

      final chordEntry = overview.milestones.firstWhere(
        (entry) => entry.milestone.skill == MasterySkill.chordTransition,
      );
      expect(chordEntry.hasEvidence, isTrue);
      expect(chordEntry.progress.evidenceSessionCount, 3);
    });

    test(
      'an unknown definitionId contributes no evidence anywhere, not a "beginner" guess',
      () {
        final history = [
          _session(
            id: 'unknown-def',
            createdAt: DateTime.utc(2026, 8, 1),
            definitionId: 'builtin.doesNotExist.v1',
            chord: PracticeMetricDimension.available(0.99),
          ),
        ];

        final overview = buildProgressOverviewProjection(
          milestoneCatalog: masteryMilestoneCatalogV1,
          practiceHistory: history,
          practiceCatalog: _practiceCatalog,
          now: now,
          isOffline: false,
          localize: _localize,
        );

        for (final entry in overview.milestones) {
          expect(entry.hasEvidence, isFalse, reason: entry.milestone.id);
        }
      },
    );
  });

  group('A6 — the builder reads no clock and no RNG', () {
    test('the source file contains neither DateTime.now() nor Random(', () {
      final source = _readBuilderSource();
      expect(source.contains('DateTime.now()'), isFalse);
      expect(source.contains('Random('), isFalse);
    });
  });

  group(
    'MINOR-1 (review) — every v1 milestone titleKey/descriptionKey resolves '
    'to real ARB text, not the raw key',
    () {
      test('all 3 catalog milestones resolve both keys through '
          'progressV2LocalizedText (6 keys total — the silent `_ => key` '
          'fallback branch stays exercised)', () {
        final l10n = AppLocalizationsEn();
        for (final milestone in masteryMilestoneCatalogV1) {
          final title = progressV2LocalizedText(l10n, milestone.titleKey);
          final description = progressV2LocalizedText(
            l10n,
            milestone.descriptionKey,
          );
          expect(title, isNot(milestone.titleKey), reason: milestone.id);
          expect(
            description,
            isNot(milestone.descriptionKey),
            reason: milestone.id,
          );
          expect(title, isNotEmpty, reason: milestone.id);
          expect(description, isNotEmpty, reason: milestone.id);
        }
      });
    },
  );

  group('A12 — minimumThreshold and minEvidenceSessions boundaries', () {
    test('0.79 (just below 0.8) never achieves, at 3 sessions', () {
      final progress = _evaluateChord(_chordSessions(3, 0.79), now);
      expect(progress.isAchieved, isFalse);
    });

    test('0.80 (exactly on the threshold) achieves, at 3 sessions', () {
      final progress = _evaluateChord(_chordSessions(3, 0.80), now);
      expect(progress.isAchieved, isTrue);
    });

    test('0.81 (just above the threshold) achieves, at 3 sessions', () {
      final progress = _evaluateChord(_chordSessions(3, 0.81), now);
      expect(progress.isAchieved, isTrue);
    });

    test(
      '2 qualifying sessions never achieve (below minEvidenceSessions 3)',
      () {
        final progress = _evaluateChord(_chordSessions(2, 0.95), now);
        expect(progress.isAchieved, isFalse);
        expect(progress.evidenceSessionCount, 2);
      },
    );

    test('3 qualifying sessions achieve (exactly minEvidenceSessions)', () {
      final progress = _evaluateChord(_chordSessions(3, 0.95), now);
      expect(progress.isAchieved, isTrue);
      expect(progress.evidenceSessionCount, 3);
    });
  });
}

MasteryProgress _evaluateChord(
  List<PracticeHistoryEntry> history,
  DateTime now,
) {
  final overview = buildProgressOverviewProjection(
    milestoneCatalog: masteryMilestoneCatalogV1,
    practiceHistory: history,
    practiceCatalog: _practiceCatalog,
    now: now,
    isOffline: false,
    localize: _localize,
  );
  return overview.milestones
      .firstWhere((entry) => identical(entry.milestone, _chordMilestone))
      .progress;
}

String _readBuilderSource() => File(
  'lib/features/progress_v2/application/progress_projection_builder.dart',
).readAsStringSync();
