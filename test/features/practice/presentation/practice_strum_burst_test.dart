// The Practice highway views burst at the strike line on every new strum
// (chunk 016b P0 juice brought from Learn/Live to Practice): the overlay
// appears when `strumSeq` rises, in the observed direction, and fades on
// its own so the screen settles.
//
// The same rise also strums the `StrumStringsBand` hung directly under the
// highway (round U4): unlike the burst, the band is ALWAYS mounted — six
// still strings, no scheduled frames — and only its local ticker starts on a
// rise. Under reduced motion neither the spark nor the ticker exists, while
// the band itself stays on screen with its direction parked as a static pick.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart'
    show SsMotionScope, SsStrumStrings;
import 'package:strumsight/core/widgets/strum_burst_overlay.dart';
import 'package:strumsight/core/widgets/strum_strings_band.dart';
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

Widget _host(Widget view, {bool reducedMotion = false}) {
  final app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: view)),
  );
  // The app-level override, not `MediaQueryData.disableAnimations`: the
  // `MaterialApp` installs its own `MediaQuery` from the view, so a
  // `MediaQuery` wrapped around it would never reach the widgets under test.
  if (!reducedMotion) return app;
  return SsMotionScope(appOverride: true, child: app);
}

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

  group('the strings band under the highway rings the same stroke (U4)', () {
    // Height of the gap the views put between the highway and the band, so
    // the "is it directly under the lane?" assertion below stays exact
    // instead of accepting any distance down the column.
    const gap = 8.0;

    Widget strumPattern({
      required int seq,
      bool? isDown,
      double strength = 1,
    }) => StrumPatternView(
      target: _emptyTarget(),
      playhead: Duration.zero,
      visualOffset: Duration.zero,
      width: 600,
      highwayHeight: 168,
      lastVerdict: null,
      metrics: null,
      strumSeq: seq,
      strumIsDown: isDown,
      strumStrength: strength,
    );

    Widget chordProgression({required int seq, bool? isDown}) =>
        ChordProgressionView(
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

    testWidgets('StrumPatternView hangs a 56 dp band directly under the '
        'highway, idle and free', (tester) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(strumPattern(seq: 0)));
      await tester.pumpAndSettle();

      final band = find.byType(StrumStringsBand);
      expect(band, findsOneWidget);
      expect(tester.getSize(band).height, StrumStringsBand.height);
      // Directly under the highway the burst is centred on — one gap, no
      // other widget in between. (An idle `StrumBurstOverlay` renders its
      // child unwrapped, so its box IS the highway's box.)
      expect(
        tester.getTopLeft(band).dy,
        moreOrLessEquals(
          tester.getBottomLeft(find.byType(StrumBurstOverlay)).dy + gap,
          epsilon: 0.5,
        ),
      );
      // An idle band is six still strings: mounted, but animating nothing.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a strumSeq rise starts the band ticker and it stops itself', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(strumPattern(seq: 0)));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(_host(strumPattern(seq: 1, isDown: true)));
      // The stroke is alive: the band's LOCAL ticker asked for a frame.
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(overlay, findsOneWidget);

      // Both the spark and the ring-out end on their own — nothing here is a
      // rhythm animation, so `pumpAndSettle` terminates.
      expect(await tester.pumpAndSettle(), greaterThan(1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(overlay, findsNothing);
      expect(find.byType(StrumStringsBand), findsOneWidget);
    });

    testWidgets('ChordProgressionView rings its band the same way', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(chordProgression(seq: 0)));
      await tester.pumpAndSettle();
      expect(find.byType(StrumStringsBand), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(_host(chordProgression(seq: 1, isDown: false)));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(await tester.pumpAndSettle(), greaterThan(1));
    });

    testWidgets('a stroke with no direction rings nothing', (tester) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(strumPattern(seq: 0)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(strumPattern(seq: 1)));

      // Same rule the burst follows: an undirected stroke is not drawn.
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(overlay, findsNothing);
      expect(find.byType(StrumStringsBand), findsOneWidget);
    });

    testWidgets('reduced motion keeps the band on screen but animates '
        'nothing', (tester) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(strumPattern(seq: 0), reducedMotion: true));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _host(strumPattern(seq: 1, isDown: true), reducedMotion: true),
      );

      // ADR 0274 §5.1 — the motion goes, the information does not: no spark,
      // no ticker, but the band (with its parked pick glyph) is still there.
      expect(await tester.pumpAndSettle(), 1);
      expect(overlay, findsNothing);
      expect(find.byType(StrumStringsBand), findsOneWidget);
      expect(find.byType(SsStrumStrings), findsOneWidget);
    });
  });
}
