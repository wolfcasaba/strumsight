// E16-R01 (ADR 0496) — router-level composition acceptance.
// A1/A2: the gamification block of app_router.dart sources every value from
// a provider — no placeholder literal, no baked LevelCurve, no
// TODO(E08-R30) marker survives (statically scanned from the file on disk,
// the same technique the brief's mandatory violation probe exercises).
// A7: the hub's onOpenLevelDetail navigates to the new AppRoutes.levelDetail
// route, and the route renders a real (not fake) profile projection.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/data/gamification_storage_schema.dart';
import 'package:strumsight/features/gamification/presentation/screens/gamification_hub_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/level_detail_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../support/preference_store.dart';

String _readRouterSource() =>
    File('lib/app/routing/app_router.dart').readAsStringSync();

/// Isolates the gamification `GoRoute`s from the rest of the (much larger)
/// router file so a cell here cannot accidentally pass or fail because of
/// unrelated router text.
String _gamificationBlock(String source) {
  final start = source.indexOf('AppRoutes.gamificationHub');
  final end = source.indexOf('\n    ],', start);
  expect(start, greaterThan(-1), reason: 'gamification hub route not found');
  expect(
    end,
    greaterThan(start),
    reason: 'end of the top-level routes list not found',
  );
  return source.substring(start, end);
}

void main() {
  group('router source — A2 (no placeholder literal / baked curve survives)', () {
    late String source;
    late String block;

    setUpAll(() {
      source = _readRouterSource();
      block = _gamificationBlock(source);
    });

    test('no TODO(E08-R30) marker remains anywhere in the router', () {
      expect(source.contains('TODO(E08-R30)'), isFalse);
    });

    test('activeQuestCount is sourced from a provider, not a bare literal', () {
      expect(block.contains('activeQuestCount: 0'), isFalse);
      expect(block, contains('activeQuestCount: activeQuests.value'));
    });

    test(
      'masteryUnlockedCount is sourced from a provider, not a bare literal',
      () {
        expect(block.contains('masteryUnlockedCount: 0'), isFalse);
        expect(block, contains('masteryUnlockedCount: masteryUnlocked.value'));
      },
    );

    test(
      'no baked LevelCurve/LevelDefinition construction remains in the router',
      () {
        expect(source.contains('LevelDefinition('), isFalse);
      },
    );

    test('onOpenLevelDetail is no longer an empty no-op callback', () {
      expect(block.contains('onOpenLevelDetail: () {}'), isFalse);
      expect(
        block,
        contains(
          'onOpenLevelDetail: () => context.push(AppRoutes.levelDetail)',
        ),
      );
    });

    test(
      'the private E08-R30 provider declarations no longer live in the router',
      () {
        expect(source.contains('_gamificationProfileProvider'), isFalse);
        expect(source.contains('_streakStateProvider ='), isFalse);
        expect(source.contains('_rewardInboxProvider'), isFalse);
        expect(source.contains('_levelCurveProvider'), isFalse);
        expect(source.contains('_gamificationRepositoryProvider'), isFalse);
      },
    );
  });

  group(
    'router — A7 (level-detail route reachable with a real projection)',
    () {
      testWidgets(
        'onOpenLevelDetail pushes AppRoutes.levelDetail with the real profile',
        (tester) async {
          final container = ProviderContainer(
            overrides: [
              ...preferenceOverrides({
                GamificationStorageKeys.profileSnapshot: storedDocument(const {
                  'schemaVersion': gamificationStorageSchemaVersion,
                  'totalXp': 260,
                }),
              }),
              onboardingSeenProvider.overrideWith(
                () => OnboardingController(true),
              ),
              appConfigProvider.overrideWithValue(
                AppConfig(
                  environment: AppEnvironment.development,
                  apiBaseUrl: AppConfig.devApiBaseUrl,
                  flags: const FeatureFlags(
                    accountEnabled: false,
                    diagnosticsEnabled: false,
                    labModeAvailable: false,
                    adaptiveShellEnabled: true,
                  ),
                  diagnosticsToken: AppConfig.devDiagnosticsToken,
                  buildMode: 'test',
                  appVersion: 'test',
                ),
              ),
            ],
          );
          addTearDown(container.dispose);

          final router = container.read(routerProvider);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp.router(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();

          router.go(AppRoutes.gamificationHub);
          await tester.pumpAndSettle();
          expect(find.byType(GamificationHubScreen), findsOneWidget);

          final hub = tester.widget<GamificationHubScreen>(
            find.byType(GamificationHubScreen),
          );
          // A real projection, not a fixture: proves the hub's profile came
          // from the seeded storage snapshot rather than a hardcoded 0.
          expect(hub.profile.totalXp, 260);

          hub.onOpenLevelDetail();
          await tester.pumpAndSettle();

          expect(router.state.uri.path, AppRoutes.levelDetail);
          expect(find.byType(LevelDetailScreen), findsOneWidget);
          final detail = tester.widget<LevelDetailScreen>(
            find.byType(LevelDetailScreen),
          );
          expect(detail.profile.totalXp, 260);
        },
      );
    },
  );
}
