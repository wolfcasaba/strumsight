import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';

void main() {
  group('PracticeSessionState', () {
    test('initial state is idle and empty', () {
      const state = PracticeSessionState.initial;
      expect(state.status, PracticeSessionStatus.idle);
      expect(state.definition, isNull);
      expect(state.config, isNull);
      expect(state.target, isNull);
      expect(state.attemptIndex, 0);
      expect(state.finishReason, isNull);
      expect(state.pauseCause, isNull);
      expect(state.recoverableFailure, isNull);
      expect(state.timelineBase, Duration.zero);
      expect(state.activeBase, Duration.zero);
      expect(state.pausedAtTimeline, isNull);
      expect(state.countInSpanStartActive, isNull);
      expect(state.emittedCountInClicks, 0);
      expect(state.wallElapsed, Duration.zero);
      expect(state.activeElapsed, Duration.zero);
      expect(state.pausedElapsed, Duration.zero);
      expect(state.countInElapsed, Duration.zero);
      expect(state.playingElapsed, Duration.zero);
      expect(state.attemptElapsed, Duration.zero);
      expect(state.timelinePosition, Duration.zero);
      expect(state.isActive, isFalse);
      expect(state.musicalPosition, isNull);
    });

    test('value equality: same fields → equal', () {
      const a = PracticeSessionState(status: PracticeSessionStatus.running);
      const b = PracticeSessionState(status: PracticeSessionStatus.running);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality: any field change → not equal', () {
      const a = PracticeSessionState(
        status: PracticeSessionStatus.running,
        attemptIndex: 0,
      );
      const b = PracticeSessionState(
        status: PracticeSessionStatus.running,
        attemptIndex: 1,
      );
      expect(a, isNot(equals(b)));
    });

    test('copyWith: explicit overrides win; cleared fields go to null', () {
      const original = PracticeSessionState(
        status: PracticeSessionStatus.running,
        attemptIndex: 2,
        pausedAtTimeline: Duration(milliseconds: 500),
        timelineBase: Duration(seconds: 4),
      );

      final bumpedAttempt = original.copyWith(attemptIndex: 5);
      expect(bumpedAttempt.attemptIndex, 5);
      expect(bumpedAttempt.status, original.status);
      expect(bumpedAttempt.pausedAtTimeline, original.pausedAtTimeline);

      final clearedPause = original.copyWith(clearPausedAtTimeline: true);
      expect(clearedPause.pausedAtTimeline, isNull);
      expect(clearedPause.status, original.status);
    });

    test(
      'timelinePosition: formula holds for all five anchor combinations',
      () {
        // activeElapsed < activeBase → clamped to timelineBase.
        const waitingOnResume = PracticeSessionState(
          status: PracticeSessionStatus.countIn,
          timelineBase: Duration(seconds: 4),
          activeBase: Duration(seconds: 9),
          activeElapsed: Duration(seconds: 5),
        );
        expect(waitingOnResume.timelinePosition, const Duration(seconds: 4));

        // activeElapsed == activeBase → just at the anchor, no offset.
        const atResumeEnd = PracticeSessionState(
          status: PracticeSessionStatus.countIn,
          timelineBase: Duration(seconds: 4),
          activeBase: Duration(seconds: 9),
          activeElapsed: Duration(seconds: 9),
        );
        expect(atResumeEnd.timelinePosition, const Duration(seconds: 4));

        // activeElapsed > activeBase → offset grows.
        const pastResume = PracticeSessionState(
          status: PracticeSessionStatus.running,
          timelineBase: Duration(seconds: 4),
          activeBase: Duration(seconds: 9),
          activeElapsed: Duration(seconds: 11),
        );
        expect(pastResume.timelinePosition, const Duration(seconds: 6));

        // Initial count-in: timelineBase = 0, activeBase = 0; timeline
        // moves 1:1 with activeElapsed.
        const initialCountIn = PracticeSessionState(
          status: PracticeSessionStatus.countIn,
          timelineBase: Duration.zero,
          activeBase: Duration.zero,
          activeElapsed: Duration(milliseconds: 250),
        );
        expect(
          initialCountIn.timelinePosition,
          const Duration(milliseconds: 250),
        );
      },
    );

    test('isActive: true for countIn/running/paused/finishing only', () {
      for (final status in PracticeSessionStatus.values) {
        final expected = const {
          PracticeSessionStatus.countIn,
          PracticeSessionStatus.running,
          PracticeSessionStatus.paused,
          PracticeSessionStatus.finishing,
        }.contains(status);
        expect(
          PracticeSessionState(status: status).isActive,
          expected,
          reason: 'status=$status',
        );
      }
    });
  });

  group('allowedTransitions (SDD §11.2 verbatim)', () {
    test('idle → preparing', () {
      expect(
        allowedTransitions[PracticeSessionStatus.idle],
        equals({PracticeSessionStatus.preparing}),
      );
    });

    test('preparing → permissionRequired | ready | failed', () {
      expect(
        allowedTransitions[PracticeSessionStatus.preparing],
        equals({
          PracticeSessionStatus.permissionRequired,
          PracticeSessionStatus.ready,
          PracticeSessionStatus.failed,
        }),
      );
    });

    test('permissionRequired → preparing | cancelled', () {
      expect(
        allowedTransitions[PracticeSessionStatus.permissionRequired],
        equals({
          PracticeSessionStatus.preparing,
          PracticeSessionStatus.cancelled,
        }),
      );
    });

    test('ready → countIn | cancelled', () {
      expect(
        allowedTransitions[PracticeSessionStatus.ready],
        equals({
          PracticeSessionStatus.countIn,
          PracticeSessionStatus.cancelled,
        }),
      );
    });

    test('countIn → running | paused | cancelled | failed', () {
      expect(
        allowedTransitions[PracticeSessionStatus.countIn],
        equals({
          PracticeSessionStatus.running,
          PracticeSessionStatus.paused,
          PracticeSessionStatus.cancelled,
          PracticeSessionStatus.failed,
        }),
      );
    });

    test('running → paused | finishing | cancelled | failed', () {
      expect(
        allowedTransitions[PracticeSessionStatus.running],
        equals({
          PracticeSessionStatus.paused,
          PracticeSessionStatus.finishing,
          PracticeSessionStatus.cancelled,
          PracticeSessionStatus.failed,
        }),
      );
    });

    test('paused → countIn | running | finishing | cancelled', () {
      expect(
        allowedTransitions[PracticeSessionStatus.paused],
        equals({
          PracticeSessionStatus.countIn,
          PracticeSessionStatus.running,
          PracticeSessionStatus.finishing,
          PracticeSessionStatus.cancelled,
        }),
      );
    });

    test('finishing → completed | failed', () {
      expect(
        allowedTransitions[PracticeSessionStatus.finishing],
        equals({PracticeSessionStatus.completed, PracticeSessionStatus.failed}),
      );
    });

    test('completed → ready | idle', () {
      expect(
        allowedTransitions[PracticeSessionStatus.completed],
        equals({PracticeSessionStatus.ready, PracticeSessionStatus.idle}),
      );
    });

    test('cancelled → ready | idle', () {
      expect(
        allowedTransitions[PracticeSessionStatus.cancelled],
        equals({PracticeSessionStatus.ready, PracticeSessionStatus.idle}),
      );
    });

    test('failed → preparing | idle', () {
      expect(
        allowedTransitions[PracticeSessionStatus.failed],
        equals({PracticeSessionStatus.preparing, PracticeSessionStatus.idle}),
      );
    });

    test('every status has a transition entry', () {
      for (final status in PracticeSessionStatus.values) {
        expect(
          allowedTransitions.containsKey(status),
          isTrue,
          reason: 'missing entry for $status',
        );
      }
    });
  });
}
