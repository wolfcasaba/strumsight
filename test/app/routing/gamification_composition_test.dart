// E16-R01 (ADR 0496) — router-level composition acceptance.
// A1/A2: the gamification block of app_router.dart sources every value from
// a provider — no placeholder literal, no baked LevelCurve, no
// TODO(E08-R30) marker survives (statically scanned from the file on disk,
// the same technique the brief's mandatory violation probe exercises).
// A7: the hub's onOpenLevelDetail navigates to the new AppRoutes.levelDetail
// route, and the route renders a real (not fake) profile projection.
import 'dart:async';
import 'dart:io';

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
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../support/preference_store.dart';

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

RewardLedgerEntry _achievementReceipt(String achievementId) =>
    RewardLedgerEntry(
      ledgerId: 'achievement:$achievementId:evt-1',
      sourceEventId: 'achievement:$achievementId',
      createdAt: DateTime.utc(2026, 1, 1),
      schemaVersion: rewardLedgerEntrySchemaVersion,
      policyVersion: achievementEvaluatorPolicyVersion,
      baseXp: 0,
      bonusXp: 0,
      totalXp: 0,
      reasonCodes: const <RewardReason>[RewardReason.achievementUnlocked],
    );

String _ledgerDocument(List<RewardLedgerEntry> entries) => storedDocument({
  'entries': entries.map((entry) => entry.toJson()).toList(),
  'processedEventIds': entries.map((entry) => entry.sourceEventId).toList(),
});

// adaptiveShellEnabled: false — these tests push top-level routes
// (`AppRoutes.practiceHub`, `.live`) and assert on the resulting `path`
// directly; the adaptive shell rewrites those into nested tab sub-routes,
// which is orthogonal to what §0.0.A/R3 #4 measures here.
FeatureFlags get _flatShellFlags => const FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  adaptiveShellEnabled: false,
  // `/practice` is flag-gated (E02-R12) — without this, QuestStartPracticeAction's
  // push falls through the router's onException redirect to `/live`.
  practiceEngineV2Enabled: true,
);

/// Shared harness: builds a real router over [overrides] and navigates it to
/// [path], returning the live [GoRouter] so a test can inspect the pushed
/// screen widget and drive further navigation. Uses a bounded [pump] instead
/// of `pumpAndSettle` when the destination itself has a running animation
/// (e.g. a loading spinner) that would otherwise never settle.
Future<GoRouter> _pumpRouterTo(
  WidgetTester tester,
  String path, {
  required List<Override> overrides,
  bool settle = true,
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A bounded pump sequence (not `pumpAndSettle`, which would hang on an
    // indefinitely-animating CircularProgressIndicator) that still advances
    // enough wall-clock time for the page-route transition itself to finish
    // — same three-pump shape as `shell_lifecycle_test.dart`.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
  }
  return router;
}

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

    // Fix-round review M3, row "Provider a routerben marad, csak
    // ÁTNEVEZVE": the check above only greps five specific OLD names, so any
    // OTHER private `final _fooProvider =` declaration slips through
    // unnoticed. A shape-based scan closes that: NO private provider
    // declaration of any name may live in this file, renamed or not.
    test('no private *Provider declaration of any name lives in the router', () {
      final privateProviderDeclaration = RegExp(
        r'final _\w+Provider(<[^>]*>)? =',
      );
      expect(
        privateProviderDeclaration.hasMatch(source),
        isFalse,
        reason:
            'found a private provider declared directly in app_router.dart '
            '— composition belongs in gamification_providers.dart (ADR 0496 §1)',
      );
    });

    // Fix-round review B2: the quest board is sourced from a provider, not a
    // bare literal (the router previously had `dailyChallengeAvailable:
    // false` / `dailyQuests: const <QuestViewProjection>[]` typed directly).
    test(
      'the quest board is sourced from questBoardProvider, not a bare literal',
      () {
        expect(block.contains('dailyChallengeAvailable: false,'), isFalse);
        expect(
          block.contains('dailyQuests: const <QuestViewProjection>[]'),
          isFalse,
        );
        expect(
          block.contains('weeklyQuests: const <QuestViewProjection>[]'),
          isFalse,
        );
        expect(block, contains('dailyChallenge: questBoard.dailyChallenge'));
        expect(
          block,
          contains(
            'dailyChallengeAvailable: questBoard.dailyChallengeAvailable',
          ),
        );
        expect(block, contains('dailyQuests: questBoard.dailyQuests'));
        expect(block, contains('weeklyQuests: questBoard.weeklyQuests'));
      },
    );

    // Fix-round review B1: the OLD bug collapsed loading/error into the
    // measured-empty fallback via `?? const <String, AchievementProgress>{}`
    // read directly off `.value` in the builder. That exact pattern must not
    // reappear in either achievement route.
    test(
      'the achievement routes no longer collapse loading/error into the measured empty',
      () {
        expect(
          block.contains('achievementProgressProvider).value ??'),
          isFalse,
        );
        expect(block, contains('_achievementsAsyncBuilder('));
      },
    );
  });

  group(
    'docs/ui/legacy-backlog.md — BACKLOG entries are not silently dropped (A5/M1/M2/B2)',
    () {
      late String backlog;

      setUpAll(() {
        backlog = File('docs/ui/legacy-backlog.md').readAsStringSync();
      });

      test(
        'the three original E16-R01 entries (R3 #1/#6/#7) are still present',
        () {
          expect(backlog, contains('E16-R01 entry 1'));
          expect(backlog, contains('E16-R01 entry 2'));
          expect(backlog, contains('E16-R01 entry 3'));
        },
      );

      // Fix-round additions: B2 (quest source), M1 (four inexpressible-gap
      // values), M2 (unwired producers) each need their own dated, owned entry
      // — review's explicit complaint was that NONE of these existed yet.
      test(
        'the fix-round entries (quest source, four gap values, producers) exist',
        () {
          expect(backlog, contains('E16-R01 entry 4'));
          expect(backlog, contains('E16-R01 entry 5'));
          expect(backlog, contains('E16-R01 entry 6'));
        },
      );
    },
  );

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

  group(
    'router — B1 (loading/error no longer collapse into the measured empty)',
    () {
      testWidgets(
        'a still-loading achievementProgressProvider shows a loading state, not AchievementsScreen',
        (tester) async {
          final neverCompletes = Completer<Map<String, AchievementProgress>>();
          await _pumpRouterTo(
            tester,
            AppRoutes.achievements,
            overrides: [
              ...preferenceOverrides({}),
              achievementProgressProvider.overrideWith(
                (ref) => neverCompletes.future,
              ),
            ],
            settle: false,
          );

          // The OLD bug rendered AchievementsScreen immediately with `?? {}`
          // — indistinguishable from a genuinely empty, fully-loaded result.
          expect(find.byType(AchievementsScreen), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        },
      );

      testWidgets(
        'a failing achievementProgressProvider logs the error and still renders the screen',
        (tester) async {
          final logger = _RecordingAppLogger();
          await _pumpRouterTo(
            tester,
            AppRoutes.achievements,
            overrides: [
              ...preferenceOverrides({}),
              achievementProgressProvider.overrideWith(
                (ref) async => throw Exception('ledger unavailable'),
              ),
              appLoggerProvider.overrideWithValue(logger),
            ],
          );

          expect(find.byType(AchievementsScreen), findsOneWidget);
          final screen = tester.widget<AchievementsScreen>(
            find.byType(AchievementsScreen),
          );
          expect(screen.progressByAchievement, isEmpty);
          expect(
            logger.errorEvents,
            contains('gamification.achievement_progress.load_failed'),
          );
        },
      );
    },
  );

  group('router — A1 route-level cells (§0.0.A/R3 #3/#4/#5/#8)', () {
    testWidgets(
      '#3 achievement-progress: a real ledger receipt reaches the screen',
      (tester) async {
        final achievementId = defaultAchievementCatalog.definitions.first.id;
        final receipt = _achievementReceipt(achievementId);
        await _pumpRouterTo(
          tester,
          AppRoutes.achievements,
          overrides: preferenceOverrides({
            LocalRewardLedgerRepository.storageKey: _ledgerDocument([receipt]),
          }),
        );

        final screen = tester.widget<AchievementsScreen>(
          find.byType(AchievementsScreen),
        );
        final progress = screen.progressByAchievement[achievementId];
        expect(progress, isNotNull);
        expect(progress!.completedAt, isNotNull);
      },
    );

    testWidgets(
      '#4 quest-action routing: QuestStartPracticeAction pushes the practice hub',
      (tester) async {
        final router = await _pumpRouterTo(
          tester,
          AppRoutes.quests,
          overrides: preferenceOverrides({}),
        );

        final questsScreen = tester.widget<QuestsScreen>(
          find.byType(QuestsScreen),
        );
        questsScreen.onAction(
          QuestStartPracticeAction(SkillTagQuestObjective('warmup')),
        );
        await tester.pumpAndSettle();

        expect(router.state.uri.path, AppRoutes.practiceHub);
      },
    );

    testWidgets('#4 quest-action routing: QuestTryLiveAction pushes Live', (
      tester,
    ) async {
      final router = await _pumpRouterTo(
        tester,
        AppRoutes.quests,
        overrides: preferenceOverrides({}),
      );

      final questsScreen = tester.widget<QuestsScreen>(
        find.byType(QuestsScreen),
      );
      questsScreen.onAction(const QuestTryLiveAction(Object()));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.live);
    });

    testWidgets(
      '#5 streak-reason: no activity yields the real service reason, not a baked qualified',
      (tester) async {
        await _pumpRouterTo(
          tester,
          AppRoutes.streakDetail,
          overrides: preferenceOverrides({}),
        );

        final screen = tester.widget<StreakDetailScreen>(
          find.byType(StreakDetailScreen),
        );
        expect(screen.reason, isNot(StreakEvaluationReason.qualified));
        expect(screen.reason, StreakEvaluationReason.insufficientActivity);
      },
    );

    testWidgets(
      '#8 inbox-join: a real ledger-joined item reaches the screen, localized (B3)',
      (tester) async {
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
        final event = screen.items.single.event;
        expect(event.earnedXp, 15);
        // B3: real, existing ARB text — not the raw `RewardKind.name` internal
        // placeholder and not baked English that never went through l10n.
        expect(event.titleKey, isNot('dailyReward'));
        expect(event.titleKey, isNotEmpty);
      },
    );
  });
}

class _RecordingAppLogger implements AppLogger {
  final errorEvents = <String>[];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {}

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    errorEvents.add(event);
  }
}
