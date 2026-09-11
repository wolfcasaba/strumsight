// The rhythm practice screen against a faked recogniser.
//
// The point of these cells is the seam between what the microphone says and what
// the screen is allowed to claim (design §2 rules 1-4): green only on a confirmed
// decision FOR THE ASKED CHORD, and nothing negative without confirmation.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
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
}) => LiveFrame(
  current: chordLabel == null ? null : Chord(chordLabel),
  next: null,
  latestStrum: null,
  bar: const [],
  bpm: 0,
  inputLevel: inputLevel,
  tuningHz: 440,
  listening: listening,
  chordDecision: decision,
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

  testWidgets('Hungarian renders Hungarian', (tester) async {
    await tester.pumpWidget(_host(_frame(), locale: const Locale('hu')));
    await tester.pump();
    expect(find.text('Pengetés'), findsOneWidget);
  });
}
