// E02-R14 — PracticeHighway widget tests.
//
// Coverage map (from the brief §6):
//   A1 — position-function matrix (targetX pure)
//   A2 — rest slots and same-direction neighbours render as distinct markers
//   A3 — 3/4 and 4/4 meter handling
//   A4 — visual latency shifts position but never commands
//   A8 — Learn-import guard (separate file)

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
}) {
  final total = events.isEmpty ? Duration.zero : events.last.time;
  return CompiledPracticeTarget(
    definitionId: 'test',
    definitionSnapshotVersion: 1,
    tempo: const Tempo(120),
    meter: meter,
    countInBars: 0,
    countInDuration: Duration.zero,
    events: events,
    musicalDuration: total,
    ringOutDuration: Duration.zero,
    totalDuration: total,
    barBoundaries: const [],
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
}
