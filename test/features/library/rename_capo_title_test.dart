import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/library/model/analyzed_session.dart';
import 'package:music_theory/features/library/providers/library_providers.dart';
import 'package:music_theory/features/library/screens/library_screen.dart';
import 'package:music_theory/features/library/screens/session_detail_screen.dart';
import 'package:music_theory/features/settings/providers/capo_provider.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 114 — a RENAMED title must never go through the capo transposer.
/// Auto-titles are chord summaries ("C · G"), so showing them transposed under
/// a capo is correct. But r106 user titles took the same path: "Campfire
/// riff" at capo 2 rendered as "A#ampfire riff" (the leading letter parsed as
/// a chord root) — and inconsistently, Share/Practice used the raw name.
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

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('withTitle marks the session as custom-titled and it survives JSON',
      () {
    final auto = _session('a', 'C · G');
    expect(auto.customTitle, isFalse);
    final named = auto.withTitle('Campfire riff');
    expect(named.customTitle, isTrue);

    final roundTripped = AnalyzedSession.fromJson(named.toJson());
    expect(roundTripped.customTitle, isTrue);
    // Legacy records (saved before the flag existed) stay auto-titled.
    final legacyJson = auto.toJson()..remove('customTitle');
    expect(AnalyzedSession.fromJson(legacyJson).customTitle, isFalse);
  });

  testWidgets('a renamed title renders VERBATIM under a capo (detail screen)',
      (tester) async {
    final session = _session('a', 'C · G');
    await tester.pumpWidget(
        ProviderScope(child: _app(SessionDetailScreen(session: session))));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionDetailScreen)));
    await container.read(libraryProvider.future);
    await container.read(libraryProvider.notifier).add(session);
    await container.read(libraryProvider.notifier).rename('a', 'Campfire riff');
    await container.read(capoProvider.notifier).set(2);
    await tester.pumpAndSettle();

    expect(find.text('Campfire riff'), findsOneWidget,
        reason: 'a personal name is not a chord summary — never transpose it');
    expect(find.text('A#ampfire riff'), findsNothing);
  });

  testWidgets('an auto chord-summary title still transposes under a capo',
      (tester) async {
    final session = _session('a', 'C · G');
    await tester.pumpWidget(
        ProviderScope(child: _app(SessionDetailScreen(session: session))));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionDetailScreen)));
    await container.read(libraryProvider.future);
    await container.read(libraryProvider.notifier).add(session);
    await container.read(capoProvider.notifier).set(2);
    await tester.pumpAndSettle();

    expect(find.text('A# · F'), findsOneWidget,
        reason: 'capo 2: the played SHAPE for C·G is A#·F — keep transposing');
  });

  testWidgets('the library list also shows a renamed title verbatim',
      (tester) async {
    // The library screen is a tab body — it brings no Material of its own.
    await tester.pumpWidget(ProviderScope(
        child: _app(const Scaffold(body: LibraryScreen()))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
    await container.read(libraryProvider.future);
    await container.read(libraryProvider.notifier).add(_session('a', 'C · G'));
    await container.read(libraryProvider.notifier).rename('a', 'Campfire riff');
    await container.read(capoProvider.notifier).set(2);
    await tester.pumpAndSettle();

    expect(find.text('Campfire riff'), findsOneWidget);
    expect(find.text('A#ampfire riff'), findsNothing);
  });
}
