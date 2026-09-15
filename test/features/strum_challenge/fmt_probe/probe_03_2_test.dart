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
  });
}
