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
      'too few strokes: "could not hear enough", no score, and '
      'nothing recorded as a best',
      (tester) async {
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
      },
    );
  });
}
