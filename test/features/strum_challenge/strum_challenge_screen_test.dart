// The 60-second strum challenge against a faked recogniser.
//
// The cells follow `test/features/curriculum/rhythm_practice_screen_test.dart`:
// the screen runs on the ENGINE clock, so every stroke is placed by arithmetic
// on the grid's own onsets (`RhythmGrid.onsetUs`) after the one-bar count-in,
// and the frame carrying it may arrive whenever it likes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/curriculum/public.dart' show RhythmLane;
import 'package:strumsight/features/live/public.dart';
import 'package:strumsight/features/streak/public.dart';
import 'package:strumsight/features/strum_challenge/presentation/screens/strum_challenge_screen.dart';
import 'package:strumsight/features/strum_challenge/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../core/storage/in_memory_key_value_store.dart';

LiveFrame _frame({
  double inputLevel = 0.5,
  bool listening = true,
  double engineTimeSec = -1,
  double latestStrumTime = -1,
  int strumSeq = 0,
  Strum? latestStrum,
}) => LiveFrame(
  current: null,
  next: null,
  latestStrum: latestStrum,
  bar: const [],
  bpm: 0,
  inputLevel: inputLevel,
  tuningHz: 440,
  listening: listening,
  engineTimeSec: engineTimeSec,
  latestStrumTime: latestStrumTime,
  strumSeq: strumSeq,
);

/// A host driven by a controller, so a test can deliver frames over time the
/// way the engine does. [store] is shared between pumps to prove persistence;
/// [clock] is the challenge's own clock, so a test can turn the calendar.
Widget _host(
  Stream<LiveFrame> frames, {
  InMemoryKeyValueStore? store,
  DateTime Function()? clock,
}) => ProviderScope(
  overrides: [
    liveFrameProvider.overrideWith((ref) => frames),
    // The screen reads the persisted calibration, the metronome mute, the
    // streak and today's best, so the store has to exist. Empty = fresh day.
    keyValueStoreProvider.overrideWithValue(store ?? InMemoryKeyValueStore()),
    if (clock != null) strumChallengeClockProvider.overrideWithValue(clock),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: SsDarkTheme.data(),
    home: const StrumChallengeScreen(),
  ),
);

/// The engine clock reading the run is started at.
const double _startSec = 1.0;

/// 80 bpm: one beat is 0.75 s, the count-in is one bar of four = 3.0 s.
final double _beatSec = 60 / strumChallengeBpm;
final double _countInSec = _beatSec * strumChallengeGrid.beatsPerBar;

Future<void> _startRun(
  WidgetTester tester,
  StreamController<LiveFrame> controller,
) async {
  controller.add(_frame(engineTimeSec: _startSec));
  await tester.pump();
  await tester.tap(find.text('Start'));
  await tester.pump();
}

/// Feeds [bars] bars of perfectly timed strokes, each travelling the way the
/// grid asks, placed by the grid's OWN onset arithmetic after the count-in.
Future<int> _playBars(
  WidgetTester tester,
  StreamController<LiveFrame> controller,
  int bars,
) async {
  var seq = 0;
  for (var bar = 0; bar < bars; bar++) {
    for (final slot in strumChallengeGrid.struckSlots) {
      final onsetUs = strumChallengeGrid.onsetUs(
        bar: bar,
        slotIndex: slot.index,
        bpm: strumChallengeBpm,
      );
      final atSec = _startSec + _countInSec + onsetUs / 1e6;
      seq++;
      controller.add(
        _frame(
          engineTimeSec: atSec,
          latestStrumTime: atSec,
          strumSeq: seq,
          latestStrum: Strum(direction: slot.direction, confidence: 0.9),
        ),
      );
      await tester.pump();
    }
  }
  return seq;
}

/// Past the end of the minute, and a few ticks to notice, grade and record.
Future<void> _finishRun(
  WidgetTester tester,
  StreamController<LiveFrame> controller,
) async {
  controller.add(
    _frame(engineTimeSec: _startSec + _countInSec + strumChallengeSeconds + 1),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 32));
  // The best is recorded through an awaited write; two more frames let the
  // "new best" answer land.
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('it renders the motion, the notation, the level meter and the '
      'empty daily best', (tester) async {
    await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
    await tester.pump();
    expect(find.byType(SsStrumPendulum), findsOneWidget);
    expect(find.byType(RhythmLane), findsOneWidget);
    expect(find.byType(SsSignalQualityIndicator), findsOneWidget);
    expect(find.text('60-second strum challenge'), findsOneWidget);
    expect(find.text('No attempt yet today'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('the pattern is the shipped D DU UDU at 80 bpm, and the minute '
      'is 20 whole bars', (tester) async {
    await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
    await tester.pump();
    final lane = tester.widget<RhythmLane>(find.byType(RhythmLane));
    expect(lane.grid.struckSlots.length, 6, reason: 'D DU UDU');
    expect(lane.chord, isNull, reason: 'no chord is asked for');
    expect(strumChallengeBars(), 20);
    expect(strumChallengeBpm, 80);
  });

  group('the run: count-in, then scoring', () {
    testWidgets(
      'correctly timed down/up strums score credited > 0 and the summary '
      'shows it',
      (tester) async {
        final controller = StreamController<LiveFrame>();
        addTearDown(controller.close);
        await tester.pumpWidget(_host(controller.stream));
        await tester.pump();
        await _startRun(tester, controller);
        await tester.pump(const Duration(milliseconds: 16));

        // Counting in first: the learner must know the minute has not begun.
        expect(find.byKey(strumChallengeCountInKey), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(strumChallengeCountInKey)).data,
          'Get ready — 1',
        );
        expect(find.byKey(strumChallengeScoreKey), findsNothing);

        // Twelve clean bars of the twenty: 72 strokes, coverage 0.6.
        final played = await _playBars(tester, controller, 12);
        expect(played, 72);

        // Inside the minute: the count-in is over, the clock and the live
        // score are up, and the score IS the credited count.
        expect(find.byKey(strumChallengeCountInKey), findsNothing);
        expect(find.byKey(strumChallengeSecondsLeftKey), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(strumChallengeScoreKey)).data,
          'Score 72',
        );

        await _finishRun(tester, controller);

        expect(find.text('Score 72 · 12 full patterns'), findsOneWidget);
        expect(find.text('Direction accuracy 100%'), findsOneWidget);
        expect(find.text('I heard 72 of 120 strums'), findsOneWidget);
        expect(find.text('New best today!'), findsOneWidget);
        expect(find.text("Today's best: 72"), findsOneWidget);
        // Uncalibrated device: no timing figure, and it says so.
        expect(
          find.text('Timing is not scored on this device yet'),
          findsOneWidget,
        );
        // The transport offers another go, not a restart of the same run.
        expect(find.text('Try again'), findsOneWidget);
        expect(find.byKey(strumChallengeScoreKey), findsNothing);
      },
    );

    testWidgets('a stroke played DURING the count-in is not scored', (
      tester,
    ) async {
      final controller = StreamController<LiveFrame>();
      addTearDown(controller.close);
      await tester.pumpWidget(_host(controller.stream));
      await tester.pump();
      await _startRun(tester, controller);
      // start + 1.0 s: well inside the 3.0 s count-in.
      controller.add(
        _frame(
          engineTimeSec: _startSec + 1.1,
          latestStrumTime: _startSec + 1.0,
          strumSeq: 1,
          latestStrum: const Strum(
            direction: StrumDirection.down,
            confidence: 0.9,
          ),
        ),
      );
      await tester.pump();
      await _finishRun(tester, controller);
      expect(find.textContaining('full patterns'), findsNothing);
      expect(find.textContaining("I couldn't hear enough"), findsOneWidget);
    });

    testWidgets('too few strokes: "could not hear enough", no score, and '
        'nothing recorded as a best', (tester) async {
      final store = InMemoryKeyValueStore();
      final controller = StreamController<LiveFrame>();
      addTearDown(controller.close);
      await tester.pumpWidget(_host(controller.stream, store: store));
      await tester.pump();
      await _startRun(tester, controller);

      // Two clean bars of twenty: 12 strokes, coverage 0.1 — too thin to
      // claim anything, and NOT a low score.
      await _playBars(tester, controller, 2);
      await _finishRun(tester, controller);

      expect(
        find.text(
          "I couldn't hear enough. Move closer to the mic or play a little "
          'louder, then try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Score'), findsNothing);
      expect(find.textContaining('full patterns'), findsNothing);
      expect(find.text('New best today!'), findsNothing);
      expect(find.text('No attempt yet today'), findsOneWidget);
      expect(
        store.values.containsKey(StorageKeys.strumChallengeBest),
        isFalse,
        reason:
            'a run below the coverage floor claims nothing, so it writes '
            'nothing',
      );
    });
  });

  group('the daily best', () {
    testWidgets('persists across a second pump of the same store, and resets '
        'on a new day', (tester) async {
      final store = InMemoryKeyValueStore();
      final day = DateTime(2026, 9, 15, 10);
      final first = StreamController<LiveFrame>();
      addTearDown(first.close);
      await tester.pumpWidget(
        _host(first.stream, store: store, clock: () => day),
      );
      await tester.pump();
      await _startRun(tester, first);
      await _playBars(tester, first, 12);
      await _finishRun(tester, first);
      expect(find.text("Today's best: 72"), findsOneWidget);
      expect(store.values.containsKey(StorageKeys.strumChallengeBest), isTrue);

      // A brand-new tree over the SAME store, later the same day.
      final second = StreamController<LiveFrame>();
      addTearDown(second.close);
      await tester.pumpWidget(
        _host(
          second.stream,
          store: store,
          clock: () => day.add(const Duration(hours: 5)),
        ),
      );
      await tester.pump();
      expect(find.text("Today's best: 72"), findsOneWidget);
      expect(find.text('No attempt yet today'), findsNothing);

      // The next morning: a new day, a fresh best to set.
      final third = StreamController<LiveFrame>();
      addTearDown(third.close);
      await tester.pumpWidget(
        _host(
          third.stream,
          store: store,
          clock: () => day.add(const Duration(days: 1)),
        ),
      );
      await tester.pump();
      expect(find.text('No attempt yet today'), findsOneWidget);
      expect(find.text("Today's best: 72"), findsNothing);
    });

    testWidgets('a lower second run keeps the best and says nothing about a '
        'record', (tester) async {
      final store = InMemoryKeyValueStore();
      final day = DateTime(2026, 9, 15, 10);
      final controller = StreamController<LiveFrame>();
      addTearDown(controller.close);
      await tester.pumpWidget(
        _host(controller.stream, store: store, clock: () => day),
      );
      await tester.pump();
      await _startRun(tester, controller);
      await _playBars(tester, controller, 12);
      await _finishRun(tester, controller);
      expect(find.text("Today's best: 72"), findsOneWidget);

      // Try again — the second run is anchored to the engine clock's NEW
      // reading, so the same arithmetic works from a fresh start.
      final second = StreamController<LiveFrame>();
      addTearDown(second.close);
      await tester.pumpWidget(
        _host(second.stream, store: store, clock: () => day),
      );
      await tester.pump();
      await _startRun(tester, second);
      await _playBars(tester, second, 11);
      await _finishRun(tester, second);

      expect(find.text('Score 66 · 11 full patterns'), findsOneWidget);
      expect(find.text('New best today!'), findsNothing);
      expect(find.text("Today's best: 72"), findsOneWidget);
    });
  });

  group('the streak', () {
    testWidgets('is credited once when anything was heard', (tester) async {
      final store = InMemoryKeyValueStore();
      final controller = StreamController<LiveFrame>();
      addTearDown(controller.close);
      await tester.pumpWidget(_host(controller.stream, store: store));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StrumChallengeScreen)),
      );
      expect(container.read(streakProvider).current, 0);

      await _startRun(tester, controller);
      await _playBars(tester, controller, 12);
      await _finishRun(tester, controller);

      expect(container.read(streakProvider).current, 1);
      expect(container.read(streakProvider).totalDays, 1);
      // And a rebuild must not credit it again.
      await tester.pump(const Duration(milliseconds: 32));
      expect(container.read(streakProvider).current, 1);
      expect(container.read(streakProvider).totalDays, 1);
    });

    testWidgets('is NOT credited by a minute in which nothing was heard', (
      tester,
    ) async {
      final controller = StreamController<LiveFrame>();
      addTearDown(controller.close);
      await tester.pumpWidget(_host(controller.stream));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StrumChallengeScreen)),
      );
      await _startRun(tester, controller);
      await _finishRun(tester, controller);
      expect(container.read(streakProvider).current, 0);
    });
  });

  group('transport', () {
    testWidgets('stopping mid-run abandons it: no score, nothing recorded', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      final controller = StreamController<LiveFrame>();
      addTearDown(controller.close);
      await tester.pumpWidget(_host(controller.stream, store: store));
      await tester.pump();
      await _startRun(tester, controller);
      await _playBars(tester, controller, 12);
      expect(find.text('Stop'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pump();

      expect(find.text('Start'), findsOneWidget);
      expect(find.textContaining('full patterns'), findsNothing);
      expect(find.text('No attempt yet today'), findsOneWidget);
      expect(store.values.containsKey(StorageKeys.strumChallengeBest), isFalse);
    });

    testWidgets('the transport wraps instead of overflowing at 2.0 text scale '
        'on a compact phone (hu)', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveFrameProvider.overrideWith(
              (ref) => Stream<LiveFrame>.value(_frame()),
            ),
            keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          ],
          child: MaterialApp(
            locale: const Locale('hu'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: SsDarkTheme.data(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: const StrumChallengeScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Indítás'), findsOneWidget);
      expect(find.text('Kész'), findsOneWidget);
    });
  });
}
