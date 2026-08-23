import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

final class _FakeBeatClock implements SsBeatClock {
  _FakeBeatClock([this.position]);

  @override
  Duration? position;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: SsDarkTheme.data(),
    home: Center(child: child),
  );
}

double _expectedDiameter(double phase) => 16 * (1 + (1 - phase) * 0.3);

// Inverse of `_expectedDiameter`: recovers the phase the widget actually
// rendered from the dot's on-screen size, so the threshold cells below
// measure the WIDGET's output, not a number handed straight to the predicate.
double _phaseFromDiameter(double diameter) => 1 - (diameter / 16 - 1) / 0.3;

void main() {
  group(
    'A3 — the three sync-tolerance threshold cells drive the real widget',
    () {
      // The clock is fed a position that lags a known "true" position by
      // `lagMs` — simulating staleness in what the clock reports. The dot is
      // rendered, its phase is read back out of its on-screen size, and
      // converted back to the position it implies. Only a widget that
      // genuinely derives its displayed phase from `clock.position` (and not,
      // say, a free-running ticker) reproduces `lagMs` exactly here.
      Future<void> expectRenderedLag(
        WidgetTester tester, {
        required int lagMs,
        required bool accepted,
      }) async {
        const beatDuration = Duration(milliseconds: 1000);
        const truePosition = Duration(milliseconds: 500);
        final clockPosition = truePosition - Duration(milliseconds: lagMs);
        final clock = _FakeBeatClock(clockPosition);
        await tester.pumpWidget(
          _wrap(SsBeatPulse(clock: clock, beatDuration: beatDuration)),
        );
        await tester.pump();

        final size = tester.getSize(find.byKey(SsBeatPulse.dotKey));
        final renderedPhase = _phaseFromDiameter(size.width);
        final renderedPosition = Duration(
          microseconds: (renderedPhase * beatDuration.inMicroseconds).round(),
        );
        final measuredLag = Duration(
          microseconds:
              (truePosition.inMicroseconds - renderedPosition.inMicroseconds)
                  .abs(),
        );

        expect(
          SsBeatPulse.isWithinSyncTolerance(measuredLag),
          accepted,
          reason: 'rendered visual lag measured as $measuredLag',
        );
      }

      testWidgets('60ms rendered lag from the clock: accepted', (tester) async {
        await expectRenderedLag(tester, lagMs: 60, accepted: true);
      });

      testWidgets(
        '100ms rendered lag sits on the threshold: accepted (inclusive bound)',
        (tester) async {
          await expectRenderedLag(tester, lagMs: 100, accepted: true);
        },
      );

      testWidgets('140ms rendered lag is over the threshold: rejected', (
        tester,
      ) async {
        await expectRenderedLag(tester, lagMs: 140, accepted: false);
      });
    },
  );

  group('A2 — the pulse is derived from the injected clock, not wall time', () {
    testWidgets('the phase does not move while the clock position is held', (
      tester,
    ) async {
      final clock = _FakeBeatClock(const Duration(milliseconds: 100));
      await tester.pumpWidget(
        _wrap(
          SsBeatPulse(
            clock: clock,
            beatDuration: const Duration(milliseconds: 1000),
          ),
        ),
      );
      await tester.pump();
      final before = tester.getSize(find.byKey(SsBeatPulse.dotKey));

      // Real time advances across several frames, but the clock's position
      // is never updated — an independent-timer implementation would still
      // move the phase forward; a clock-derived one must not.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final after = tester.getSize(find.byKey(SsBeatPulse.dotKey));

      expect(after, before);
    });

    testWidgets('the phase tracks the clock position directly', (tester) async {
      final clock = _FakeBeatClock(const Duration(milliseconds: 200));
      await tester.pumpWidget(
        _wrap(
          SsBeatPulse(
            clock: clock,
            beatDuration: const Duration(milliseconds: 1000),
          ),
        ),
      );
      await tester.pump();
      final size = tester.getSize(find.byKey(SsBeatPulse.dotKey));
      final expected = _expectedDiameter(0.2);
      expect(size.width, closeTo(expected, 0.05));
      expect(size.height, closeTo(expected, 0.05));
    });
  });

  group(
    'A3 — seek and stop are reflected immediately, with no accumulated drift',
    () {
      testWidgets('a forward seek is reflected on the very next frame', (
        tester,
      ) async {
        final clock = _FakeBeatClock(const Duration(milliseconds: 100));
        const beatDuration = Duration(milliseconds: 1000);
        await tester.pumpWidget(
          _wrap(SsBeatPulse(clock: clock, beatDuration: beatDuration)),
        );
        await tester.pump();
        expect(
          tester.getSize(find.byKey(SsBeatPulse.dotKey)).width,
          closeTo(_expectedDiameter(0.1), 0.05),
        );

        // Seek far ahead — a drifting implementation would still be near the
        // old trajectory; a clock-derived one snaps to the new true phase.
        clock.position = const Duration(milliseconds: 900);
        await tester.pump();
        expect(
          tester.getSize(find.byKey(SsBeatPulse.dotKey)).width,
          closeTo(_expectedDiameter(0.9), 0.05),
        );
      });

      testWidgets('stopping the clock (null position) freezes the pulse', (
        tester,
      ) async {
        final clock = _FakeBeatClock(const Duration(milliseconds: 300));
        await tester.pumpWidget(
          _wrap(
            SsBeatPulse(
              clock: clock,
              beatDuration: const Duration(milliseconds: 1000),
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(SsBeatPulse.dotKey), findsOneWidget);

        clock.position = null;
        await tester.pump();
        final frozen = tester.getSize(find.byKey(SsBeatPulse.dotKey));

        // Real time keeps passing with no live timeline: still not animating.
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.getSize(find.byKey(SsBeatPulse.dotKey)), frozen);
      });
    },
  );

  group(
    'A1 — reduced motion keeps the feedback observable and clock-linked',
    () {
      testWidgets(
        'no scale under reduced motion, but the color still steps with the beat',
        (tester) async {
          final clock = _FakeBeatClock(const Duration(milliseconds: 100));
          const beatDuration = Duration(milliseconds: 1000);
          await tester.pumpWidget(
            _wrap(
              SsMotionScope(
                appOverride: true,
                child: SsBeatPulse(clock: clock, beatDuration: beatDuration),
              ),
            ),
          );
          await tester.pump();

          // Full motion would scale the dot per-phase (see the A2/A3 tests
          // above); under reduced motion it must stay pinned to the base size.
          final onBeatSize = tester.getSize(find.byKey(SsBeatPulse.dotKey));
          expect(onBeatSize, const Size(16, 16));
          final onBeatColor = tester
              .widget<Container>(find.byKey(SsBeatPulse.dotKey))
              .decoration;

          // Cross the beat's midpoint: the feedback must still change with the
          // clock's phase — this is the falsification of `if (reduceMotion)
          // return child;`, which would render an unchanging widget instead.
          clock.position = const Duration(milliseconds: 700);
          await tester.pump();
          final offBeatSize = tester.getSize(find.byKey(SsBeatPulse.dotKey));
          final offBeatColor = tester
              .widget<Container>(find.byKey(SsBeatPulse.dotKey))
              .decoration;

          expect(offBeatSize, onBeatSize, reason: 'still no scale');
          expect(
            offBeatColor,
            isNot(onBeatColor),
            reason:
                'the modality that replaces scale must still track the beat',
          );
        },
      );
    },
  );

  group('A4 — dispose leaves no live controller and calls no setState', () {
    testWidgets('removing the widget stops updates and leaves no ticker', (
      tester,
    ) async {
      final clock = _FakeBeatClock(Duration.zero);
      await tester.pumpWidget(
        _wrap(
          SsBeatPulse(
            clock: clock,
            beatDuration: const Duration(milliseconds: 500),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);

      // Advance the injected clock past disposal — a leaked ticker or a
      // setState-after-dispose call would throw here or at test teardown.
      clock.position = const Duration(milliseconds: 400);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no live timeline renders a static, non-animating state', (
    tester,
  ) async {
    final clock = _FakeBeatClock();
    await tester.pumpWidget(
      _wrap(
        SsBeatPulse(
          clock: clock,
          beatDuration: const Duration(milliseconds: 500),
        ),
      ),
    );
    await tester.pump();
    final before = tester.getSize(find.byKey(SsBeatPulse.dotKey));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(find.byKey(SsBeatPulse.dotKey)), before);
  });

  group('reduced motion off-beat is distinguishable from "not playing"', () {
    testWidgets('the off-beat color differs from the no-live-timeline color', (
      tester,
    ) async {
      final clock = _FakeBeatClock(const Duration(milliseconds: 700));
      const beatDuration = Duration(milliseconds: 1000);

      await tester.pumpWidget(
        _wrap(
          SsMotionScope(
            appOverride: true,
            child: SsBeatPulse(clock: clock, beatDuration: beatDuration),
          ),
        ),
      );
      await tester.pump();
      // phase 0.7 -> second half of the beat -> off-beat color.
      final offBeatColor = tester
          .widget<Container>(find.byKey(SsBeatPulse.dotKey))
          .decoration;

      clock.position = null;
      await tester.pump();
      final stoppedColor = tester
          .widget<Container>(find.byKey(SsBeatPulse.dotKey))
          .decoration;

      expect(
        offBeatColor,
        isNot(stoppedColor),
        reason:
            'a reduced-motion off-beat must not look identical to '
            'playback being stopped',
      );
    });
  });

  group(
    'beatDuration <= 0 is a real runtime guard, not just a debug assert',
    () {
      testWidgets(
        'a zero beatDuration renders the static no-live-timeline state '
        'instead of throwing',
        (tester) async {
          final clock = _FakeBeatClock(const Duration(milliseconds: 250));
          await tester.pumpWidget(
            _wrap(SsBeatPulse(clock: clock, beatDuration: Duration.zero)),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(SsBeatPulse.dotKey)),
            const Size(16, 16),
          );
        },
      );
    },
  );

  group('MAJOR-2 regression — the pulse resumes on its own, without a rebuild '
      '(the ticker keeps running, matching the CircularProgressIndicator '
      'idiom, per ADR 0274 §1 and the second review round)', () {
    testWidgets(
      'PROBE_D — the pulse comes alive once the clock starts reporting a '
      'position, with no pumpWidget call in between',
      (tester) async {
        final clock = _FakeBeatClock();
        await tester.pumpWidget(
          _wrap(
            SsBeatPulse(
              clock: clock,
              beatDuration: const Duration(milliseconds: 500),
            ),
          ),
        );
        await tester.pump();
        final dead = tester.getSize(find.byKey(SsBeatPulse.dotKey));
        expect(dead, const Size(16, 16));

        // The clock starts reporting a position — nothing rebuilds the
        // widget; only the ticker's own frames can pick this up.
        clock.position = const Duration(milliseconds: 100);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        final afterGoingLive = tester.getSize(find.byKey(SsBeatPulse.dotKey));
        expect(
          afterGoingLive,
          isNot(dead),
          reason:
              'a continuously running ticker must pick up the live '
              'position on its own, without the caller rebuilding this '
              'widget',
        );
      },
    );

    testWidgets('PROBE_E — a pause/resume mid-playback is picked up with no '
        'pumpWidget call in between', (tester) async {
      final clock = _FakeBeatClock(const Duration(milliseconds: 100));
      const beatDuration = Duration(milliseconds: 500);
      await tester.pumpWidget(
        _wrap(SsBeatPulse(clock: clock, beatDuration: beatDuration)),
      );
      await tester.pump();

      clock.position = null;
      await tester.pump();
      final frozen = tester.getSize(find.byKey(SsBeatPulse.dotKey));
      expect(frozen, const Size(16, 16));

      // Resume — again, nothing rebuilds the widget.
      clock.position = const Duration(milliseconds: 300);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      final afterResume = tester.getSize(find.byKey(SsBeatPulse.dotKey));
      expect(
        afterResume,
        isNot(frozen),
        reason:
            'resuming a live timeline must revive the pulse on its '
            'own, without the caller rebuilding this widget',
      );
    });
  });
}
