import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/songs/screens/song_builder_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 103 — tap-tempo in the Song Builder (same tool the metronome has):
/// writing a song from a track you're listening to means tapping its tempo,
/// not guessing a slider position.
Future<void> _pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SongBuilderScreen(),
      ),
    ));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping the tempo button sets the BPM from the tap rate',
      (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    // Bring the tempo section into view (multiple scrollables on screen, so
    // drag the outer list directly instead of scrollUntilVisible).
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pump();
    final tap = find.byIcon(Icons.touch_app_outlined);
    expect(tap, findsOneWidget);

    // Test taps land microseconds apart → a huge raw BPM, clamped to the
    // slider's max (180). Deterministic without controlling the wall clock.
    await tester.tap(tap);
    await tester.tap(tap);
    await tester.tap(tap);
    await tester.pump();

    expect(find.text('180 BPM'), findsOneWidget);
  });
}
