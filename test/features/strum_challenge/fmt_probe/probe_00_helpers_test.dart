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

void main() {}
