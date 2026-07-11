import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/providers/favorite_chords_provider.dart';
import 'package:music_theory/features/chords/screens/chord_library_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 108 — favourite chords: long-press a diagram in the library to pin
/// it into a FAVORITES group at the top (persisted). The chords you're
/// drilling this month shouldn't need scrolling past the whole catalogue.
Future<void> _pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChordLibraryScreen(),
      ),
    ));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('toggle adds and removes, and persists across containers', () async {
    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    await c1.read(favoriteChordsProvider.notifier).toggle('Am');
    await c1.read(favoriteChordsProvider.notifier).toggle('C');
    await c1.read(favoriteChordsProvider.notifier).toggle('Am');
    expect(c1.read(favoriteChordsProvider), {'C'});

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(favoriteChordsProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c2.read(favoriteChordsProvider), {'C'});
  });

  testWidgets('long-pressing a chord pins it into a Favorites group on top',
      (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('FAVORITES'), findsNothing);

    await tester.longPress(find.text('C'));
    await tester.pumpAndSettle();

    expect(find.text('FAVORITES'), findsOneWidget);
    // Pinned copy + the original in the Major group.
    expect(find.text('C'), findsNWidgets(2));

    // Long-press the pinned copy: unpin, the group disappears.
    await tester.longPress(find.text('C').first);
    await tester.pumpAndSettle();
    expect(find.text('FAVORITES'), findsNothing);
    expect(find.text('C'), findsOneWidget);
  });
}
