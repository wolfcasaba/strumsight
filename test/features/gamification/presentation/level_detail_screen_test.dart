// E15-R08 — dedicated LevelDetailScreen coverage. §0.0.A/R3: the screen is
// MEASURED `unreachable` (no route, no lib/ construction site — see
// docs/ui/retirement-plan.md §3.4) yet stays in this round's scope, same
// decision class as the E15-R07 batch (ADR 0471 D5: unreachable is not
// retire). §0.0.A/R5: the A3 cells below use the exact 360x640 phone
// viewport (not the flutter_test 800x600 default) so a real overflow is
// actually measured, not masked (L558).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/domain/levels/level_curve.dart';
import 'package:strumsight/features/gamification/domain/levels/level_definition.dart';
import 'package:strumsight/features/gamification/domain/profile/gamification_profile.dart';
import 'package:strumsight/features/gamification/domain/rewards/experience_points.dart';
import 'package:strumsight/features/gamification/presentation/screens/level_detail_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

AppLocalizations _english() => AppLocalizationsEn();

LevelCurve _curve() => LevelCurve(<LevelDefinition>[
  LevelDefinition(
    number: 1,
    levelThreshold: 0,
    titleKey: 'gamification.level.beginner',
  ),
  LevelDefinition(
    number: 2,
    levelThreshold: 100,
    titleKey: 'gamification.level.explorer',
  ),
  LevelDefinition(
    number: 3,
    levelThreshold: 250,
    titleKey: 'gamification.level.consistent',
  ),
]);

GamificationProfile _profile({int totalXp = 60}) => GamificationProfile(
  schemaVersion: gamificationProfileSchemaVersion,
  totalXp: totalXp,
  progress: _curve().progressForTotalXp(totalXp),
);

ExperiencePoints _xp() => ExperiencePoints(
  baseXp: 10,
  durationXp: 8,
  qualityXp: 6,
  improvementXp: 4,
  diversityXp: 2,
);

List<LevelDetailXpComponent> _components(AppLocalizations l10n) =>
    buildR06XpComponents(l10n: l10n, xp: _xp());

Future<void> _pump(
  WidgetTester tester, {
  int totalXp = 60,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  final l10n = locale.languageCode == 'hu'
      ? await AppLocalizations.delegate.load(const Locale('hu'))
      : _english();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: LevelDetailScreen(
          profile: _profile(totalXp: totalXp),
          latestSessionXp: _xp(),
          components: _components(l10n),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 — the screen imports the design system for its component rows', () {
    testWidgets('all five R06 Xp components render inside SsCard rows', (
      tester,
    ) async {
      // A tall viewport so the whole ListView content mounts at once — a
      // ListView(children:) still lazily builds only the elements within
      // its viewport + cache extent, so a short/default surface would
      // silently under-count the below-the-fold rows without this.
      await tester.binding.setSurfaceSize(const Size(360, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester);

      expect(
        find.byKey(const Key('level-detail-component-row')),
        findsNWidgets(5),
      );
      expect(find.byType(SsCard), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });
  });

  group('A2 — current and next level content is caller-fed, verbatim', () {
    testWidgets('a level below the ceiling shows both current and next', (
      tester,
    ) async {
      await _pump(tester, totalXp: 60);
      expect(
        find.byKey(const Key('level-detail-current-header')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('level-detail-next-header')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the ceiling level omits the next-level section', (
      tester,
    ) async {
      await _pump(tester, totalXp: 250);
      expect(
        find.byKey(const Key('level-detail-current-header')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('level-detail-next-header')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('A3 — phone viewport (360x640), textScaler 1.5/2.0/2.5, en+hu', () {
    for (final scale in <double>[1.5, 2.0, 2.5]) {
      for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
        testWidgets(
          '$scale / ${locale.languageCode} — no overflow, list scrollable',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pump(tester, locale: locale, textScale: scale);

            expect(find.byType(ListView), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
