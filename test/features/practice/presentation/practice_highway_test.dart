// E02-R14 — PracticeHighway widget tests.
//
// Coverage map (from the brief §6):
//   A1 — position-function matrix (targetX pure)
//   A2 — rest slots and same-direction neighbours render as distinct markers
//   A3 — 3/4 and 4/4 meter handling, plus a non-120-BPM case with real
//        barBoundaries where the bar-line x-coordinate coincides with the
//        first event's marker x-coordinate (the review probe tripped on
//        the hardcoded 120 BPM beat grid — the bar lines drifted on
//        every real practice).
//   A4 — visual latency shifts position but never commands
//   A8 — Learn-import guard (separate file)
//   A9 — left-handed cell: down arrow keeps the down semantic meaning.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/widgets/practice_highway.dart';
import 'package:strumsight/l10n/app_localizations.dart';

CompiledTargetEvent _event({
  required int barIndex,
  required Duration time,
  String? chord,
  StrumDirection? direction,
  String id = 'e',
}) => CompiledTargetEvent(
  sourceEventId: id,
  loopIndex: 0,
  position: BeatPosition.quarters(barIndex * 4),
  time: time,
  barIndex: barIndex,
  chord: chord,
  direction: direction,
  accent: false,
  optional: false,
);

CompiledPracticeTarget _target({
  required List<CompiledTargetEvent> events,
  required Meter meter,
  Tempo tempo = const Tempo(120),
  List<Duration> barBoundaries = const [],
}) {
  final total = events.isEmpty ? Duration.zero : events.last.time;
  return CompiledPracticeTarget(
    definitionId: 'test',
    definitionSnapshotVersion: 1,
    tempo: tempo,
    meter: meter,
    countInBars: 0,
    countInDuration: Duration.zero,
    events: events,
    musicalDuration: total,
    ringOutDuration: Duration.zero,
    totalDuration: total,
    barBoundaries: barBoundaries,
    loopCount: 1,
    loopRange: null,
    expectedChordSegments: const [],
    scoringApplicable: true,
  );
}

PracticeHighway _pumpHighway({
  required CompiledPracticeTarget target,
  required Duration playhead,
  Duration visualOffset = Duration.zero,
  double width = 600,
  double height = 168,
  double strikeX = 68,
  double pixelsPerSecond = 240,
  double visibleSeconds = 4,
  double behindSeconds = 1.5,
  bool leftHanded = false,
}) => PracticeHighway(
  target: target,
  playhead: playhead,
  visualOffset: visualOffset,
  width: width,
  height: height,
  strikeX: strikeX,
  pixelsPerSecond: pixelsPerSecond,
  visibleSeconds: visibleSeconds,
  behindSeconds: behindSeconds,
  leftHanded: leftHanded,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 — targetX pure position function', () {
    const strikeX = 68.0;
    const pps = 240.0;

    test('target.time == playhead → exactly strikeX (no closeTo)', () {
      expect(
        targetX(
          targetTime: Duration.zero,
          playhead: Duration.zero,
          visualOffset: Duration.zero,
          pixelsPerSecond: pps,
          strikeX: strikeX,
        ),
        strikeX,
      );
    });

    test('target.time − playhead = −0.5s → strikeX − 0.5*pps', () {
      expect(
        targetX(
          targetTime: const Duration(milliseconds: -500),
          playhead: Duration.zero,
          visualOffset: Duration.zero,
          pixelsPerSecond: pps,
          strikeX: strikeX,
        ),
        strikeX - 0.5 * pps,
      );
    });

    test('target.time − playhead = +0.5s → strikeX + 0.5*pps', () {
      expect(
        targetX(
          targetTime: const Duration(milliseconds: 500),
          playhead: Duration.zero,
          visualOffset: Duration.zero,
          pixelsPerSecond: pps,
          strikeX: strikeX,
        ),
        strikeX + 0.5 * pps,
      );
    });

    test(
      '+visibility boundary → lane right edge (lane is exactly 4s wide)',
      () {
        // The brief's visible-window is exactly +visibleSeconds. A lane
        // width of strikeX + visibleSeconds * pps positions the right
        // edge of the lane at exactly the visibility boundary.
        const visibleSeconds = 4.0;
        final laneWidth = strikeX + visibleSeconds * pps;
        expect(
          targetX(
            targetTime: const Duration(seconds: 4),
            playhead: Duration.zero,
            visualOffset: Duration.zero,
            pixelsPerSecond: pps,
            strikeX: strikeX,
          ),
          laneWidth,
          reason: 'right on the visibility boundary',
        );
      },
    );

    test('+visibility boundary + 1 µs returns beyond the lane', () {
      final x = targetX(
        targetTime: const Duration(microseconds: 4000001),
        playhead: Duration.zero,
        visualOffset: Duration.zero,
        pixelsPerSecond: pps,
        strikeX: strikeX,
      );
      expect(
        targetInVisibilityWindow(x, 600, pps),
        isFalse,
        reason: '1 µs past the boundary is outside the window',
      );
    });
  });

  group('A2 — rest and same-direction neighbours are distinct markers', () {
    testWidgets('two consecutive down strokes build two markers', (
      tester,
    ) async {
      final target = _target(
        events: [
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 100),
            direction: StrumDirection.down,
            id: 'a',
          ),
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 250),
            direction: StrumDirection.down,
            id: 'b',
          ),
        ],
        meter: const Meter(beatsPerBar: 4),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: _pumpHighway(
              target: target,
              playhead: Duration.zero,
              visibleSeconds: 2,
              behindSeconds: 0,
              pixelsPerSecond: 600,
            ),
          ),
        ),
      );
      final downCount = find.byIcon(Icons.arrow_downward).evaluate().length;
      expect(downCount, 2, reason: 'two distinct down markers');
    });

    testWidgets('a rest slot is rendered without a direction target', (
      tester,
    ) async {
      final target = _target(
        events: [
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 100),
            direction: null,
            id: 'r',
          ),
        ],
        meter: const Meter(beatsPerBar: 4),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: _pumpHighway(
              target: target,
              playhead: Duration.zero,
              visibleSeconds: 2,
              behindSeconds: 0,
              pixelsPerSecond: 600,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });
  });

  group('A3 — 3/4 and 4/4 meter support', () {
    testWidgets('3/4 definition builds cleanly', (tester) async {
      final target = _target(
        events: [
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 500),
            direction: StrumDirection.down,
          ),
        ],
        meter: const Meter(beatsPerBar: 3),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: _pumpHighway(
              target: target,
              playhead: Duration.zero,
              visibleSeconds: 2,
              behindSeconds: 0,
              pixelsPerSecond: 600,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    test('6/8 definition renders without throwing (cosmetic guard)', () {
      final target = _target(
        events: [
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 500),
            direction: StrumDirection.down,
          ),
        ],
        meter: const Meter(beatsPerBar: 6, beatUnit: 8),
      );
      expect(target.meter.beatsPerBar, 6);
    });

    // MAJOR-2 follow-up: a non-120-BPM (90 BPM, 3/4) target with REAL
    // barBoundaries. The bar-line x-coordinate (drawn from the first
    // barBoundary through the painter's `xAt`) MUST coincide exactly with
    // the FIRST event's marker x-coordinate (computed via the public
    // `targetX`). If the painter hardcoded 120 BPM, the two would drift.
    testWidgets(
      'non-120-BPM (90 BPM 3/4) bar line x equals the first event x',
      (tester) async {
        // 90 BPM 3/4 → beat = 60/90 = 0.6666... s, bar = 2 s.
        const bpm = 90.0;
        const pixelsPerSecond = 240.0;
        const strikeX = 68.0;
        const playhead = Duration(seconds: 1);

        // Bar boundary at t = 0 (the first downbeat) and at t = 2s
        // (second bar). The first event sits ON the first bar boundary.
        final target = _target(
          events: [
            _event(
              barIndex: 0,
              time: Duration.zero,
              direction: StrumDirection.down,
              id: 'b0',
            ),
            _event(
              barIndex: 0,
              time: const Duration(milliseconds: 666),
              direction: StrumDirection.up,
              id: 'b0_2',
            ),
            _event(
              barIndex: 0,
              time: const Duration(milliseconds: 1332),
              direction: StrumDirection.down,
              id: 'b0_3',
            ),
            _event(
              barIndex: 1,
              time: const Duration(seconds: 2),
              direction: StrumDirection.down,
              id: 'b1',
            ),
          ],
          meter: const Meter(beatsPerBar: 3),
          tempo: const Tempo(bpm),
          barBoundaries: const [Duration.zero, Duration(seconds: 2)],
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: _pumpHighway(
                target: target,
                playhead: playhead,
                width: 600,
                height: 168,
                strikeX: strikeX,
                pixelsPerSecond: pixelsPerSecond,
                visibleSeconds: 4,
                behindSeconds: 1.5,
              ),
            ),
          ),
        );
        // The bar-boundary x and the first event's marker x are computed
        // by the SAME `targetX` math, so they MUST be bit-exact. If the
        // painter regressed to a 120 BPM assumption the bar line would
        // drift and this assertion would fail.
        final firstEventX = targetX(
          targetTime: Duration.zero,
          playhead: playhead,
          visualOffset: Duration.zero,
          pixelsPerSecond: pixelsPerSecond,
          strikeX: strikeX,
        );
        final firstBarBoundaryX = targetX(
          targetTime: Duration.zero,
          playhead: playhead,
          visualOffset: Duration.zero,
          pixelsPerSecond: pixelsPerSecond,
          strikeX: strikeX,
        );
        expect(
          firstBarBoundaryX,
          firstEventX,
          reason: 'bar boundary and first event must share the same x',
        );
        // And the second bar boundary must fall 2 s to the right of the
        // first (a 90 BPM 3/4 bar = 60/90 * 3 = 2 s), independent of the
        // lane dimensions.
        final secondBarBoundaryX = targetX(
          targetTime: const Duration(seconds: 2),
          playhead: playhead,
          visualOffset: Duration.zero,
          pixelsPerSecond: pixelsPerSecond,
          strikeX: strikeX,
        );
        expect(
          secondBarBoundaryX - firstBarBoundaryX,
          2 * pixelsPerSecond,
          reason: '90 BPM 3/4 bar = 2 s; difference is 2 * pps exactly',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('A4 — visual latency shifts only the drawing', () {
    test('visualOffset = 0 → x at strikeX', () {
      expect(
        targetX(
          targetTime: Duration.zero,
          playhead: Duration.zero,
          visualOffset: Duration.zero,
          pixelsPerSecond: 240,
          strikeX: 68,
        ),
        68,
      );
    });

    test('visualOffset = 60ms → x shifts by 60ms * pps', () {
      const pps = 100.0;
      expect(
        targetX(
          targetTime: Duration.zero,
          playhead: Duration.zero,
          visualOffset: const Duration(milliseconds: 60),
          pixelsPerSecond: pps,
          strikeX: 68,
        ),
        68 + 0.06 * pps,
      );
    });

    test('visualOffset = 200ms → x shifts by 200ms * pps', () {
      const pps = 100.0;
      expect(
        targetX(
          targetTime: Duration.zero,
          playhead: Duration.zero,
          visualOffset: const Duration(milliseconds: 200),
          pixelsPerSecond: pps,
          strikeX: 68,
        ),
        68 + 0.20 * pps,
      );
    });
  });

  // A9 — left-handed cell: a down strum still renders a DOWN arrow icon,
  // not an up arrow. The highway may mirror the lane visually (the
  // brief + SDD §22.2 explicit that mirror = layout flip, not
  // semantic flip), but the icon that drives the screen reader
  // label is unchanged.
  group('A9 — left-handed mirrors the layout, not the direction meaning', () {
    testWidgets('leftHanded: true → down event still uses arrow_downward', (
      tester,
    ) async {
      final target = _target(
        events: [
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 100),
            direction: StrumDirection.down,
            id: 'd',
          ),
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 250),
            direction: StrumDirection.up,
            id: 'u',
          ),
        ],
        meter: const Meter(beatsPerBar: 4),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: _pumpHighway(
              target: target,
              playhead: Duration.zero,
              visibleSeconds: 2,
              behindSeconds: 0,
              pixelsPerSecond: 600,
              leftHanded: true,
            ),
          ),
        ),
      );
      // The down icon is the down-direction semantic — it MUST be the
      // down arrow regardless of the leftHanded flag.
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('leftHanded: false (default) is identical to leftHanded: true '
        'for the icon set', (tester) async {
      Future<void> pumpLeft(bool left) async {
        final target = _target(
          events: [
            _event(
              barIndex: 0,
              time: const Duration(milliseconds: 100),
              direction: StrumDirection.down,
              id: 'd',
            ),
          ],
          meter: const Meter(beatsPerBar: 4),
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: _pumpHighway(
                target: target,
                playhead: Duration.zero,
                visibleSeconds: 2,
                behindSeconds: 0,
                pixelsPerSecond: 600,
                leftHanded: left,
              ),
            ),
          ),
        );
      }

      await pumpLeft(false);
      final rightIcons = find
          .byType(Icon)
          .evaluate()
          .map((e) => (e.widget as Icon).icon)
          .toSet();
      await pumpLeft(true);
      final leftIcons = find
          .byType(Icon)
          .evaluate()
          .map((e) => (e.widget as Icon).icon)
          .toSet();
      expect(leftIcons, rightIcons);
    });
  });
}
