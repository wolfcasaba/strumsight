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
      'a lower second run keeps the best and says nothing about a '
      'record',
      (tester) async {
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
      },
    );
  });
}
