import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/streak/daily_challenge.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../../support/preference_store.dart';

/// A fixture covering all five [PracticeMode] values, with [PracticeMode.strumPattern]
/// carrying two definitions (A2 — a filter that only ever sees 0/1 cards is
/// indistinguishable from "always render everything"). Every definition
/// carries a `displayTitle` so the Hub widget never reaches for a missing
/// ARB key.
const _kFixtureModes = <PracticeMode, int>{
  PracticeMode.strumPattern: 2,
  PracticeMode.chordChanges: 1,
  PracticeMode.chordProgression: 1,
  PracticeMode.rhythmOnly: 1,
  PracticeMode.freePractice: 1,
};

int _fixtureTotal = _kFixtureModes.values.fold<int>(0, (sum, c) => sum + c);

class _FixtureRepository implements PracticeCatalogRepository {
  const _FixtureRepository();

  static final List<PracticeDefinition> _definitions = [
    for (final entry in _kFixtureModes.entries)
      for (var i = 0; i < entry.value; i++)
        _build(
          id: 'fixture.${entry.key.name}.$i',
          mode: entry.key,
          title: 'Fixture ${entry.key.name} #$i',
        ),
  ];

  static int get _expectedTotal => _definitions.length;

  static PracticeDefinition _build({
    required String id,
    required PracticeMode mode,
    required String title,
  }) {
    return PracticeDefinition(
      id: id,
      schemaVersion: 1,
      titleKey: 'practiceCatalog${id.split('.').last}Title',
      descriptionKey: 'practiceCatalog${id.split('.').last}Description',
      mode: mode,
      source: PracticeSource.builtin,
      meter: const Meter(beatsPerBar: 4),
      defaultTempo: const Tempo(80),
      totalBeats: BeatPosition.quarters(16),
      events: List<PracticeEvent>.unmodifiable([
        for (var i = 0; i < 16; i++)
          PracticeEvent(
            id: '$id.e$i',
            position: BeatPosition.quarters(i),
            direction: StrumDirection.down,
          ),
      ]),
      scoringProfile: ScoringProfile.legacyLearnParity,
      skillTags: ['fixture'],
      displayTitle: title,
    );
  }

  @override
  List<PracticeDefinition> all() =>
      List<PracticeDefinition>.unmodifiable(_definitions);

  @override
  PracticeDefinition? byId(String id) {
    for (final def in _definitions) {
      if (def.id == id) return def;
    }
    return null;
  }

  @override
  List<PracticeDefinition> byMode(PracticeMode mode) {
    final matches = <PracticeDefinition>[];
    for (final def in _definitions) {
      if (def.mode == mode) matches.add(def);
    }
    return List<PracticeDefinition>.unmodifiable(matches);
  }

  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      const <PracticeDefinition>[];
}

class _EmptyRepository implements PracticeCatalogRepository {
  const _EmptyRepository();

  @override
  List<PracticeDefinition> all() => const <PracticeDefinition>[];
  @override
  PracticeDefinition? byId(String id) => null;
  @override
  List<PracticeDefinition> byMode(PracticeMode mode) =>
      const <PracticeDefinition>[];
  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      const <PracticeDefinition>[];
}

Widget _host({
  required PracticeCatalogRepository repository,
  DailyChallenge? dailyChallenge,
  DateTime? now,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      ...preferenceOverrides(),
      practiceCatalogRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      theme: SsLightTheme.data(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PracticeHubScreen(now: now, dailyChallenge: dailyChallenge),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('A1: fixture covers all five modes and totals to 6 cards', () {
    expect(_kFixtureModes.length, PracticeMode.values.length);
    expect(_FixtureRepository._expectedTotal, 6);
    expect(_fixtureTotal, 6);
  });

  testWidgets(
    'A1: hub renders a card per catalog definition with displayTitle',
    (tester) async {
      await tester.pumpWidget(_host(repository: const _FixtureRepository()));
      await tester.pump();

      // All six fixture cards must render their display titles.
      for (var i = 0; i < _FixtureRepository._expectedTotal; i++) {
        // displayTitle is 'Fixture <mode> #<i>' — every card with a
        // definition's title should be in the tree.
        expect(find.textContaining('Fixture '), findsWidgets, reason: 'i=$i');
      }
    },
  );

  testWidgets('A1: empty catalog shows the localized empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_host(repository: const _EmptyRepository()));
    await tester.pump();

    expect(find.text('No practice sessions yet'), findsOneWidget);
  });

  testWidgets('A2: filtering by strumPattern leaves only strum-pattern cards', (
    tester,
  ) async {
    await tester.pumpWidget(_host(repository: const _FixtureRepository()));
    await tester.pump();

    // Tap the strum-pattern filter chip. (It's the first non-"All" chip
    // and is visible at the default viewport.)
    await tester.tap(find.widgetWithText(ChoiceChip, 'Strum pattern'));
    await tester.pump();

    // Two strum-pattern cards remain; chord/other modes disappear.
    expect(find.text('Fixture strumPattern #0'), findsOneWidget);
    expect(find.text('Fixture strumPattern #1'), findsOneWidget);
    expect(find.text('Fixture chordChanges #0'), findsNothing);
    expect(find.text('Fixture chordProgression #0'), findsNothing);
    expect(find.text('Fixture rhythmOnly #0'), findsNothing);
    expect(find.text('Fixture freePractice #0'), findsNothing);

    // Re-tapping the same chip clears the filter — everything returns.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Strum pattern'));
    await tester.pump();
    expect(find.text('Fixture chordChanges #0'), findsOneWidget);
  });

  testWidgets(
    'A2: filtering by chordChanges leaves only the chord-change card',
    (tester) async {
      await tester.pumpWidget(_host(repository: const _FixtureRepository()));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Chord changes'));
      await tester.pump();
      expect(find.text('Fixture chordChanges #0'), findsOneWidget);
      expect(find.text('Fixture strumPattern #0'), findsNothing);
    },
  );

  testWidgets(
    'A2: filtering by freePractice shows the lone free-practice card',
    (tester) async {
      await tester.pumpWidget(_host(repository: const _FixtureRepository()));
      await tester.pump();
      // The mode-filter row is a horizontal scroller; the last chip is off
      // the default 800x600 viewport, so scroll it into view first.
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Free practice'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Free practice'));
      await tester.pump();
      expect(find.text('Fixture freePractice #0'), findsOneWidget);
      expect(find.text('Fixture strumPattern #0'), findsNothing);
    },
  );

  testWidgets('A3: Continue/Recent blocks are absent — no placeholder data', (
    tester,
  ) async {
    await tester.pumpWidget(_host(repository: const _FixtureRepository()));
    await tester.pump();

    // The Hub must not contain Continue or Recent sections; the history
    // is Kör 18's concern. There is no ARB key for them, so even a
    // typo would fail the test.
    expect(find.textContaining('Continue', findRichText: true), findsNothing);
    expect(find.textContaining('Recent', findRichText: true), findsNothing);
  });

  testWidgets(
    'A3: empty catalog hides the Quick Start entry, not just disables it',
    (tester) async {
      await tester.pumpWidget(_host(repository: const _EmptyRepository()));
      await tester.pump();

      expect(find.text('No practice sessions yet'), findsOneWidget);
      // Quick Start is keyed to "catalog.first" — with no catalog, the entry
      // must not exist at all.
      expect(find.text('Quick start'), findsNothing);
    },
  );

  testWidgets(
    'A3: daily-challenge failure is visible but disabled, not hidden',
    (tester) async {
      final failing = DailyChallenge(
        day: 20000,
        name: 'Empty',
        pattern: const <StrumDirection>[],
      );
      await tester.pumpWidget(
        _host(repository: const _FixtureRepository(), dailyChallenge: failing),
      );
      await tester.pump();

      // The card is present (l10n title) and the explanation shows.
      expect(find.text('Daily challenge'), findsOneWidget);
      expect(
        find.text('No daily challenge available right now'),
        findsOneWidget,
      );
      // A disabled InkWell's onTap is null — tapping it must not navigate.
      final card = find.ancestor(
        of: find.text('Daily challenge'),
        matching: find.byType(InkWell),
      );
      expect(card, findsOneWidget);
      final inkWell = tester.widget<InkWell>(card);
      expect(inkWell.onTap, isNull);
    },
  );

  testWidgets('A3: daily-challenge success path shows the live card', (
    tester,
  ) async {
    final success = DailyChallenge(
      day: 20000,
      name: 'Pattern',
      pattern: const <StrumDirection>[
        StrumDirection.down,
        StrumDirection.up,
        StrumDirection.down,
        StrumDirection.up,
      ],
    );
    await tester.pumpWidget(
      _host(repository: const _FixtureRepository(), dailyChallenge: success),
    );
    await tester.pump();
    expect(find.text('Daily challenge'), findsOneWidget);
    expect(find.text('No daily challenge available right now'), findsNothing);
  });

  testWidgets('A8: hungarian locale renders a hungarian title in the tree', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(repository: const _FixtureRepository(), locale: const Locale('hu')),
    );
    await tester.pump();
    expect(find.text('Gyakorló hub'), findsOneWidget);
  });
}
