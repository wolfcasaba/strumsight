// E14-R36 (ADR 0546) — the "10 useful minutes" chain: the composition rule,
// the step machine, the interruption rule and the measured play-evidence
// promotion. Pure domain: no widget, no provider container.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/today/domain/ten_minute_flow.dart';

TenMinuteFlowState _flow({
  TenMinuteStep step = TenMinuteStep.tune,
  DateTime? startedAt,
  int baselineActiveSeconds = 0,
}) => TenMinuteFlowState(
  plan: TenMinutePlan.standard,
  step: step,
  startedAt: startedAt ?? DateTime(2026, 8, 25, 18),
  baselineActiveSeconds: baselineActiveSeconds,
);

void main() {
  group('the composition rule (§ "10 perces LÁNC")', () {
    test('the shipped 10 minutes split 2 / 7 / 1', () {
      final plan = TenMinutePlan.standard;

      expect(plan.total, const Duration(minutes: 10));
      expect(plan.tune, const Duration(minutes: 2));
      expect(plan.play, const Duration(minutes: 7));
      expect(plan.review, const Duration(minutes: 1));
    });

    test(
      'the sum invariant holds for EVERY accepted total, not just for 10 — '
      'so a future total cannot silently lose or invent minutes',
      () {
        for (var minutes = 4; minutes <= 60; minutes++) {
          final total = Duration(minutes: minutes);
          expect(TenMinutePlan.fits(total), isTrue, reason: '$total');
          expect(TenMinutePlan.of(total).allocated, total, reason: '$total');
        }
      },
    );

    test('the play budget absorbs the whole remainder', () {
      expect(
        TenMinutePlan.of(const Duration(minutes: 20)).play,
        const Duration(minutes: 17),
      );
    });

    test(
      'a total that cannot fund one minute of playing is REJECTED, not '
      'squeezed into a session that is 3.5 minutes of overhead',
      () {
        const tooShort = Duration(minutes: 3, seconds: 59);

        expect(TenMinutePlan.fits(tooShort), isFalse);
        expect(() => TenMinutePlan.of(tooShort), throwsArgumentError);
      },
    );

    test('exactly at the 2 + 1 + 1 boundary is accepted', () {
      const boundary = Duration(minutes: 4);

      expect(TenMinutePlan.fits(boundary), isTrue);
      expect(TenMinutePlan.of(boundary).play, TenMinutePlan.minimumPlayBudget);
    });

    test('every step has a budget and the three cover the total', () {
      final plan = TenMinutePlan.standard;
      var sum = Duration.zero;
      for (final step in TenMinutePlan.steps) {
        sum += plan.budgetOf(step);
      }

      expect(TenMinutePlan.steps, hasLength(3));
      expect(sum, plan.total);
    });
  });

  group('the step machine', () {
    test('the chain is tune → play → review, then it ends', () {
      final tune = _flow();
      final play = tune.advanced();
      final review = play!.advanced();

      expect(tune.step, TenMinuteStep.tune);
      expect(play.step, TenMinuteStep.play);
      expect(review!.step, TenMinuteStep.review);
      expect(review.advanced(), isNull, reason: 'the recap is the last link');
      expect(review.isLastStep, isTrue);
    });

    test('the step counter is 1-based and reports the chain length', () {
      expect(_flow().stepNumber, 1);
      expect(_flow(step: TenMinuteStep.play).stepNumber, 2);
      expect(_flow(step: TenMinuteStep.review).stepNumber, 3);
      expect(_flow().stepCount, 3);
    });

    test('advancing keeps the baseline and the start time', () {
      final tune = _flow(baselineActiveSeconds: 420);
      final play = tune.advanced()!;

      expect(play.baselineActiveSeconds, 420);
      expect(play.startedAt, tune.startedAt);
    });
  });

  group('interruption (folytatás / megszakítás)', () {
    final startedAt = DateTime(2026, 8, 25, 18);

    test('resumable inside the window, including exactly at the bound', () {
      final flow = _flow(startedAt: startedAt);

      expect(flow.isResumableAt(startedAt), isTrue);
      expect(
        flow.isResumableAt(startedAt.add(const Duration(minutes: 45))),
        isTrue,
      );
      expect(
        flow.isResumableAt(startedAt.add(TenMinuteFlowState.resumeWindow)),
        isTrue,
        reason: 'the resume window bound is inclusive',
      );
    });

    test('one second past the window it is no longer resumable', () {
      final flow = _flow(startedAt: startedAt);

      expect(
        flow.isResumableAt(
          startedAt.add(
            TenMinuteFlowState.resumeWindow + const Duration(seconds: 1),
          ),
        ),
        isFalse,
      );
    });

    test('a backwards clock is not evidence of a live session', () {
      final flow = _flow(startedAt: startedAt);

      expect(
        flow.isResumableAt(startedAt.subtract(const Duration(minutes: 1))),
        isFalse,
      );
    });
  });

  group('measured play evidence', () {
    test('only movement PAST the baseline counts as having practised', () {
      final flow = _flow(step: TenMinuteStep.play, baselineActiveSeconds: 600);

      expect(flow.hasPlayEvidence(600), isFalse, reason: 'nothing moved');
      expect(flow.hasPlayEvidence(599), isFalse, reason: 'a cleared log');
      expect(flow.hasPlayEvidence(601), isTrue);
    });

    test('the recap reports MEASURED minutes, never the planned budget', () {
      final flow = _flow(step: TenMinuteStep.play, baselineActiveSeconds: 600);

      expect(flow.measuredMinutes(600), 0);
      expect(flow.measuredMinutes(660), 1);
      expect(flow.measuredMinutes(1020), 7);
      expect(
        flow.measuredMinutes(659),
        0,
        reason: '59 seconds is not "1 minute practised"',
      );
      expect(flow.measuredMinutes(0), 0, reason: 'never a negative claim');
    });
  });

  group('resolveTenMinuteFlow — the pure view the hub renders', () {
    final now = DateTime(2026, 8, 25, 18, 30);
    final startedAt = DateTime(2026, 8, 25, 18);

    test('no stored chain resolves to nothing', () {
      expect(
        resolveTenMinuteFlow(null, now: now, activeSecondsToday: 0),
        isNull,
      );
    });

    test('an interrupted chain past the resume window is dropped', () {
      final stale = _flow(startedAt: DateTime(2026, 8, 25, 9));

      expect(
        resolveTenMinuteFlow(stale, now: now, activeSecondsToday: 0),
        isNull,
      );
    });

    test('the play step is promoted to the recap ONLY with measured time', () {
      final playing = _flow(
        step: TenMinuteStep.play,
        startedAt: startedAt,
        baselineActiveSeconds: 300,
      );

      expect(
        resolveTenMinuteFlow(playing, now: now, activeSecondsToday: 300)?.step,
        TenMinuteStep.play,
        reason: 'opening the setup screen is not evidence of practising',
      );
      expect(
        resolveTenMinuteFlow(playing, now: now, activeSecondsToday: 361)?.step,
        TenMinuteStep.review,
      );
    });

    test('the tune step is never promoted by practice time alone', () {
      final tuning = _flow(startedAt: startedAt, baselineActiveSeconds: 0);

      expect(
        resolveTenMinuteFlow(tuning, now: now, activeSecondsToday: 999)?.step,
        TenMinuteStep.tune,
      );
    });

    test('resolving never mutates the stored state it was handed', () {
      final playing = _flow(
        step: TenMinuteStep.play,
        startedAt: startedAt,
        baselineActiveSeconds: 0,
      );

      resolveTenMinuteFlow(playing, now: now, activeSecondsToday: 999);

      expect(playing.step, TenMinuteStep.play);
    });
  });
}
