import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/screens/chord_library_screen.dart';
import 'package:music_theory/features/learn/audio/chord_audio.dart';
import 'package:music_theory/features/learn/providers/backing_provider.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 90 — tap a chord in the library to HEAR it (the reference tool
/// teaches sound, not just shape). The pad player is injected so tests can
/// record what was asked to play.
class _RecordingBacking extends Backing {
  final List<String> played = [];

  @override
  Future<void> playChord(String label) async => played.add(label);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping a chord diagram plays that chord', (tester) async {
    final backing = _RecordingBacking();
    await tester.pumpWidget(ProviderScope(
      overrides: [backingProvider.overrideWithValue(backing)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChordLibraryScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('C'));
    await tester.pumpAndSettle();

    expect(backing.played, ['C']);
  });

  testWidgets('each tile plays its OWN chord', (tester) async {
    final backing = _RecordingBacking();
    await tester.pumpWidget(ProviderScope(
      overrides: [backingProvider.overrideWithValue(backing)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChordLibraryScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Em'));
    await tester.pumpAndSettle();

    expect(backing.played, ['Em']);
  });
}
