import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/public.dart';

void main() {
  group('MasteryEvaluator', () {
    const evaluator = MasteryEvaluator();
    final now = DateTime.utc(2026, 8, 21, 12);
    final milestone = MasteryMilestone(
      id: 'rhythm_accuracy_intermediate',
      catalogVersion: 1,
      skill: MasterySkill.rhythmAccuracy,
      metric: MasteryMetric.accuracy,
      minimumThreshold: 0.92,
      difficulty: MasteryDifficulty.intermediate,
      tempoRange: MasteryTempoRange(minBpm: 80, maxBpm: 120),
      minEvidenceSessions: 2,
      titleKey: 'masteryRhythmAccuracyIntermediateTitle',
      descriptionKey: 'masteryRhythmAccuracyIntermediateDescription',
    );

    MasteryEvidence session({
      String id = 'session',
      MasteryEvidenceOrigin origin = MasteryEvidenceOrigin.device,
      MasteryDifficulty difficulty = MasteryDifficulty.intermediate,
      num tempoBpm = 100,
      num metricValue = 0.95,
      double? confidence = 0.9,
      DateTime? observedAt,
    }) {
      return MasteryEvidence(
        sessionId: id,
        origin: origin,
        difficulty: difficulty,
        tempoBpm: tempoBpm,
        metricValue: metricValue,
        observedAt: observedAt ?? now,
        confidence: confidence,
      );
    }

    test('A1: mastery surface carries no XP / level / ledger parameter — '
        'evaluate() runs without any XP-shaped argument', () {
      // Behavioral assertion of A1: a successful evaluation does not
      // require any XP, level, or ledger argument. The result is a pure
      // domain progress with no XP-shaped field.
      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[
          session(id: 'a1'),
          session(id: 'a2', observedAt: now.add(const Duration(minutes: 1))),
        ],
        now: now,
      );

      // The progress is a MasteryProgress — runtime type must be in the
      // mastery domain, never XP-shaped.
      expect(progress.runtimeType.toString(), 'MasteryProgress');
      // Its persisted field set is the closed mastery domain — none of
      // xp, level, ledger appear as field names in the toString.
      final flat = progress.toString().toLowerCase();
      expect(flat.contains('xp'), isFalse);
      expect(flat.contains('level'), isFalse);
      expect(flat.contains('ledger'), isFalse);
      expect(flat.contains('balance'), isFalse);
    });

    test('A2: one qualifying session does not meet minEvidenceSessions=2', () {
      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[session(id: 's1')],
        now: now,
      );

      expect(progress.isAchieved, isFalse);
      expect(progress.achievedAt, isNull);
      expect(progress.badge, isNull);
      expect(progress.evidenceSessionCount, 1);
      expect(progress.progressValue(milestone), 0.5);
    });

    test('A3: two segments from the same sessionId count as ONE evidence '
        '(distinct-session boundary not crossed)', () {
      // Two segments of a single physical session: same sessionId, two
      // slightly different metricValues. The dedup must collapse them so
      // distinctSessionCount is 1, not 2 — the threshold is session-level.
      final first = session(
        id: 'session-A',
        metricValue: 0.96,
        observedAt: now.subtract(const Duration(minutes: 5)),
      );
      final second = session(
        id: 'session-A',
        metricValue: 0.93,
        observedAt: now,
      );

      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[first, second],
        now: now,
      );

      expect(progress.evidenceSessionCount, 1);
      expect(progress.isAchieved, isFalse);
      expect(progress.progressValue(milestone), 0.5);
    });

    test(
      'A4: sub-threshold Vision/Analysis confidence is excluded entirely',
      () {
        // Two vision-origin samples, both at the threshold minimum BPM and
        // above the metric threshold, BUT one has confidence=0.69 (below
        // 0.70) — it must be dropped. The single passing sample does not
        // satisfy the multi-session requirement, so no achievement.
        final subThreshold = session(
          id: 'low-confidence',
          origin: MasteryEvidenceOrigin.vision,
          confidence: 0.69,
        );
        final passing = session(
          id: 'passing',
          origin: MasteryEvidenceOrigin.analysis,
          confidence: 0.92,
        );

        final progress = evaluator.evaluate(
          milestone: milestone,
          previous: null,
          evidence: <MasteryEvidence>[subThreshold, passing],
          now: now,
        );

        expect(progress.evidenceSessionCount, 1);
        expect(progress.isAchieved, isFalse);
      },
    );

    test('A4 boundary: confidence exactly at 0.70 passes the gate', () {
      final s1 = session(
        id: 's1',
        origin: MasteryEvidenceOrigin.vision,
        confidence: 0.70,
      );
      final s2 = session(
        id: 's2',
        origin: MasteryEvidenceOrigin.analysis,
        confidence: 0.85,
        observedAt: now.add(const Duration(minutes: 10)),
      );

      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[s1, s2],
        now: now,
      );

      expect(progress.isAchieved, isTrue);
      expect(progress.badge, isNotNull);
    });

    test('A5: achieved progress survives a weaker subsequent batch', () {
      // First batch satisfies the milestone.
      final first = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[
          session(id: 's1'),
          session(
            id: 's2',
            metricValue: 0.97,
            observedAt: now.add(const Duration(minutes: 5)),
          ),
        ],
        now: now,
      );
      expect(first.isAchieved, isTrue);
      final badge = first.badge!;
      final achievedAt = first.achievedAt!;

      // A much weaker batch arrives — should NOT revoke the achievement.
      final weak = <MasteryEvidence>[
        session(id: 'weak-1', metricValue: 0.40),
        session(
          id: 'weak-2',
          metricValue: 0.30,
          observedAt: now.add(const Duration(days: 1)),
        ),
      ];

      final after = evaluator.evaluate(
        milestone: milestone,
        previous: first,
        evidence: weak,
        now: now.add(const Duration(days: 2)),
      );

      expect(after.isAchieved, isTrue);
      expect(after.achievedAt, achievedAt);
      expect(after.badge, badge);
    });

    test('A6: evidence with mismatched difficulty is excluded', () {
      // Three samples: one beginner (wrong difficulty), two device-origin
      // at the right difficulty and tempo. Distinct qualifying sessions
      // = 2 → milestone achieved.
      final beginner = session(
        id: 'beginner',
        difficulty: MasteryDifficulty.beginner,
        tempoBpm: 70, // out of range AND wrong difficulty
        observedAt: now,
      );
      final midA = session(
        id: 'mid-a',
        metricValue: 0.94,
        observedAt: now.add(const Duration(minutes: 1)),
      );
      final midB = session(
        id: 'mid-b',
        metricValue: 0.95,
        observedAt: now.add(const Duration(minutes: 2)),
      );

      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[beginner, midA, midB],
        now: now,
      );

      expect(progress.evidenceSessionCount, 2);
      expect(progress.isAchieved, isTrue);
    });

    test('A6: evidence outside tempo range is excluded', () {
      final outOfRange = session(
        id: 'out-of-range',
        tempoBpm: 160, // milestone tempoRange is [80,120]
        observedAt: now,
      );
      final inRangeA = session(
        id: 'a',
        tempoBpm: 95,
        observedAt: now.add(const Duration(minutes: 1)),
      );
      final inRangeB = session(
        id: 'b',
        tempoBpm: 110,
        observedAt: now.add(const Duration(minutes: 2)),
      );

      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[outOfRange, inRangeA, inRangeB],
        now: now,
      );

      expect(progress.evidenceSessionCount, 2);
      expect(progress.isAchieved, isTrue);
    });

    test(
      'A7: badge summary contains no audio / session-id / health keywords',
      () {
        // First obtain a real badge through a successful evaluation.
        final progress = evaluator.evaluate(
          milestone: milestone,
          previous: null,
          evidence: <MasteryEvidence>[
            session(id: 'p1'),
            session(id: 'p2', observedAt: now.add(const Duration(minutes: 5))),
          ],
          now: now,
        );
        final badge = progress.badge!;
        final summary = badge.toSummary();

        // The summary MUST NOT carry session ids, raw audio, or any health
        // framing — the badge is closed-form (ADR 0388 §6).
        expect(summary.keys, isNot(contains('sessionId')));
        expect(summary.keys, isNot(contains('rawAudio')));
        expect(summary.keys, isNot(contains('audio')));
        expect(summary.keys, isNot(contains('waveform')));
        expect(summary.keys, isNot(contains('freeText')));
        expect(summary.keys, isNot(contains('note')));
        expect(summary.keys, isNot(contains('injuryRisk')));
        expect(summary.keys, isNot(contains('posture')));
        expect(summary.keys, isNot(contains('pain')));
        expect(summary.keys, isNot(contains('medical')));

        // No stringified form of the badge leaks any of the forbidden tokens.
        final flat = summary.values.map((v) => v.toString()).join(' ');
        expect(flat.toLowerCase(), isNot(contains('audio')));
        expect(flat.toLowerCase(), isNot(contains('waveform')));
        expect(flat.toLowerCase(), isNot(contains('posture')));
        expect(flat.toLowerCase(), isNot(contains('injur')));
        expect(flat.toLowerCase(), isNot(contains('pain')));
        expect(flat.toLowerCase(), isNot(contains('session')));

        // contributingSessionCount is the only session-derived value the
        // badge exposes, and the original session ids must not appear.
        expect(summary['contributingSessionCount'], isA<int>());
        expect(
          summary.values.whereType<String>().any(
            (s) => s.contains('p1') || s.contains('p2'),
          ),
          isFalse,
        );
      },
    );

    test('A8: badge summary is explainable and lists each measured primitive '
        'that founded the milestone', () {
      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[
          session(id: 'one', tempoBpm: 100, metricValue: 0.95, observedAt: now),
          session(
            id: 'two',
            tempoBpm: 110,
            metricValue: 0.97,
            observedAt: now.add(const Duration(minutes: 10)),
          ),
        ],
        now: now,
      );
      final summary = progress.badge!.toSummary();

      // Every key in the contract must be present and finite/well-typed.
      expect(summary['milestoneId'], milestone.id);
      expect(summary['skill'], MasterySkill.rhythmAccuracy.code);
      expect(summary['metric'], MasteryMetric.accuracy.code);
      expect(summary['difficulty'], MasteryDifficulty.intermediate.code);
      expect(summary['tempoBpmMin'], 80);
      expect(summary['tempoBpmMax'], 120);
      expect(summary['contributingSessionCount'], 2);
      expect(summary['achievedAt'], isA<String>());
    });

    test('threshold alatt: 1 qualifying session → does not complete', () {
      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[session(id: 'only-one')],
        now: now,
      );
      expect(progress.isAchieved, isFalse);
      expect(progress.evidenceSessionCount, 1);
    });

    test('threshold rajta: exactly 2 qualifying sessions → '
        'the inclusive minEvidenceSessions boundary completes', () {
      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[
          session(id: 'one', observedAt: now),
          session(id: 'two', observedAt: now.add(const Duration(minutes: 5))),
        ],
        now: now,
      );

      expect(progress.evidenceSessionCount, 2);
      expect(progress.isAchieved, isTrue);
      expect(progress.badge, isNotNull);
      expect(progress.badge!.contributingSessionCount, 2);
      // achievedAt pin: the observed-at of the 2nd session (completion
      // moment), not `now`.
      expect(progress.achievedAt, now.add(const Duration(minutes: 5)));
    });

    test('threshold fölött: 3 sessions → completes with 3 contributing', () {
      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[
          session(id: 'one', observedAt: now),
          session(id: 'two', observedAt: now.add(const Duration(minutes: 5))),
          session(
            id: 'three',
            observedAt: now.add(const Duration(minutes: 10)),
          ),
        ],
        now: now,
      );
      expect(progress.isAchieved, isTrue);
      expect(progress.badge!.contributingSessionCount, 3);
      expect(progress.evidenceSessionCount, 3);
      expect(progress.progressValue(milestone), 1.0);
    });

    test(
      'best-metric rule: highest sample value is the achievement signal',
      () {
        final progress = evaluator.evaluate(
          milestone: milestone,
          previous: null,
          evidence: <MasteryEvidence>[
            // One strong, one weak — distinct sessions, BOTH pass the metric
            // threshold, so completion is on the max value.
            session(id: 'low', metricValue: 0.92, observedAt: now),
            session(
              id: 'high',
              metricValue: 0.98,
              observedAt: now.add(const Duration(minutes: 1)),
            ),
          ],
          now: now,
        );

        expect(progress.isAchieved, isTrue);
        expect(progress.badge, isNotNull);
      },
    );

    test('metric below the minimum threshold blocks completion', () {
      final below = MasteryMilestone(
        id: 'tight_threshold',
        catalogVersion: 1,
        skill: MasterySkill.rhythmAccuracy,
        metric: MasteryMetric.accuracy,
        minimumThreshold: 0.99,
        difficulty: MasteryDifficulty.intermediate,
        tempoRange: MasteryTempoRange(minBpm: 80, maxBpm: 120),
        minEvidenceSessions: 2,
        titleKey: 'tightTitle',
        descriptionKey: 'tightDescription',
      );

      final progress = evaluator.evaluate(
        milestone: below,
        previous: null,
        evidence: <MasteryEvidence>[
          session(id: 'one', metricValue: 0.95),
          session(
            id: 'two',
            metricValue: 0.96,
            observedAt: now.add(const Duration(minutes: 1)),
          ),
        ],
        now: now,
      );

      expect(progress.evidenceSessionCount, 2);
      expect(progress.isAchieved, isFalse);
    });

    test('vision origin without confidence cannot contribute', () {
      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[
          MasteryEvidence(
            sessionId: 'vision-1',
            origin: MasteryEvidenceOrigin.vision,
            difficulty: MasteryDifficulty.intermediate,
            tempoBpm: 100,
            metricValue: 0.97,
            observedAt: now,
            // confidence intentionally absent — must be rejected
          ),
          MasteryEvidence(
            sessionId: 'vision-2',
            origin: MasteryEvidenceOrigin.vision,
            difficulty: MasteryDifficulty.intermediate,
            tempoBpm: 100,
            metricValue: 0.97,
            observedAt: now.add(const Duration(minutes: 1)),
          ),
        ],
        now: now,
      );

      expect(progress.evidenceSessionCount, 0);
      expect(progress.isAchieved, isFalse);
    });

    test('device origin is accepted without a confidence value', () {
      final progress = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[
          MasteryEvidence(
            sessionId: 'device-1',
            origin: MasteryEvidenceOrigin.device,
            difficulty: MasteryDifficulty.intermediate,
            tempoBpm: 100,
            metricValue: 0.95,
            observedAt: now,
          ),
          MasteryEvidence(
            sessionId: 'device-2',
            origin: MasteryEvidenceOrigin.device,
            difficulty: MasteryDifficulty.intermediate,
            tempoBpm: 110,
            metricValue: 0.96,
            observedAt: now.add(const Duration(minutes: 5)),
          ),
        ],
        now: now,
      );

      expect(progress.evidenceSessionCount, 2);
      expect(progress.isAchieved, isTrue);
    });

    test('previous monotonic: stronger batch raises evidenceSessionCount', () {
      final weak = evaluator.evaluate(
        milestone: milestone,
        previous: null,
        evidence: <MasteryEvidence>[session(id: 'only-one')],
        now: now,
      );
      expect(weak.evidenceSessionCount, 1);

      final stronger = evaluator.evaluate(
        milestone: milestone,
        previous: weak,
        evidence: <MasteryEvidence>[
          session(id: 'only-one'),
          session(
            id: 'second',
            observedAt: now.add(const Duration(minutes: 1)),
          ),
        ],
        now: now,
      );

      expect(stronger.evidenceSessionCount, 2);
      expect(stronger.isAchieved, isTrue);
    });

    test('invalid inputs are surfaced as ArgumentError', () {
      // Milestone with minEvidenceSessions < 2 — the spec floor.
      expect(
        () => MasteryMilestone(
          id: 'bad',
          catalogVersion: 1,
          skill: MasterySkill.rhythmAccuracy,
          metric: MasteryMetric.accuracy,
          minimumThreshold: 0.9,
          difficulty: MasteryDifficulty.intermediate,
          tempoRange: MasteryTempoRange(minBpm: 80, maxBpm: 120),
          minEvidenceSessions: 1,
          titleKey: 't',
          descriptionKey: 'd',
        ),
        throwsArgumentError,
      );

      // Tempo range with min > max.
      expect(
        () => MasteryTempoRange(minBpm: 120, maxBpm: 80),
        throwsArgumentError,
      );

      // Evidence with confidence outside [0, 1].
      expect(
        () => MasteryEvidence(
          sessionId: 'x',
          origin: MasteryEvidenceOrigin.vision,
          difficulty: MasteryDifficulty.intermediate,
          tempoBpm: 100,
          metricValue: 0.9,
          observedAt: now,
          confidence: 1.5,
        ),
        throwsArgumentError,
      );
    });

    test('evaluator rejects non-UTC `now` (failure is fail-closed)', () {
      expect(
        () => evaluator.evaluate(
          milestone: milestone,
          previous: null,
          evidence: <MasteryEvidence>[],
          now: DateTime(2026, 8, 21, 12),
        ),
        throwsArgumentError,
      );
    });
  });
}
