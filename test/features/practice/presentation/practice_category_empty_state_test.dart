// R34 (audit MI-B) — a goal chip that resolves to nothing says WHICH
// absence it found.
//
// Measured before this round: `PracticeCategory.scales` matches no built-in
// definition (`practice_category_test.dart` pins that emptiness as a fact
// about the shipped catalog), so the Practice Area Hub's `scales` chip
// always landed on the catalog listing with an empty list — and that listing
// rendered `practiceHubEmptyCatalogSubtitle` ("Check back later"), the
// WHOLE-catalog empty copy. The learner was told the catalog was empty while
// nine other exercises sat one tap away.
//
// The chip itself is deliberately NOT hidden here: the Practice Area Hub's
// chip row is inside a pixel-pinned golden
// (`e13_r17_practice_area_hub_compact*.png`) that cannot be re-recorded on
// this box, and tagging a strumming exercise `scales` would invent catalog
// content. The honest, pixel-neutral fix is the copy on the destination.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/practice_category.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/streak/daily_challenge.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/preference_store.dart';

const _testConfig = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

/// The REAL built-in catalog — `practiceCatalogRepositoryProvider` is
/// deliberately not overridden, so the emptiness these cells describe is the
/// shipped catalog's own, not a fixture's.
Widget _host(PracticeCategory? category) => ProviderScope(
  overrides: [
    ...preferenceOverrides(),
    appConfigProvider.overrideWithValue(_testConfig),
  ],
  child: MaterialApp(
    theme: SsLightTheme.data(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: PracticeHubScreen(
      now: DateTime.utc(2026, 9, 8),
      dailyChallenge: const DailyChallenge(
        day: 20705,
        name: 'Audit',
        pattern: <StrumDirection>[],
      ),
      category: category,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('the scales chip lands on copy that names THIS goal as empty, '
      'not the whole catalog', (tester) async {
    await tester.pumpWidget(_host(PracticeCategory.scales));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('practice-catalog-empty')), findsOneWidget);
    expect(find.text(l10n.practiceCatalogCategoryEmpty), findsOneWidget);
    expect(
      find.text(l10n.practiceHubEmptyCatalogSubtitle),
      findsNothing,
      reason:
          'the catalog is NOT empty — nine other exercises are one chip '
          'away, and saying otherwise is the measured MI-B defect',
    );
  });

  testWidgets('a goal that DOES have exercises renders them, not the empty '
      'copy', (tester) async {
    await tester.pumpWidget(_host(PracticeCategory.chords));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('practice-catalog-empty')), findsNothing);
    expect(find.text(l10n.practiceCatalogCategoryEmpty), findsNothing);
  });
}
