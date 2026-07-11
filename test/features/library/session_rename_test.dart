import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/library/model/analyzed_session.dart';
import 'package:music_theory/features/library/providers/library_providers.dart';
import 'package:music_theory/features/library/screens/session_detail_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 106 — rename a saved recording. Auto-titles are the chord summary
/// ("C · G · Am"); a personal library needs personal names ("Campfire riff").
AnalyzedSession _session(String id, String title) => AnalyzedSession(
      id: id,
      createdAt: DateTime(2026, 7, 11),
      title: title,
      result: const AnalyzeResult(
        durationSec: 4,
        bpm: 90,
        chords: [TimelineChord(label: 'C', startSec: 0, endSec: 4)],
        strums: [],
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rename updates the session and persists it', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final lib = container.read(libraryProvider.notifier);
    await container.read(libraryProvider.future);
    await lib.add(_session('a', 'C · G'));
    await lib.rename('a', '  Campfire riff  ');

    expect(container.read(libraryProvider).value!.single.title,
        'Campfire riff'); // trimmed
    // Persisted: a FRESH container (same mock prefs) reloads the new name.
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    final reloaded = await fresh.read(libraryProvider.future);
    expect(reloaded.single.title, 'Campfire riff');
  });

  test('an empty or whitespace name is ignored', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final lib = container.read(libraryProvider.notifier);
    await container.read(libraryProvider.future);
    await lib.add(_session('a', 'C · G'));
    await lib.rename('a', '   ');
    expect(container.read(libraryProvider).value!.single.title, 'C · G');
  });

  testWidgets('the detail screen renames via the edit dialog and shows the '
      'fresh title', (tester) async {
    final session = _session('a', 'C · G');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SessionDetailScreen(session: session),
      ),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionDetailScreen)));
    await container.read(libraryProvider.future);
    await container.read(libraryProvider.notifier).add(session);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Campfire riff');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Campfire riff'), findsOneWidget,
        reason: 'the AppBar must show the renamed title immediately');
    expect(container.read(libraryProvider).value!.single.title,
        'Campfire riff');
  });
}
