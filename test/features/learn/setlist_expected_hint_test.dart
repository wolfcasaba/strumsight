import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/features/songs/model/setlist.dart';
import 'package:music_theory/features/songs/model/song.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

/// Round 146 probe (c): in a combined SETLIST lesson the expected-chord hint
/// must follow the song boundary — song 2's chord becomes the hint when its
/// (tempo-warped) beats begin.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the hint crosses a setlist song boundary', (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    List<StrumDirection?> oneDown() =>
        [StrumDirection.down, null, null, null, null, null, null, null];
    final songC = Song(
        id: 'c', name: 'C song', chords: const ['C'], pattern: oneDown(), bpm: 120);
    final songG = Song(
        id: 'g', name: 'G song', chords: const ['G'], pattern: oneDown(), bpm: 60);
    final combined = const Setlist(id: 's', name: 'set', songIds: ['c', 'g'])
        .combine([songC, songG]);

    await tester.pumpWidget(ProviderScope(
      overrides: [strumEngineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LearnScreen(lesson: combined),
      ),
    ));
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(engine.expectedChordCalls, contains('C'),
        reason: 'pre-roll hints the first song\'s chord');

    // Ref BPM = 120 → 0.5 s/beat; count-in 4 beats (2 s) + song C bar (2 s),
    // then song G's warped beats begin — pump past the boundary.
    await tester.pump(const Duration(milliseconds: 4300));
    expect(engine.expectedChordCalls, contains('G'),
        reason: 'the hint must follow the song boundary');

    // Tidy: stop the ticker before teardown.
    await tester.pumpWidget(const SizedBox());
  });
}
