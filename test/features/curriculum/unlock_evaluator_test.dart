// The unlock gate, which is where the curriculum's honesty rules become code.
//
// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §2.
// The rules these cells pin:
//
//   5. Unlocking requires CONFIDENCE, not luck: `emerging` or better opens a
//      rung; `stale` and `conflicted` never open one, and `unknown` never does.
//   7. What is not measured says so: a rung with nothing to measure is
//      available without evidence, and is reported as such rather than as
//      measured skill.
//
// One trap this file exists to catch: `SkillEstimateState` is declared
// `unknown, initial, emerging, stable, strong, stale, conflicted`, so `stale`
// and `conflicted` sit AFTER `strong` in index order. Any implementation that
// compares `.index` would read degraded evidence as the strongest kind. The
// ordering must be explicit.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

SkillEstimate _estimate(
  String skillId, {
  required SkillEstimateState state,
  double level = 0.8,
}) => SkillEstimate(
  skillId: skillId,
  level: level,
  uncertainty: 0.2,
  state: state,
  trend: SkillTrend.improving,
  trendDelta: 0.1,
  lastObservedAt: DateTime.utc(2026, 9, 11),
  evidenceIds: const ['e1'],
  evidenceSummary: const EvidenceSummary(
    validPerformanceCount: 4,
    stalePerformanceCount: 0,
    discomfortOnlyCount: 0,
  ),
);

/// A rung that needs one skill at `emerging` or better, level >= 0.6.
final _gated = UnlockRule.skillConfidence(
  prerequisiteSkillIds: {'chordChange.A-D'},
  minimumState: SkillEstimateState.emerging,
  minimumLevel: 0.6,
);

void main() {
  group('confidence ordering', () {
    test('emerging, stable and strong all satisfy an emerging gate', () {
      for (final state in const [
        SkillEstimateState.emerging,
        SkillEstimateState.stable,
        SkillEstimateState.strong,
      ]) {
        expect(
          _gated.isSatisfiedBy({
            'chordChange.A-D': _estimate('chordChange.A-D', state: state),
          }),
          isTrue,
          reason: '$state must open an emerging gate',
        );
      }
    });

    test('stale and conflicted NEVER open a gate, at any level', () {
      // The index trap: both of these out-rank `strong` in declaration order.
      for (final state in const [
        SkillEstimateState.stale,
        SkillEstimateState.conflicted,
      ]) {
        expect(
          _gated.isSatisfiedBy({
            'chordChange.A-D': _estimate(
              'chordChange.A-D',
              state: state,
              level: 1,
            ),
          }),
          isFalse,
          reason: '$state is degraded evidence, not strong evidence',
        );
      }
    });

    test('initial is not enough, and unknown is never enough', () {
      expect(
        _gated.isSatisfiedBy({
          'chordChange.A-D': _estimate(
            'chordChange.A-D',
            state: SkillEstimateState.initial,
            level: 1,
          ),
        }),
        isFalse,
        reason: 'a single observation is not an emerging skill',
      );
      expect(
        _gated.isSatisfiedBy({
          'chordChange.A-D': SkillEstimate.unknown(skillId: 'chordChange.A-D'),
        }),
        isFalse,
        reason: 'no evidence must never unlock',
      );
    });

    test('a missing estimate is treated as unknown, not as satisfied', () {
      // The absent-entry trap: an empty map must not vacuously pass.
      expect(_gated.isSatisfiedBy(const {}), isFalse);
    });

    test('the level threshold is honoured independently of the state', () {
      expect(
        _gated.isSatisfiedBy({
          'chordChange.A-D': _estimate(
            'chordChange.A-D',
            state: SkillEstimateState.strong,
            level: 0.59,
          ),
        }),
        isFalse,
        reason: 'strong but below the required level must not open the gate',
      );
      expect(
        _gated.isSatisfiedBy({
          'chordChange.A-D': _estimate(
            'chordChange.A-D',
            state: SkillEstimateState.strong,
            level: 0.6,
          ),
        }),
        isTrue,
        reason: 'the threshold is inclusive',
      );
    });

    test('every prerequisite must pass, not just one', () {
      final two = UnlockRule.skillConfidence(
        prerequisiteSkillIds: const {'a', 'b'},
        minimumState: SkillEstimateState.emerging,
        minimumLevel: 0.6,
      );
      expect(
        two.isSatisfiedBy({
          'a': _estimate('a', state: SkillEstimateState.strong),
          'b': _estimate('b', state: SkillEstimateState.initial),
        }),
        isFalse,
      );
      expect(
        two.isSatisfiedBy({
          'a': _estimate('a', state: SkillEstimateState.strong),
          'b': _estimate('b', state: SkillEstimateState.emerging),
        }),
        isTrue,
      );
    });
  });

  group('the always gate — rungs with nothing to measure', () {
    test('opens with no evidence at all', () {
      expect(UnlockRule.always.isSatisfiedBy(const {}), isTrue);
    });

    test('declares that it is not measured', () {
      // Rule 7: an unmeasured rung must never masquerade as measured skill, so
      // the rule itself has to be able to say which kind it is.
      expect(UnlockRule.always.isMeasured, isFalse);
      expect(_gated.isMeasured, isTrue);
    });
  });

  group('construction refuses a vacuous gate', () {
    test('a confidence gate with no prerequisite is rejected', () {
      // Otherwise a rung could look measured while gating on nothing — the
      // same failure mode `SuccessCriteria` guards against on its own side.
      expect(
        () => UnlockRule.skillConfidence(
          prerequisiteSkillIds: const {},
          minimumState: SkillEstimateState.emerging,
          minimumLevel: 0.6,
        ),
        throwsArgumentError,
      );
    });

    test('a confidence gate on unknown or degraded evidence is rejected', () {
      // A gate whose own minimum is `unknown`/`stale`/`conflicted` could never
      // mean anything; refusing it at construction stops the nonsense earlier
      // than a failing evaluation would.
      for (final state in const [
        SkillEstimateState.unknown,
        SkillEstimateState.stale,
        SkillEstimateState.conflicted,
      ]) {
        expect(
          () => UnlockRule.skillConfidence(
            prerequisiteSkillIds: const {'a'},
            minimumState: state,
            minimumLevel: 0.6,
          ),
          throwsArgumentError,
          reason: '$state is not a usable minimum',
        );
      }
    });

    test('a level outside 0..1 is rejected', () {
      for (final level in const [-0.1, 1.1]) {
        expect(
          () => UnlockRule.skillConfidence(
            prerequisiteSkillIds: const {'a'},
            minimumState: SkillEstimateState.emerging,
            minimumLevel: level,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('persistence codes', () {
    test('gates round-trip through a stable code, never through .name', () {
      for (final gate in UnlockGate.values) {
        expect(UnlockGate.fromCode(gate.code), gate);
      }
    });

    test('an unknown or empty code is rejected, never silently defaulted', () {
      expect(() => UnlockGate.fromCode('nope'), throwsArgumentError);
      expect(() => UnlockGate.fromCode(''), throwsArgumentError);
      expect(() => UnlockGate.fromCode(null), throwsArgumentError);
    });
  });
}
