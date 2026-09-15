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
  testWidgets(
    'the pattern is the shipped D DU UDU at 80 bpm, and the minute '
    'is 20 whole bars',
    (tester) async {
      await tester.pumpWidget(_host(Stream<LiveFrame>.value(_frame())));
      await tester.pump();
      final lane = tester.widget<RhythmLane>(find.byType(RhythmLane));
      expect(lane.grid.struckSlots.length, 6, reason: 'D DU UDU');
      expect(lane.chord, isNull, reason: 'no chord is asked for');
      expect(strumChallengeBars(), 20);
      expect(strumChallengeBpm, 80);
    },
  );
}
