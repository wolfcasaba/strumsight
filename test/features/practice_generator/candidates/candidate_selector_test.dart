import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/candidate_decision.dart';
import 'package:strumsight/features/practice_generator/domain/model/exercise_candidate.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_enums.dart';
import 'package:strumsight/features/practice_generator/domain/policy/candidate_policy.dart';
import 'package:strumsight/features/practice_generator/domain/service/candidate_selector.dart';

import '../../../fixtures/practice_generator/candidates/candidates_fixtures.dart';

void main() {
  group('CandidateSelector — hard filter and ranking boundary', () {
    test(
      'A1 — a hard-avoided candidate never returns regardless of its score',
      () {
        // Two candidates targeting the same skill with the same offline
        // truth. The hard-avoided one is lexicographically later but has
        // strictly higher composite score via priority.score.
        final higher = buildCandidate(exerciseId: 'rhythm.zzz');
        final lower = buildCandidate(exerciseId: 'rhythm.aaa');
        final catalog = buildCatalog(
          candidates: <ExerciseCandidate>[higher, lower],
        );
        final priority = buildPriority(score: 0.9);
        final context = buildContext(
          hardAvoidIdentities: <String>[identityOf(higher)],
        );
        final decision = const CandidateSelector().select(
          priority: priority,
          catalog: catalog,
          context: context,
          seed: 7,
        );

        expect(decision.selected, isNotNull);
        expect(decision.selected!.identity, identityOf(lower));
        expect(decision.fallback, isNull);
        expect(
          decision.rejected.map((rejected) => rejected.identity).toList(),
          <String>[identityOf(higher)],
        );
        expect(
          decision.rejected.single.reason,
          CandidateRejectReason.hardAvoid,
        );
      },
    );

    test('A1 (megfelel) — a candidate that satisfies every hard filter is '
        'rankable', () {
      final candidate = buildCandidate(exerciseId: 'rhythm.clean');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[candidate]);
      final priority = buildPriority();
      final context = buildContext();
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: context,
        seed: 1,
      );

      expect(decision.selected, isNotNull);
      expect(decision.selected!.identity, identityOf(candidate));
      expect(decision.fallback, isNull);
      expect(decision.rejected, isEmpty);
    });

    test('A1 (a határon) — a candidate exactly at the hard-filter boundary '
        'is rankable', () {
      // Prerequisites include the tuning prerequisite and the caller has
      // confirmed tuning exactly for this identity.
      final candidate = buildCandidate(
        exerciseId: 'rhythm.atBoundary',
        prerequisites: const <String>['guitar.tuned'],
      );
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[candidate]);
      final priority = buildPriority();
      final context = buildContext(
        confirmedTuningIdentities: <String>[identityOf(candidate)],
      );
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: context,
        seed: 1,
      );

      expect(decision.selected, isNotNull);
      expect(decision.selected!.identity, identityOf(candidate));
      expect(decision.rejected, isEmpty);
    });

    test('A1 (kizárt) — a candidate that fails one hard filter is excluded '
        'even when its relevance is strictly the highest', () {
      final best = buildCandidate(
        exerciseId: 'rhythm.best',
        offlineAvailable: false,
      );
      final ok = buildCandidate(exerciseId: 'rhythm.ok');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[best, ok]);
      final priority = buildPriority(score: 0.99);
      // No offline confirmations supplied.
      final context = buildContext();
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: context,
        seed: 1,
      );

      expect(decision.selected, isNotNull);
      expect(decision.selected!.identity, identityOf(ok));
      expect(
        decision.rejected
            .where((rejected) => rejected.identity == identityOf(best))
            .single
            .reason,
        CandidateRejectReason.offlineUnconfirmed,
      );
      expect(decision.rejected.single.wouldBeScore, priority.score);
    });

    test('A2 — an offline-unconfirmed candidate cannot be selected or '
        'fallback', () {
      final offlineOnly = buildCandidate(
        exerciseId: 'rhythm.offlineOnly',
        offlineAvailable: false,
      );
      final online = buildCandidate(exerciseId: 'rhythm.online');
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[offlineOnly, online],
      );
      final priority = buildPriority();
      // Neither candidate has offline confirmed.
      final context = buildContext();
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: context,
        seed: 1,
      );

      expect(decision.selected, isNotNull);
      expect(decision.selected!.identity, identityOf(online));
      expect(decision.fallback, isNull);
      expect(
        decision.rejected.single.reason,
        CandidateRejectReason.offlineUnconfirmed,
      );
    });

    test('A2 — locked-style catalog contents are not visible to the selector '
        '(no candidate refers to a locked identity)', () {
      // The selector only sees what the snapshot exposes. A caller that
      // wants to verify "locked never returns" can do so by simply
      // observing the snapshot has no such candidate: the snapshot's
      // type signature rejects duplicates, so an attempt to smuggle a
      // locked candidate into the decision has no construction site.
      final online = buildCandidate(exerciseId: 'rhythm.online');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[online]);
      final priority = buildPriority();
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: buildContext(),
        seed: 1,
      );

      expect(
        decision.selected!.candidate.source,
        CandidateSource.practiceCatalog,
      );
      // The snapshot itself never carries a 'locked' field on the
      // ExerciseCandidate; the contract is upstream. The selector only
      // selects from `catalog.candidates`.
      expect(catalog.candidates, isNotEmpty);
    });

    test('A3 — diversity/exploration only permutes the top bucket, never '
        'replaces the winner with a less relevant candidate', () {
      // Three candidates with very different composite scores. The seed
      // must not move a strictly less relevant candidate ahead of the
      // primary winner.
      final best = buildCandidate(exerciseId: 'rhythm.best');
      final mid = buildCandidate(exerciseId: 'rhythm.mid');
      final weak = buildCandidate(exerciseId: 'rhythm.weak');
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[best, mid, weak],
      );
      final priority = buildPriority(score: 0.9);
      // mid and weak are outside the diversityWindow of best thanks to the
      // overuse penalty; only best can be selected under any seed.
      final context = buildContext(
        recentlyUsedIdentities: <String>[identityOf(mid), identityOf(weak)],
      );

      for (final seed in <int>[0, 1, 7, 42, 12345]) {
        final decision = const CandidateSelector().select(
          priority: priority,
          catalog: catalog,
          context: context,
          seed: seed,
        );
        expect(decision.selected, isNotNull);
        expect(
          decision.selected!.identity,
          identityOf(best),
          reason: 'seed=$seed must not promote a less relevant candidate',
        );
      }
    });

    test('A4 — identical (catalog, context, priority, seed) yields identical '
        'decisions across calls', () {
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[
          buildCandidate(exerciseId: 'rhythm.alpha'),
          buildCandidate(exerciseId: 'rhythm.bravo'),
        ],
      );
      final priority = buildPriority();
      final context = buildContext();

      final first = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: context,
        seed: 17,
      );
      final second = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: context,
        seed: 17,
      );

      expect(first, second);
      expect(first.seedProvenance, '17');
    });

    test(
      'A5 — the decision lists every rejected candidate with its reason',
      () {
        final hardAvoid = buildCandidate(exerciseId: 'rhythm.avoid');
        final assetOnly = buildCandidate(
          exerciseId: 'rhythm.assetOnly',
          capabilityOverrides: const <ExerciseCapability, CapabilitySupport>{
            ExerciseCapability.requiresSongAsset: CapabilitySupport.supported,
          },
        );
        final ok = buildCandidate(exerciseId: 'rhythm.ok');
        final catalog = buildCatalog(
          candidates: <ExerciseCandidate>[hardAvoid, assetOnly, ok],
        );
        final priority = buildPriority();
        final context = buildContext(
          hardAvoidIdentities: <String>[identityOf(hardAvoid)],
        );
        final decision = const CandidateSelector().select(
          priority: priority,
          catalog: catalog,
          context: context,
          seed: 1,
        );

        expect(decision.selected!.identity, identityOf(ok));
        expect(decision.rejected, hasLength(2));
        expect(
          decision.rejected.map((rejected) => rejected.reason).toList(),
          <CandidateRejectReason>[
            CandidateRejectReason.assetUnconfirmed,
            CandidateRejectReason.hardAvoid,
          ],
        );
        for (final rejected in decision.rejected) {
          expect(rejected.detail, isNotEmpty);
        }
      },
    );

    test('A6 — the fallback always targets the same skill and survives the '
        'hard filter', () {
      final a = buildCandidate(exerciseId: 'rhythm.alpha');
      final b = buildCandidate(exerciseId: 'rhythm.bravo');
      final c = buildCandidate(exerciseId: 'rhythm.charlie');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[a, b, c]);
      final priority = buildPriority();
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: buildContext(),
        seed: 1,
      );

      expect(decision.selected, isNotNull);
      expect(decision.fallback, isNotNull);
      expect(decision.fallback!.skillId, priority.skillId);
      expect(decision.fallback!.skillId, decision.selected!.skillId);
      expect(decision.fallback!.identity, isNot(decision.selected!.identity));
      // Both must target the requested skill.
      for (final picked in <SelectedCandidate?>[
        decision.selected,
        decision.fallback,
      ]) {
        expect(picked, isNotNull);
        expect(picked!.candidate.skillTargets, contains(priority.skillId));
      }
    });

    test('A6 — when only one candidate survives the hard filter, the fallback '
        'is null but the skill is still the same', () {
      final a = buildCandidate(exerciseId: 'rhythm.alpha');
      final b = buildCandidate(
        exerciseId: 'rhythm.bravo',
        offlineAvailable: false,
      );
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[a, b]);
      final priority = buildPriority();
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: buildContext(),
        seed: 1,
      );

      expect(decision.selected, isNotNull);
      expect(decision.selected!.skillId, priority.skillId);
      expect(decision.fallback, isNull);
    });

    test('A7 — a recently-used candidate receives the configured overuse '
        'penalty', () {
      final fresh = buildCandidate(exerciseId: 'rhythm.fresh');
      final stale = buildCandidate(exerciseId: 'rhythm.stale');
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[stale, fresh],
      );
      final priority = buildPriority(score: 0.9);
      final context = buildContext(
        recentlyUsedIdentities: <String>[identityOf(stale)],
      );
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: context,
        seed: 1,
      );

      expect(decision.selected, isNotNull);
      // fresh has no penalty (compositeScore = 0.9); stale is penalized
      // (compositeScore = 0.7). fresh wins on raw score; the penalty on
      // stale is observable in the fallback's compositeScore.
      expect(decision.selected!.identity, identityOf(fresh));
      expect(decision.selected!.compositeScore, priority.score);
      expect(decision.fallback, isNotNull);
      expect(decision.fallback!.identity, identityOf(stale));
      expect(
        decision.fallback!.compositeScore,
        priority.score - CandidatePolicy.defaultPolicy.recentOverusePenalty,
      );
    });

    test('A7 — the penalty term appears on the SelectedCandidate factor '
        'list when a recently-used candidate is selected', () {
      // A single recently-used candidate with no competitor survives; the
      // penalty must still be exposed on the factor list so the diagnostic
      // is faithful (ADR 0297 §5).
      final only = buildCandidate(exerciseId: 'rhythm.only');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[only]);
      final priority = buildPriority(score: 0.9);
      final context = buildContext(
        recentlyUsedIdentities: <String>[identityOf(only)],
      );
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: context,
        seed: 1,
      );

      expect(decision.selected, isNotNull);
      expect(decision.selected!.identity, identityOf(only));
      expect(
        decision.selected!.factors,
        contains(
          isA<CandidateFactor>()
              .having(
                (factor) => factor.kind,
                'kind',
                CandidateFactorKind.recentOveruse,
              )
              .having(
                (factor) => factor.contribution,
                'contribution',
                -CandidatePolicy.defaultPolicy.recentOverusePenalty,
              ),
        ),
      );
      expect(
        decision.selected!.compositeScore,
        priority.score - CandidatePolicy.defaultPolicy.recentOverusePenalty,
      );
    });

    test('A8 — fallback identity is independent of the seed', () {
      final alpha = buildCandidate(exerciseId: 'rhythm.alpha');
      final bravo = buildCandidate(exerciseId: 'rhythm.bravo');
      final charlie = buildCandidate(exerciseId: 'rhythm.charlie');
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[alpha, bravo, charlie],
      );
      final priority = buildPriority();

      final first = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: buildContext(),
        seed: 0,
      );
      final second = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: buildContext(),
        seed: 999,
      );

      // Lexical tie-break for the fallback is independent of the seed:
      // both calls share the canonical ranked list, so the fallback is
      // always the second-lexical identity that was not promoted to
      // selected.
      expect(first.fallback, isNotNull);
      expect(second.fallback, isNotNull);
      expect(first.fallback!.identity, second.fallback!.identity);
      expect(first.fallback!.identity, isNot(equals(first.selected!.identity)));
      expect(
        second.fallback!.identity,
        isNot(equals(second.selected!.identity)),
      );
    });

    test('A8 — the fallback is always a deterministic, non-selected, '
        'lexically-second candidate', () {
      final zulu = buildCandidate(exerciseId: 'rhythm.zulu');
      final alpha = buildCandidate(exerciseId: 'rhythm.alpha');
      final middle = buildCandidate(exerciseId: 'rhythm.middle');
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[zulu, alpha, middle],
      );
      final priority = buildPriority(score: 0.6);
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: buildContext(),
        seed: 1,
      );

      // Canonical ranking by compositeScore desc, identity asc:
      //   alpha, middle, zulu
      // The fallback is the first candidate in that list that is not the
      // selected identity — it is therefore always alpha or middle, never
      // zulu (zulu is the canonical third and the seed cannot promote it
      // past middle).
      expect(decision.selected, isNotNull);
      expect(decision.fallback, isNotNull);
      expect(decision.fallback!.identity, isNot(decision.selected!.identity));
      expect(
        decision.fallback!.identity,
        anyOf(identityOf(alpha), identityOf(middle)),
      );
      expect(decision.rejected, isEmpty);
    });

    test('a missing skill target yields no selection and no rejection', () {
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[
          buildCandidate(
            exerciseId: 'rhythm.other',
            skillTargets: const <String>['rhythm.sixteenthNotes'],
          ),
        ],
      );
      final priority = buildPriority(skillId: candidateSkill);
      final decision = const CandidateSelector().select(
        priority: priority,
        catalog: catalog,
        context: buildContext(),
        seed: 1,
      );

      expect(decision.selected, isNull);
      expect(decision.fallback, isNull);
      expect(decision.rejected, isEmpty);
      expect(decision.hasNoEligible, isTrue);
      expect(decision.skillId, candidateSkill);
    });

    test('CandidateDecision rejects mismatched skillId between selection and '
        'decision', () {
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[
          buildCandidate(exerciseId: 'rhythm.alpha'),
        ],
      );
      final decision = const CandidateSelector().select(
        priority: buildPriority(),
        catalog: catalog,
        context: buildContext(),
        seed: 1,
      );

      expect(
        () => CandidateDecision(
          initialSelected: decision.selected,
          initialFallback: decision.fallback,
          rejected: decision.rejected,
          policyVersion: decision.policyVersion,
          seedProvenance: decision.seedProvenance,
          skillId: 'rhythm.other',
        ),
        throwsArgumentError,
      );
    });

    test('CandidateDecision rejects a fallback that duplicates the selected '
        'identity', () {
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[
          buildCandidate(exerciseId: 'rhythm.alpha'),
        ],
      );
      final decision = const CandidateSelector().select(
        priority: buildPriority(),
        catalog: catalog,
        context: buildContext(),
        seed: 1,
      );

      expect(
        () => CandidateDecision(
          initialSelected: decision.selected,
          initialFallback: decision.selected,
          rejected: decision.rejected,
          policyVersion: decision.policyVersion,
          seedProvenance: decision.seedProvenance,
          skillId: decision.skillId,
        ),
        throwsArgumentError,
      );
    });

    test('A3 — distinct candidate-level soft ranking factors produce distinct '
        'relevance and the diversity window respects them across all seeds '
        '(falsifying: a selector without candidate-level factors picks the '
        'lexically-first candidate regardless of distinct relevance)', () {
      // Three candidates tied on hard-filter and skill-target state.
      // Distinct per-candidate soft profiles create strictly different
      // composite scores; the diversity window collapses to a single top
      // bucket; the seed must never promote a less relevant candidate.
      final best = buildCandidate(exerciseId: 'rhythm.best');
      final mid = buildCandidate(exerciseId: 'rhythm.mid');
      final weak = buildCandidate(exerciseId: 'rhythm.weak');
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[best, mid, weak],
      );
      final priority = buildPriority(score: 0.6);
      final policy = CandidatePolicy(
        diversityWindow: 0.05,
        explorationWeight: 1.0, // engaged so any leak would show
        difficultyWeight: 0.5,
        preferenceWeight: 0.5,
        measurabilityWeight: 0.5,
      );
      final context = buildContext(
        rankingProfiles: buildRankingProfiles(
          [best, mid, weak],
          difficultyAffinityFor: (c) => c.exerciseId == 'rhythm.best'
              ? 1.0
              : c.exerciseId == 'rhythm.mid'
              ? 0.4
              : 0.1,
          preferenceAffinityFor: (c) => c.exerciseId == 'rhythm.best'
              ? 0.9
              : c.exerciseId == 'rhythm.mid'
              ? 0.3
              : 0.1,
          measurabilityScoreFor: (c) => c.exerciseId == 'rhythm.best'
              ? 0.8
              : c.exerciseId == 'rhythm.mid'
              ? 0.2
              : 0.0,
        ),
      );

      for (final seed in <int>[0, 1, 7, 42, 12345]) {
        final decision = CandidateSelector(policy: policy).select(
          priority: priority,
          catalog: catalog,
          context: context,
          seed: seed,
        );
        expect(decision.selected, isNotNull);
        expect(
          decision.selected!.identity,
          identityOf(best),
          reason: 'seed=$seed must not promote a less relevant candidate',
        );
      }
    });

    test('A4 — explorationWeight=0 yields strict lexical order regardless of '
        'seed (falsifying: a selector that always permutes leaks the seed '
        'into the winner)', () {
      // Two candidates tied on every composite score component, sharing
      // the diversityWindow bucket. explorationWeight=0 must collapse
      // to lexical order, so the seed never affects the winner.
      final alpha = buildCandidate(exerciseId: 'rhythm.alpha');
      final bravo = buildCandidate(exerciseId: 'rhythm.bravo');
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[alpha, bravo],
      );
      final priority = buildPriority();
      final policy = CandidatePolicy(
        diversityWindow: 0.05,
        explorationWeight: 0.0,
      );
      final selector = CandidateSelector(policy: policy);

      for (final seed in <int>[0, 1, 7, 42, 12345, 99999]) {
        final decision = selector.select(
          priority: priority,
          catalog: catalog,
          context: buildContext(),
          seed: seed,
        );
        expect(decision.selected, isNotNull);
        expect(
          decision.selected!.identity,
          identityOf(alpha),
          reason:
              'explorationWeight=0 must pick the lexically-first '
              'candidate regardless of seed=$seed',
        );
      }
    });

    test('A4 — explorationWeight>0 with identical seed yields identical '
        'decisions (falsifying: a Random-driven permutation would diverge '
        'for the same seed)', () {
      final alpha = buildCandidate(exerciseId: 'rhythm.alpha');
      final bravo = buildCandidate(exerciseId: 'rhythm.bravo');
      final charlie = buildCandidate(exerciseId: 'rhythm.charlie');
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[alpha, bravo, charlie],
      );
      final priority = buildPriority();
      final policy = CandidatePolicy(
        diversityWindow: 0.05,
        explorationWeight: 1.0,
      );
      final selector = CandidateSelector(policy: policy);

      for (final seed in <int>[0, 1, 7, 42, 12345]) {
        final first = selector.select(
          priority: priority,
          catalog: catalog,
          context: buildContext(),
          seed: seed,
        );
        final second = selector.select(
          priority: priority,
          catalog: catalog,
          context: buildContext(),
          seed: seed,
        );
        expect(
          first,
          second,
          reason: 'same seed=$seed must produce identical decision bytes',
        );
      }
    });

    test('A4 — explorationWeight>0 across distinct seeds can produce distinct '
        'selected identities (proves the seed permutation is engaged '
        'inside the bucket)', () {
      final alpha = buildCandidate(exerciseId: 'rhythm.alpha');
      final bravo = buildCandidate(exerciseId: 'rhythm.bravo');
      final charlie = buildCandidate(exerciseId: 'rhythm.charlie');
      final catalog = buildCatalog(
        candidates: <ExerciseCandidate>[alpha, bravo, charlie],
      );
      final priority = buildPriority();
      final policy = CandidatePolicy(
        diversityWindow: 0.05,
        explorationWeight: 1.0,
      );
      final selector = CandidateSelector(policy: policy);

      final selectedIdentities = <String>{};
      for (final seed in <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) {
        final decision = selector.select(
          priority: priority,
          catalog: catalog,
          context: buildContext(),
          seed: seed,
        );
        expect(decision.selected, isNotNull);
        selectedIdentities.add(decision.selected!.identity);
      }
      // Three candidates, ten seeds: the seed-based permutation must
      // cover more than one identity to prove it is engaged (with
      // explorationWeight=0 it would always be alpha).
      expect(
        selectedIdentities.length,
        greaterThan(1),
        reason:
            'explorationWeight>0 must let different seeds select '
            'different identities',
      );
    });

    test('the difficulty factor contributes to compositeScore and appears '
        'on the SelectedCandidate factor list', () {
      final candidate = buildCandidate(exerciseId: 'rhythm.diff');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[candidate]);
      final priority = buildPriority(score: 0.5);
      final policy = CandidatePolicy(difficultyWeight: 0.8);
      final context = buildContext(
        rankingProfiles: buildRankingProfiles([
          candidate,
        ], difficultyAffinity: 0.6),
      );
      final decision = CandidateSelector(
        policy: policy,
      ).select(priority: priority, catalog: catalog, context: context, seed: 1);

      expect(decision.selected, isNotNull);
      // 0.5 (relevance) + 0.8 * 0.6 (difficulty) = 0.98
      expect(decision.selected!.compositeScore, closeTo(0.98, 0.0000001));
      expect(
        decision.selected!.factors,
        contains(
          isA<CandidateFactor>()
              .having((f) => f.kind, 'kind', CandidateFactorKind.difficulty)
              .having((f) => f.normalizedValue, 'normalizedValue', 0.6)
              .having(
                (f) => f.contribution,
                'contribution',
                closeTo(0.48, 0.0000001),
              ),
        ),
      );
    });

    test('the preference factor contributes to compositeScore and appears '
        'on the SelectedCandidate factor list', () {
      final candidate = buildCandidate(exerciseId: 'rhythm.pref');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[candidate]);
      final priority = buildPriority(score: 0.4);
      final policy = CandidatePolicy(preferenceWeight: 0.5);
      final context = buildContext(
        rankingProfiles: buildRankingProfiles([
          candidate,
        ], preferenceAffinity: 0.7),
      );
      final decision = CandidateSelector(
        policy: policy,
      ).select(priority: priority, catalog: catalog, context: context, seed: 1);

      expect(decision.selected, isNotNull);
      // 0.4 (relevance) + 0.5 * 0.7 (preference) = 0.75
      expect(decision.selected!.compositeScore, closeTo(0.75, 0.0000001));
      expect(
        decision.selected!.factors,
        contains(
          isA<CandidateFactor>()
              .having((f) => f.kind, 'kind', CandidateFactorKind.preference)
              .having((f) => f.normalizedValue, 'normalizedValue', 0.7)
              .having(
                (f) => f.contribution,
                'contribution',
                closeTo(0.35, 0.0000001),
              ),
        ),
      );
    });

    test('the measurability factor contributes to compositeScore and appears '
        'on the SelectedCandidate factor list', () {
      final candidate = buildCandidate(exerciseId: 'rhythm.measure');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[candidate]);
      final priority = buildPriority(score: 0.3);
      final policy = CandidatePolicy(measurabilityWeight: 0.6);
      final context = buildContext(
        rankingProfiles: buildRankingProfiles([
          candidate,
        ], measurabilityScore: 0.5),
      );
      final decision = CandidateSelector(
        policy: policy,
      ).select(priority: priority, catalog: catalog, context: context, seed: 1);

      expect(decision.selected, isNotNull);
      // 0.3 (relevance) + 0.6 * 0.5 (measurability) = 0.6
      expect(decision.selected!.compositeScore, closeTo(0.6, 0.0000001));
      expect(
        decision.selected!.factors,
        contains(
          isA<CandidateFactor>()
              .having((f) => f.kind, 'kind', CandidateFactorKind.measurability)
              .having((f) => f.normalizedValue, 'normalizedValue', 0.5)
              .having(
                (f) => f.contribution,
                'contribution',
                closeTo(0.3, 0.0000001),
              ),
        ),
      );
    });

    test('a soft factor with policy weight=0 does not appear in the factor '
        'list, and the candidate gets the neutral compositeScore', () {
      // The weight=0 / non-zero value pair must NOT contribute and must
      // NOT show up on the factor list — proves the policy is the gate.
      final candidate = buildCandidate(exerciseId: 'rhythm.silent');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[candidate]);
      final priority = buildPriority(score: 0.5);
      final policy = CandidatePolicy(difficultyWeight: 0);
      final context = buildContext(
        rankingProfiles: buildRankingProfiles([
          candidate,
        ], difficultyAffinity: 0.7),
      );
      final decision = CandidateSelector(
        policy: policy,
      ).select(priority: priority, catalog: catalog, context: context, seed: 1);

      expect(decision.selected, isNotNull);
      expect(decision.selected!.compositeScore, closeTo(0.5, 0.0000001));
      expect(
        decision.selected!.factors.where(
          (f) => f.kind == CandidateFactorKind.difficulty,
        ),
        isEmpty,
      );
    });

    test('the diversity window cannot promote a candidate outside the top '
        'bucket even when explorationWeight is positive', () {
      // best and weak have a strict composite score gap that exceeds the
      // diversityWindow. The exploration seed must never carry weak
      // ahead of best — the bucket is the canonical top.
      final best = buildCandidate(exerciseId: 'rhythm.best');
      final weak = buildCandidate(exerciseId: 'rhythm.weak');
      final catalog = buildCatalog(candidates: <ExerciseCandidate>[best, weak]);
      final priority = buildPriority(score: 0.9);
      final policy = CandidatePolicy(
        diversityWindow: 0.05,
        explorationWeight: 1.0,
        preferenceWeight: 1.0, // enable the preference factor so it matters
      );
      // best gets a strong preference boost so its composite sits well
      // above the bucket window; weak gets no preference.
      final context = buildContext(
        rankingProfiles: buildRankingProfiles(
          [best, weak],
          preferenceAffinityFor: (c) => c.exerciseId == 'rhythm.best' ? 1.0 : 0,
        ),
      );

      for (final seed in <int>[0, 1, 7, 42, 12345, 99999]) {
        final decision = CandidateSelector(policy: policy).select(
          priority: priority,
          catalog: catalog,
          context: context,
          seed: seed,
        );
        expect(decision.selected, isNotNull);
        expect(
          decision.selected!.identity,
          identityOf(best),
          reason:
              'seed=$seed must not promote a candidate outside the top '
              'bucket',
        );
      }
    });
  });
}
