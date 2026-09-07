// R22 (re-audit 2026-09-07 §3, MI1/MI2) — the two gamification controls
// that rendered as ACTIVE but did nothing are now wired at the router
// level. Both cells drive the REAL `routerProvider`, so a regression that
// re-empties either callback fails here and not only in a source scan.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

// `adaptiveShellEnabled: false` — this file asserts on top-level pushed
// paths, which the adaptive shell would rewrite into nested tab routes.
// `practiceEngineV2Enabled: true` — `/practice` is flag-gated (E02-R12);
// without it the push falls through the router's onException to `/live`.
FeatureFlags get _flatShellFlags => const FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  adaptiveShellEnabled: false,
  practiceEngineV2Enabled: true,
);

RewardLedgerEntry _rewardEntry(String sourceEventId, {int totalXp = 20}) =>
    RewardLedgerEntry(
      ledgerId: 'ledger-$sourceEventId',
      sourceEventId: sourceEventId,
      createdAt: DateTime.utc(2026, 2, 1),
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: 1,
      baseXp: totalXp,
      bonusXp: 0,
      totalXp: totalXp,
      reasonCodes: const <RewardReason>[RewardReason.baseExperience],
    );

String _readRouterSource() =>
    File('lib/app/routing/app_router.dart').readAsStringSync();

String _ledgerDocument(List<RewardLedgerEntry> entries) => storedDocument({
  'entries': entries.map((entry) => entry.toJson()).toList(),
  'processedEventIds': entries.map((entry) => entry.sourceEventId).toList(),
});

Future<GoRouter> _pumpRouterTo(
  WidgetTester tester,
  String path, {
  required List<Override> overrides,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: _flatShellFlags,
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

  router.go(path);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('MI1 — StreakDetailScreen.onRecoveryPressed', () {
    testWidgets('the recovery CTA navigates to the practice hub', (
      tester,
    ) async {
      final router = await _pumpRouterTo(
        tester,
        AppRoutes.streakDetail,
        overrides: preferenceOverrides({}),
      );

      final screen = tester.widget<StreakDetailScreen>(
        find.byType(StreakDetailScreen),
      );
      screen.onRecoveryPressed();
      await tester.pumpAndSettle();

      // The CTA's own copy is "Start a recovery practice" — the practice
      // hub is where such a session starts. The domain's ONLY recovery
      // concept is `StreakEvaluationRequest.recoveryEligible`, which no
      // repository can grant, so nothing else may be claimed here.
      expect(router.state.uri.path, AppRoutes.practiceHub);
    });

    test('the router no longer wires an empty recovery callback', () {
      final source = _readRouterSource();
      expect(source.contains('onRecoveryPressed: () {'), isFalse);
      expect(
        source,
        contains(
          'onRecoveryPressed: () => context.push(AppRoutes.practiceHub)',
        ),
      );
    });
  });

  group('MI2 — RewardInboxScreen.onItemSelected', () {
    testWidgets('selecting a row opens the reward summary sheet', (
      tester,
    ) async {
      final entry = _rewardEntry('practice-evt-route', totalXp: 15);
      await _pumpRouterTo(
        tester,
        AppRoutes.rewardInbox,
        overrides: preferenceOverrides({
          GamificationStorageKeys.rewardInbox: storedCollection([
            GamificationInboxItem(
              id: 'practice-evt-route',
              createdAt: DateTime.utc(2026, 3, 1),
            ).toJson(),
          ]),
          LocalRewardLedgerRepository.storageKey: _ledgerDocument([entry]),
        }),
      );

      final screen = tester.widget<RewardInboxScreen>(
        find.byType(RewardInboxScreen),
      );
      expect(screen.items, hasLength(1));
      final id = screen.items.single.id;
      expect(find.byType(RewardSummarySheet), findsNothing);

      await tester.tap(find.byKey(Key('reward-inbox-entry-tap-$id')));
      await tester.pumpAndSettle();

      expect(find.byType(RewardSummarySheet), findsOneWidget);
      final sheet = tester.widget<RewardSummarySheet>(
        find.byType(RewardSummarySheet),
      );
      // A REAL, ledger-joined event — not a placeholder summary.
      expect(sheet.summary.events, hasLength(1));
      expect(sheet.summary.events.single.earnedXp, 15);
      expect(sheet.summary.totalXp, 15);
    });

    test('the router no longer wires an empty selection callback', () {
      final source = _readRouterSource();
      expect(source.contains('onItemSelected: (_) {'), isFalse);
      expect(source, contains('RewardSummarySheet.show<void>('));
    });
  });
}
