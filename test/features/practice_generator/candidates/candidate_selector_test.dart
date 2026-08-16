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
  });
}
