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
      // hub is where such a session starts.
      expect(router.state.uri.path, AppRoutes.practiceHub);
    });

    // R34 — the remainder of MI1 (`docs/ui/legacy-backlog.md` §6.2). Until
    // this round the CTA was navigation ONLY: the domain's single recovery
    // concept, `StreakEvaluationRequest.recoveryEligible` (a LOWER
    // qualification threshold for one session), was never granted anywhere
    // in `lib/`, so the button promised a recovery practice and credited
    // nothing.
    testWidgets('the recovery CTA PERSISTS a single-use recovery grant', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      final router = await _pumpRouterTo(
        tester,
        AppRoutes.streakDetail,
        overrides: [preferenceStoreOverride(store)],
      );

      expect(
        store.readInt(StreakRecoveryGrantStore.storageKey),
        isNull,
        reason: 'nothing is credited before the learner asks for it',
      );

      final screen = tester.widget<StreakDetailScreen>(
        find.byType(StreakDetailScreen),
      );
      screen.onRecoveryPressed();
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.practiceHub);
      expect(
        store.readInt(StreakRecoveryGrantStore.storageKey),
        isNotNull,
        reason:
            'the grant is what makes the next short session qualify — a CTA '
            'that only navigates leaves the promise unpaid',
      );
    });

    test('the router no longer wires an empty recovery callback', () {
      final source = _readRouterSource();
      expect(source.contains('onRecoveryPressed: () {}'), isFalse);
      expect(source, contains('.grant(ref.read(todayEpochDayProvider))'));
      expect(source, contains('context.push(AppRoutes.practiceHub)'));
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
