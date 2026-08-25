import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/metronome/beat_pulse_dot.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// A4 (brief §6, §0.0/R5.2): the metronome's visual beat pulse must be bound
/// to the audio clock (`SsBeatClock`/`MetronomeBeatClockAdapter`), never a
/// separate `Timer.periodic` — that class of implementation drifts from the
/// audible click, defeating the point of a metronome. This mirrors
/// `test/core/design_system/motion/ss_beat_pulse_test.dart`'s own
/// methodology (feed a controlled lag, read the rendered phase back out of
/// the dot's on-screen size) applied to the metronome's own port + widget.
final class _FakeBeatClock implements SsBeatClock {
  _FakeBeatClock([this.position]);

  @override
  Duration? position;
}

double _expectedDiameter(double phase) => 16 * (1 + (1 - phase) * 0.3);

double _phaseFromDiameter(double diameter) => 1 - (diameter / 16 - 1) / 0.3;

Widget _wrap(Widget child) => MaterialApp(home: Center(child: child));

void main() {
  group('MetronomeBeatClockAdapter — the SsBeatClock port', () {
    test('reflects the exact elapsed-seconds value while playing', () {
      double? secs = 1.25;
      final adapter = MetronomeBeatClockAdapter(() => secs);
      expect(adapter.position, const Duration(microseconds: 1250000));
      secs = 2.5;
      expect(adapter.position, const Duration(microseconds: 2500000));
    });

    test('returns null while stopped (no live timeline)', () {
      final adapter = MetronomeBeatClockAdapter(() => null);
      expect(adapter.position, isNull);
    });
  });

  group('BeatPulseDot — audio-clock-derived phase, never a free timer', () {
    testWidgets('a null position (stopped) renders the muted resting dot', (
      tester,
    ) async {
      final clock = _FakeBeatClock(null);
      await tester.pumpWidget(
        _wrap(
          BeatPulseDot(
            clock: clock,
            beatDuration: const Duration(milliseconds: 500),
            color: Colors.green,
            mutedColor: Colors.grey,
          ),
        ),
      );
      await tester.pump();

      final size = tester.getSize(find.byKey(BeatPulseDot.dotKey));
      expect(size.width, 16);
      final box = tester.widget<Container>(find.byKey(BeatPulseDot.dotKey));
      expect((box.decoration as BoxDecoration).color, Colors.grey);
    });

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
        _wrap(
          BeatPulseDot(
            clock: clock,
            beatDuration: beatDuration,
            color: Colors.green,
            mutedColor: Colors.grey,
          ),
        ),
      );
      await tester.pump();

      final size = tester.getSize(find.byKey(BeatPulseDot.dotKey));
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
        reason: 'lag=$lagMs ms, measured=$measuredLag',
      );
    }

    testWidgets('within tolerance: 0ms lag is accepted', (tester) async {
      await expectRenderedLag(tester, lagMs: 0, accepted: true);
    });

    testWidgets('at the boundary: exactly 100ms lag is accepted (inclusive)', (
      tester,
    ) async {
      await expectRenderedLag(tester, lagMs: 100, accepted: true);
    });

    testWidgets('beyond tolerance: 150ms lag is rejected', (tester) async {
      await expectRenderedLag(tester, lagMs: 150, accepted: false);
    });

    testWidgets('the rendered size exactly matches the phase formula', (
      tester,
    ) async {
      final clock = _FakeBeatClock(const Duration(milliseconds: 250));
      await tester.pumpWidget(
        _wrap(
          BeatPulseDot(
            clock: clock,
            beatDuration: const Duration(milliseconds: 1000),
            color: Colors.green,
            mutedColor: Colors.grey,
          ),
        ),
      );
      await tester.pump();

      final size = tester.getSize(find.byKey(BeatPulseDot.dotKey));
      expect(size.width, closeTo(_expectedDiameter(0.25), 0.01));
    });
  });

  group('MetronomeScreen integration — the dot is bound to the real clock', () {
    Widget app() => const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MetronomeScreen(),
    );

    testWidgets('stopped: the beat dot is present but at rest', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      final size = tester.getSize(find.byKey(BeatPulseDot.dotKey));
      expect(size.width, 16);
    });

    testWidgets('playing: the beat dot pulses as time advances', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();

      final sizes = <double>{};
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        sizes.add(tester.getSize(find.byKey(BeatPulseDot.dotKey)).width);
      }
      // Stop again so no ticker is active at teardown.
      await tester.tap(find.text('Stop'));
      await tester.pump();

      expect(
        sizes.length,
        greaterThan(1),
        reason: 'the dot must visibly change as the audio clock advances',
      );
    });
  });
}
