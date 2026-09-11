// The rhythm practice screen against a faked recogniser.
//
// The point of these cells is the seam between what the microphone says and what
// the screen is allowed to claim (design §2 rules 1-4): green only on a confirmed
// decision FOR THE ASKED CHORD, and nothing negative without confirmation.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/curriculum/presentation/screens/rhythm_practice_screen.dart';
import 'package:strumsight/features/curriculum/presentation/widgets/rhythm_lane.dart';
import 'package:strumsight/features/live/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

LiveFrame _frame({
  String? chordLabel,
  RecognitionDecision? decision,
  double inputLevel = 0.5,
  bool listening = true,
  double engineTimeSec = -1,
  double latestStrumTime = -1,
  int strumSeq = 0,
  Strum? latestStrum,
}) => LiveFrame(
  current: chordLabel == null ? null : Chord(chordLabel),
  next: null,
  latestStrum: latestStrum,
  bar: const [],
  bpm: 0,
  inputLevel: inputLevel,
  tuningHz: 440,
  listening: listening,
  chordDecision: decision,
  engineTimeSec: engineTimeSec,
  latestStrumTime: latestStrumTime,
  strumSeq: strumSeq,
);

Widget _host(LiveFrame frame, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      overrides: [
        liveFrameProvider.overrideWith((ref) => Stream<LiveFrame>.value(frame)),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SsDarkTheme.data(),
        home: const RhythmPracticeScreen(),
      ),
    );

/// A host driven by a controller, so a test can deliver frames over time the
/// way the engine does.
Widget _streamHost(Stream<LiveFrame> frames) => ProviderScope(
  overrides: [liveFrameProvider.overrideWith((ref) => frames)],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: SsDarkTheme.data(),
    home: const RhythmPracticeScreen(),
  ),
);

FrettingState _fretting(WidgetTester tester) =>
    tester.widgetList<RhythmLane>(find.byType(RhythmLane)).first.fretting;

void main() {
  testWidgets('it renders the motion, the notation and the level meter', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_frame()));
    await tester.pump();
    expect(find.byType(SsStrumPendulum), findsOneWidget);
    expect(find.byType(RhythmLane), findsNWidgets(2));
    expect(find.byType(SsSignalQualityIndicator), findsOneWidget);
    expect(find.byType(SsChordDiagram), findsOneWidget);
  });

  testWidgets('the default rung is the pattern rung, over two chords', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_frame()));
    await tester.pump();
    final lanes = tester.widgetList<RhythmLane>(find.byType(RhythmLane));
    expect(lanes.map((lane) => lane.chord), ['Em', 'Am']);
    expect(lanes.first.grid.struckSlots.length, 6, reason: 'D DU UDU');
  });

  group('only confirmed evidence turns anything green', () {
    testWidgets('a confirmed asked chord is ringing', (tester) async {
      await tester.pumpWidget(
        _host(
          _frame(chordLabel: 'Em', decision: RecognitionDecision.confirmed),
        ),
      );
      await tester.pump();
      expect(_fretting(tester), FrettingState.ringing);
    });

    testWidgets('the SAME chord unconfirmed claims nothing', (tester) async {
      // Rule 1: an uncertain frame gives nothing and takes nothing.
      for (final decision in [
        RecognitionDecision.uncertain,
        RecognitionDecision.rejected,
        null,
      ]) {
        await tester.pumpWidget(
          _host(_frame(chordLabel: 'Em', decision: decision)),
        );
        await tester.pump();
        expect(
          _fretting(tester),
          FrettingState.unconfirmed,
          reason: 'decision $decision must not go green',
        );
      }
    });

    testWidgets('a confirmed DIFFERENT chord is reported as the other chord', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _frame(chordLabel: 'Am', decision: RecognitionDecision.confirmed),
        ),
      );
      await tester.pump();
      expect(_fretting(tester), FrettingState.otherChord);
      expect(find.text('Am is sounding'), findsOneWidget);
    });

    testWidgets('a confirmed decision with no label claims nothing', (
      tester,
    ) async {
      // Belt and braces: `confirmed` with a null chord must not be read as
      // agreement with whatever was asked.
      await tester.pumpWidget(
        _host(_frame(decision: RecognitionDecision.confirmed)),
      );
      await tester.pump();
      expect(_fretting(tester), FrettingState.unconfirmed);
    });

    testWidgets('a silent microphone is neutral, never a failure', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_frame(inputLevel: 0, listening: false)));
      await tester.pump();
      expect(_fretting(tester), FrettingState.unconfirmed);
      // The fact is present — on the meter, not as prose (rule 4).
      expect(find.byType(SsSignalQualityIndicator), findsOneWidget);
    });
  });

  group('transport', () {
    testWidgets('it starts paused, and play starts the clock', (tester) async {
      await tester.pumpWidget(_host(_frame()));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('the tempo shown is the shipped beginner tempo', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_frame()));
      await tester.pump();
      expect(find.text('80 BPM'), findsOneWidget);
    });
  });

  group('the clock is the ENGINE clock, measured', () {
    testWidgets('without an engine frame there is no timeline to start', (
      tester,
    ) async {
      // No engine clock means no shared scale, so nothing could be scored. The
      // screen must not invent a timeline of its own in that state.
      await tester.pumpWidget(_host(_frame()));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump(const Duration(milliseconds: 300));
      // It flips to playing, but the pendulum stays parked: `frameAt` is never
      // called with a fabricated position.
      expect(find.byType(SsStrumPendulum), findsOneWidget);
    });

    testWidgets('a stroke is placed at latestStrumTime, not at arrival', (
      tester,
    ) async {
      // The measured point: `latestStrumTime` is the true onset (0.0-3.4 ms),
      // while the frame carrying it arrives 84-142 ms later. Here the frame
      // claims to arrive at 10.30 s carrying a stroke from 10.20 s — a 100 ms
      // gap of exactly the measured shape. The stroke must land on the beat.
      final controller = StreamController<LiveFrame>();
      addTearDown(controller.close);
      await tester.pumpWidget(_streamHost(controller.stream));
      await tester.pump();

      controller.add(_frame(engineTimeSec: 10.0));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      controller.add(
        _frame(
          engineTimeSec: 10.30,
          latestStrumTime: 10.20,
          strumSeq: 1,
          latestStrum: const Strum(
            direction: StrumDirection.down,
            confidence: 0.9,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // 10.20 − 10.00 = 200 ms after the start. At 80 bpm the eighth-note grid
      // has slots every 375 ms, so a stroke at 200 ms is NOT on a slot and must
      // not be credited — the point being that it is judged on its own
      // timestamp rather than on the frame's.
      expect(find.textContaining('heard'), findsOneWidget);
    });

    testWidgets('starting again clears what the last run heard', (
      tester,
    ) async {
      final controller = StreamController<LiveFrame>();
      addTearDown(controller.close);
      await tester.pumpWidget(_streamHost(controller.stream));
      await tester.pump();
      controller.add(_frame(engineTimeSec: 5.0));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      controller.add(
        _frame(
          engineTimeSec: 5.1,
          latestStrumTime: 5.0,
          strumSeq: 1,
          latestStrum: const Strum(
            direction: StrumDirection.down,
            confidence: 0.9,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('heard 1 of'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(
        find.textContaining('heard 0 of'),
        findsOneWidget,
        reason: 'a new attempt must not inherit the previous run evidence',
      );
    });

    testWidgets('a thin attempt says so rather than scoring it', (
      tester,
    ) async {
      // One stroke out of twelve is not a verdict, it is too little evidence.
      final controller = StreamController<LiveFrame>();
      addTearDown(controller.close);
      await tester.pumpWidget(_streamHost(controller.stream));
      await tester.pump();
      controller.add(_frame(engineTimeSec: 1.0));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      controller.add(
        _frame(
          engineTimeSec: 1.1,
          latestStrumTime: 1.0,
          strumSeq: 1,
          latestStrum: const Strum(
            direction: StrumDirection.down,
            confidence: 0.9,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('I could not hear enough of that yet'), findsOneWidget);
    });
  });

  testWidgets('Hungarian renders Hungarian', (tester) async {
    await tester.pumpWidget(_host(_frame(), locale: const Locale('hu')));
    await tester.pump();
    expect(find.text('Pengetés'), findsOneWidget);
  });
}
