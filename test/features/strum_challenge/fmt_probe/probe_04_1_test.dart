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
  group('the daily best', () {
    testWidgets(
      'persists across a second pump of the same store, and resets '
      'on a new day',
      (tester) async {
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
        expect(
          store.values.containsKey(StorageKeys.strumChallengeBest),
          isTrue,
        );

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
      },
    );
  });
}
