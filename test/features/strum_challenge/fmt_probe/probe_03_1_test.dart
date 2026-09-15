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

void main() {
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
  });
}
