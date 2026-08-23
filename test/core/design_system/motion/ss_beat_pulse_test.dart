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

void main() {
  group(
    'SsBeatPulse.isWithinSyncTolerance — A3, the three threshold cells',
    () {
      test('60ms lag is under the threshold: accepted', () {
        expect(
          SsBeatPulse.isWithinSyncTolerance(const Duration(milliseconds: 60)),
          isTrue,
        );
      });

      test('100ms lag sits on the threshold: accepted (inclusive bound)', () {
        expect(
          SsBeatPulse.isWithinSyncTolerance(const Duration(milliseconds: 100)),
          isTrue,
        );
      });

      test('140ms lag is over the threshold: rejected', () {
        expect(
          SsBeatPulse.isWithinSyncTolerance(const Duration(milliseconds: 140)),
          isFalse,
        );
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
}
