// The Practice highway views burst at the strike line on every new strum
// (chunk 016b P0 juice brought from Learn/Live to Practice): the overlay
// appears when `strumSeq` rises, in the observed direction, and fades on
// its own so the screen settles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/widgets/strum_burst_overlay.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/views/chord_progression_view.dart';
import 'package:strumsight/features/practice/presentation/views/strum_pattern_view.dart';
import 'package:strumsight/l10n/app_localizations.dart';

CompiledPracticeTarget _emptyTarget() => CompiledPracticeTarget(
  definitionId: 'burst',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(120),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 0,
  countInDuration: Duration.zero,
  events: const [],
  musicalDuration: const Duration(seconds: 4),
  ringOutDuration: Duration.zero,
  totalDuration: const Duration(seconds: 4),
  barBoundaries: const [],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const [],
  scoringApplicable: true,
);

Widget _host(Widget view) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: view)),
);

void main() {
  final overlay = find.byKey(StrumBurstOverlay.overlayKey);

  testWidgets('StrumPatternView bursts on a strumSeq rise and settles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget view({required int seq, bool? isDown}) => StrumPatternView(
      target: _emptyTarget(),
      playhead: Duration.zero,
      visualOffset: Duration.zero,
      width: 600,
      highwayHeight: 168,
      lastVerdict: null,
      metrics: null,
      strumSeq: seq,
      strumIsDown: isDown,
      strumStrength: 1,
    );

    await tester.pumpWidget(_host(view(seq: 0)));
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);

    await tester.pumpWidget(_host(view(seq: 1, isDown: true)));
    await tester.pump();
    expect(overlay, findsOneWidget);

    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
  });

  testWidgets('ChordProgressionView bursts the same way', (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget view({required int seq, bool? isDown}) => ChordProgressionView(
      target: _emptyTarget(),
      playhead: Duration.zero,
      visualOffset: Duration.zero,
      width: 600,
      highwayHeight: 168,
      lastVerdict: null,
      metrics: null,
      showChordHint: false,
      strumSeq: seq,
      strumIsDown: isDown,
      strumStrength: 0.72,
    );

    await tester.pumpWidget(_host(view(seq: 0)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(view(seq: 1, isDown: false)));
    await tester.pump();
    expect(overlay, findsOneWidget);
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
  });

  testWidgets('a strum with no direction never bursts', (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget view(int seq) => StrumPatternView(
      target: _emptyTarget(),
      playhead: Duration.zero,
      visualOffset: Duration.zero,
      width: 600,
      highwayHeight: 168,
      lastVerdict: null,
      metrics: null,
      strumSeq: seq,
    );
    await tester.pumpWidget(_host(view(0)));
    await tester.pumpWidget(_host(view(1)));
    await tester.pump();
    expect(overlay, findsNothing);
  });
}
