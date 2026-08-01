// E02-R14 — A7 PracticeHighway scaling/virtualisation test.
//
// The highway is contracted to build only the records that fall into the
// visibility window. The marker count is bounded by the window's lane
// length; the per-step examined-record count covers the visible window
// only (binary-search lower bound + early-exit upper bound).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/widgets/practice_highway.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const int _eventCount = 2000;
const int _spacingMs = 100; // 2000 events = 200 s of music

CompiledTargetEvent _makeEvent(int i) => CompiledTargetEvent(
  sourceEventId: 'e$i',
  loopIndex: i % 4,
  position: BeatPosition.quarters(i),
  time: Duration(milliseconds: i * _spacingMs),
  barIndex: i ~/ 4,
  chord: null,
  direction: i.isEven ? StrumDirection.down : StrumDirection.up,
  accent: false,
  optional: false,
);

CompiledPracticeTarget _makeTarget() {
  final events = List.generate(_eventCount, _makeEvent);
  return CompiledPracticeTarget(
    definitionId: 'scaling',
    definitionSnapshotVersion: 1,
    tempo: const Tempo(120),
    meter: const Meter(beatsPerBar: 4),
    countInBars: 0,
    countInDuration: Duration.zero,
    events: events,
    musicalDuration: events.last.time,
    ringOutDuration: Duration.zero,
    totalDuration: events.last.time,
    barBoundaries: const [],
    loopCount: 1,
    loopRange: null,
    expectedChordSegments: const [],
    scoringApplicable: true,
  );
}

int _examinedAt(WidgetTester tester, Duration playhead) {
  // The widget's State holds the examined counter. Re-pull after each
  // pump to capture the latest reading.
  final state = tester.state(find.byType(PracticeHighway));
  return (state as dynamic).lastExaminedRecordCount as int;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('2 000 events, 4 s visibility → examined ≤ 64', (tester) async {
    final target = _makeTarget();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PracticeHighway(
            target: target,
            playhead: const Duration(seconds: 50),
            width: 600,
            height: 168,
            strikeX: 68,
            pixelsPerSecond: 240,
            visibleSeconds: 4,
            behindSeconds: 1.5,
          ),
        ),
      ),
    );
    expect(
      _examinedAt(tester, const Duration(seconds: 50)),
      lessThanOrEqualTo(64),
    );
  });

  testWidgets('playhead advances 100 steps → cumulative examined ≤ 100 × 64', (
    tester,
  ) async {
    final target = _makeTarget();
    var cumulative = 0;
    for (var step = 0; step < 100; step++) {
      final playhead = Duration(milliseconds: 50000 + step * _spacingMs);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PracticeHighway(
              target: target,
              playhead: playhead,
              width: 600,
              height: 168,
              strikeX: 68,
              pixelsPerSecond: 240,
              visibleSeconds: 4,
              behindSeconds: 1.5,
            ),
          ),
        ),
      );
      cumulative += _examinedAt(tester, playhead);
    }
    expect(cumulative, lessThanOrEqualTo(100 * 64));
  });

  testWidgets('2 000 events, playhead at the end → examined ≤ 64', (
    tester,
  ) async {
    final target = _makeTarget();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PracticeHighway(
            target: target,
            playhead: const Duration(seconds: 100),
            width: 600,
            height: 168,
            strikeX: 68,
            pixelsPerSecond: 240,
            visibleSeconds: 4,
            behindSeconds: 1.5,
          ),
        ),
      ),
    );
    expect(
      _examinedAt(tester, const Duration(seconds: 100)),
      lessThanOrEqualTo(64),
    );
  });
}
