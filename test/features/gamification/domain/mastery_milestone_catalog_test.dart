// E16-R02 §6 A8 (ADR 0500 §5.4) — the v1 mastery-milestone catalog pins
// exactly the measured id/threshold/session/difficulty/tempo table, and
// tempoStability has no milestone (no measured tempoAdherence source).
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  group('masteryMilestoneCatalogV1 — A8', () {
    test('is exactly the three §5.4 milestones, in table order', () {
      expect(
        masteryMilestoneCatalogV1.map((milestone) => milestone.id),
        orderedEquals(<String>[
          'mastery_chord_transition_v1',
          'mastery_rhythm_accuracy_v1',
          'mastery_strum_consistency_v1',
        ]),
      );
    });

    test('every milestone pins catalogVersion 1', () {
      for (final milestone in masteryMilestoneCatalogV1) {
        expect(milestone.catalogVersion, 1, reason: milestone.id);
      }
    });

    test('every milestone pins minimumThreshold 0.8', () {
      for (final milestone in masteryMilestoneCatalogV1) {
        expect(milestone.minimumThreshold, 0.8, reason: milestone.id);
      }
    });

    test('every milestone pins minEvidenceSessions 3', () {
      for (final milestone in masteryMilestoneCatalogV1) {
        expect(milestone.minEvidenceSessions, 3, reason: milestone.id);
      }
    });

    test('every milestone is MasteryDifficulty.beginner — the MEASURED builtin '
        'majority (8 of 10 definitions), not a free choice', () {
      for (final milestone in masteryMilestoneCatalogV1) {
        expect(
          milestone.difficulty,
          MasteryDifficulty.beginner,
          reason: milestone.id,
        );
      }
    });

    test('every milestone spans the 40..240 BPM tempo range', () {
      for (final milestone in masteryMilestoneCatalogV1) {
        expect(milestone.tempoRange.minBpm, 40, reason: milestone.id);
        expect(milestone.tempoRange.maxBpm, 240, reason: milestone.id);
      }
    });

    test('each milestone maps to its own skill and the accuracy metric', () {
      final bySkill = {
        for (final milestone in masteryMilestoneCatalogV1)
          milestone.skill: milestone,
      };
      expect(
        bySkill[MasterySkill.chordTransition]?.id,
        'mastery_chord_transition_v1',
      );
      expect(
        bySkill[MasterySkill.rhythmAccuracy]?.id,
        'mastery_rhythm_accuracy_v1',
      );
      expect(
        bySkill[MasterySkill.strumConsistency]?.id,
        'mastery_strum_consistency_v1',
      );
      for (final milestone in masteryMilestoneCatalogV1) {
        expect(milestone.metric, MasteryMetric.accuracy, reason: milestone.id);
      }
    });

    test(
      'tempoStability has NO milestone — no measured tempoAdherence source',
      () {
        expect(
          masteryMilestoneCatalogV1.any(
            (milestone) => milestone.skill == MasterySkill.tempoStability,
          ),
          isFalse,
        );
      },
    );

    test('every id is lower snake case (the domain\'s own contract)', () {
      final pattern = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final milestone in masteryMilestoneCatalogV1) {
        expect(pattern.hasMatch(milestone.id), isTrue, reason: milestone.id);
      }
    });

    test('the catalog is unmodifiable', () {
      expect(
        () => masteryMilestoneCatalogV1.add(masteryMilestoneCatalogV1.first),
        throwsUnsupportedError,
      );
    });
  });
}
