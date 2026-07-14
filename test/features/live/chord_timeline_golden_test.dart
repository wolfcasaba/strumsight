// Golden snapshots of the Live chord-timeline (r185) at a full 6-card buffer,
// on both a normal (412 px) and a narrow (320 px) phone — the exact case the
// happy-path widget tests skip and the review flagged for hero readability.
//
// Regenerate: ~/flutter/bin/flutter test --update-goldens \
//   test/features/live/chord_timeline_golden_test.dart
// (Brand fonts don't load in the test host, so labels render in a fallback
// face — layout, sizing, colours, glass and arrows are all faithful.)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/core/theme/app_theme.dart';
import 'package:music_theory/features/live/model/chord.dart';
import 'package:music_theory/features/live/model/chord_event.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/live/widgets/chord_timeline.dart';
import 'package:music_theory/l10n/app_localizations.dart';

ChordEvent _e(String label, StrumDirection dir, double conf, int seq) =>
    ChordEvent(
      chord: Chord(label),
      direction: dir,
      confidence: conf,
      seq: seq,
      timeSec: seq.toDouble(),
    );

/// A full cap-6 buffer: 5 receding history cards + the Em hero.
final _fullBuffer = <ChordEvent>[
  _e('Am', StrumDirection.down, 0.72, 0),
  _e('F', StrumDirection.up, 0.85, 1),
  _e('C', StrumDirection.down, 0.90, 2),
  _e('G', StrumDirection.up, 0.61, 3),
  _e('Dm', StrumDirection.down, 0.80, 4),
  _e('Em', StrumDirection.up, 0.77, 5),
];

Future<void> _pumpAt(WidgetTester tester, double width) async {
  // ~ the height the Live Expanded actually gives the timeline after the status
  // bar / beat counter / action bar claim their space — so the hero's
  // height-bounded FittedBox scale is representative, not over-inflated.
  await tester.binding.setSurfaceSize(Size(width, 340));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ChordTimeline(events: _fullBuffer, capo: 0),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Golden pixels differ across host CPUs/font stacks (this box is ARM, CI is
// x86), so this is a LOCAL visual-regression tool, opt-in via GOLDENS=1 — it
// never runs (or fails) in the CI `flutter test` sweep.
final _skip = Platform.environment['GOLDENS'] != '1';

void main() {
  testWidgets('chord timeline — full buffer, 412 px', (tester) async {
    await _pumpAt(tester, 412);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chord_timeline_412.png'),
    );
  }, skip: _skip);

  testWidgets('chord timeline — full buffer, narrow 320 px', (tester) async {
    await _pumpAt(tester, 320);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chord_timeline_320.png'),
    );
  }, skip: _skip);
}
