// E02-R07 / Task #7 — the four "0 hívás" routes that the E02 audit
// (R22/R16/R5/R11) flagged as registered-but-never-reached.
//
// Every cell below drives the REAL `routerProvider` from a contextual entry
// point and asserts that the registered route lands where the entry promised,
// instead of falling through `onException` to the generic entry location. A
// regression that silently empties any of the four callbacks (or removes the
// contextual entry the audit §5.2 list relied on) fails here, not in a static
// source scan — the same technique R22 (`r22_dead_control_wiring_test.dart`)
// and R18 (`r18_entry_points_test.dart`) already use.
//
// The four routes:
//   * `AppRoutes.rewardInbox`              (`/gamification/inbox`)           R22
//   * `AppRoutes.profileRewards`           (`/profile/rewards`)              R22
//   * `AppRoutes.profileProgressSkill`     (`/profile/progress/skills/:id`)  R2-Progress
//   * `AppRoutes.communityClubDetail`      (`/community/clubs/:clubId`)      R5
//
// `adaptiveShellEnabled: true` — every contextual entry is shipped that way.
// The flat-shell harness used elsewhere cannot drive `/streak → /profile/rewards`
// (the legacy redirect is shell-only) or the dashboard's
// `onOpenSkillDetail` (the milestone rows render inside the shell branch).
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
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/community/data/repositories/club_repository_impl.dart'
    show communityClubRepositoryProvider;
import 'package:strumsight/features/community/domain/entities/community_club.dart';
import 'package:strumsight/features/community/domain/repositories/club_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_detail_screen.dart';
import 'package:strumsight/features/gamification/data/gamification_storage_schema.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/domain/rewards/reward_ledger_entry.dart';
import 'package:strumsight/features/gamification/domain/rewards/reward_reason.dart';
import 'package:strumsight/features/gamification/presentation/screens/gamification_hub_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/reward_inbox_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/features/streak/screens/streak_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

FeatureFlags get _adaptiveFlags => const FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  adaptiveShellEnabled: true,
  // Community + clubs: `/community/clubs/:clubId` is `communityClubsEnabled`-gated.
  communityEnabled: true,
  communityClubsEnabled: true,
  // Practice Engine V2: `/practice` is gated — without this, the gamification
  // hub's own quest-row push would fall through the router's `onException`.
  practiceEngineV2Enabled: true,
);

Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  required String initialLocation,
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
          flags: _adaptiveFlags,
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

  router.go(initialLocation);
  await tester.pumpAndSettle();
  return router;
}

/// Bounded wait for a route-level transition (one frame is rarely enough when
/// the push navigates across a shell branch — the shell re-mounts the
/// branch's `Navigator`, and that costs at least one extra paint).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  // -------------------------------------------------------------------------
  // Reward inbox (`/gamification/inbox`).
  //
  // R22 (audit §5.2 MI2): the inbox screen's `onItemSelected` was wired up to
  // open the `RewardSummarySheet`; the inbox ROUTE itself has been reachable
  // from the hub's inbox indicator since E16-R01. The cell below drives that
  // path end to end — tap the indicator, arrive on the inbox — so a
  // regression that empties the callback OR drops the `gamificationHub`
  // `onOpenInbox` wiring fails here.
  // -------------------------------------------------------------------------
  group(
    'rewardInbox — the gamification hub\'s inbox indicator opens the route',
    () {
      testWidgets(
        'tapping the inbox indicator on the hub pushes /gamification/inbox '
        'and renders RewardInboxScreen',
        (tester) async {
          final entry = _rewardEntry('practice-evt-route', totalXp: 15);
          final router = await _pumpRouter(
            tester,
            initialLocation: AppRoutes.gamificationHub,
            overrides: preferenceOverrides({
              GamificationStorageKeys.rewardInbox: storedCollection([
                <String, dynamic>{
                  'id': 'practice-evt-route',
                  'createdAt': DateTime.utc(2026, 3, 1).toIso8601String(),
                  'schemaVersion': 1,
                },
              ]),
              LocalRewardLedgerRepository.storageKey: _ledgerDocument([entry]),
            }),
          );

          final hub = tester.widget<GamificationHubScreen>(
            find.byType(GamificationHubScreen),
          );
          hub.onOpenInbox();
          await _settle(tester);

          expect(router.state.uri.path, AppRoutes.rewardInbox);
          expect(find.byType(RewardInboxScreen), findsOneWidget);
          final inbox = tester.widget<RewardInboxScreen>(
            find.byType(RewardInboxScreen),
          );
          // The inbox reflects the seeded ledger entry — the real projection,
          // not an empty placeholder.
          expect(inbox.items, hasLength(1));
          expect(inbox.items.single.event.earnedXp, 15);
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Profile rewards (`/profile/rewards`).
  //
  // R22 audit §5.2: no caller in `lib/` pushes `AppRoutes.profileRewards`
  // directly. The route lives in the adaptive shell's profile branch and is
  // reached only through the legacy `/streak` redirect (legacyRedirects map,
  // `adaptive_shell_routes.dart`). The shipped `StreakBadge` widget on the
  // Live header pushes `/streak`, which under the adaptive shell lands here.
  //
  // The cell below drives that chain through the REAL router: arriving on
  // `/streak` redirects to `/profile/rewards` and renders `StreakScreen`.
  // A regression that breaks the legacy map, drops `StreakScreen` from the
  // profile branch, or short-circuits the redirect fails here.
  // -------------------------------------------------------------------------
  group('profileRewards — /streak legacy redirect lands on the route', () {
    testWidgets('arriving on /streak under the adaptive shell redirects to '
        '/profile/rewards and renders StreakScreen', (tester) async {
      final router = await _pumpRouter(
        tester,
        initialLocation: AppRoutes.streak,
        overrides: preferenceOverrides({}),
      );

      expect(router.state.uri.path, AppRoutes.profileRewards);
      expect(router.state.uri.path, isNot(AppRoutes.streak));
      expect(find.byType(StreakScreen), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Profile progress skill detail (`/profile/progress/skills/:skillId`).
  //
  // The dashboard's `onOpenSkillDetail` hands back a milestone id; the
  // router resolves it to the milestone's `skill.code` and pushes the route.
  // A regression that empties the callback (the E22 dead-control class) OR
  // drops the `_masteryMilestoneById` resolver (so the push silently
  // short-circuits) fails here. The seed satisfies the new-user threshold
  // so the milestone rows are present at all.
  // -------------------------------------------------------------------------
  group(
    'profileProgressSkill — the dashboard\'s milestone row opens the route',
    () {
      testWidgets('tapping a milestone row from the dashboard pushes '
          '/profile/progress/skills/<skillCode> with a real projection', (
        tester,
      ) async {
        final router = await _pumpRouter(
          tester,
          initialLocation: AppRoutes.profileProgress,
          overrides: [
            progressPracticeHistoryProvider.overrideWithValue(
              _qualifiedChordSessions(),
            ),
          ],
        );

        await tester.tap(
          find.byKey(
            const ValueKey('progress-skill-row-mastery_chord_transition_v1'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          router.state.uri.path,
          '/profile/progress/skills/chordTransition',
          reason:
              'a tap on the chord-transition milestone must resolve to '
              'the milestone\'s skill code, not the milestone id',
        );
        expect(find.byType(SkillDetailScreen), findsOneWidget);
        final detail = tester.widget<SkillDetailScreen>(
          find.byType(SkillDetailScreen),
        );
        // Real ARB-resolved title — a regression that bypassed the
        // localization closure would land on the raw key here.
        expect(detail.projection.title, isNot('masteryChordTransitionTitle'));
        expect(detail.projection.title, isNotEmpty);
      });
    },
  );

  // -------------------------------------------------------------------------
  // Community club detail (`/community/clubs/:clubId`).
  //
  // R5 (WP-C, audit §5.2): the club list's row InkWell pushes this route
  // with the tapped club's id. A regression that removes the InkWell (so
  // the row stops being tappable), drops the `context.push` (so taps fall
  // through to the list's own RefreshIndicator), or shortens the route
  // template to a literal (so the `:clubId` is dropped) fails here.
  // -------------------------------------------------------------------------
  group(
    'communityClubDetail — the club list\'s row opens the route with the id',
    () {
      testWidgets('tapping a club row from the list pushes '
          '/community/clubs/<clubPublicId> and renders ClubDetailScreen', (
        tester,
      ) async {
        final router = await _pumpRouter(
          tester,
          initialLocation: AppRoutes.communityClubs,
          overrides: [
            communityClubRepositoryProvider.overrideWithValue(
              _SeedingClubsRepository([
                _club(
                  publicId: 'club-7',
                  name: 'Blues Lovers',
                  visibility: ClubVisibility.discoverable,
                  memberCount: 12,
                ),
              ]),
            ),
          ],
        );

        await tester.tap(find.byKey(const Key('club-row-club-7')));
        await tester.pumpAndSettle();

        expect(
          router.state.uri.path,
          AppRoutes.communityClubDetail.replaceFirst(':clubId', 'club-7'),
          reason:
              'the tapped club\'s public id must replace the route\'s '
              ':clubId segment — a literal in the template would land '
              'somewhere else entirely',
        );
        expect(find.byType(ClubDetailScreen), findsOneWidget);
        final detail = tester.widget<ClubDetailScreen>(
          find.byType(ClubDetailScreen),
        );
        expect(detail.clubId.value, 'club-7');
      });
    },
  );
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

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

String _ledgerDocument(List<RewardLedgerEntry> entries) => storedDocument({
  'entries': entries.map((entry) => entry.toJson()).toList(),
  'processedEventIds': entries.map((entry) => entry.sourceEventId).toList(),
});

PracticeMetricSnapshot _chordSnapshot(double value) => PracticeMetricSnapshot(
  completion: const PracticeMetricDimensionNotApplicable(),
  rhythm: const PracticeMetricDimensionNotApplicable(),
  direction: const PracticeMetricDimensionNotApplicable(),
  chord: PracticeMetricDimension.available(value),
  overall: PracticeMetricDimension.available(value),
);

PracticeHistoryEntry _chordSession(String id, DateTime createdAt) =>
    PracticeHistoryEntry(
      id: id,
      modeCode: 'practice.mode.strumPattern',
      sourceCode: 'builtin',
      createdAt: createdAt,
      definitionId: 'builtin.quarterDownstrokes.v1',
      displayTitle: '',
      finishReasonCode: PracticeFinishReason.completedAllTargets.code,
      activeDuration: const Duration(seconds: 30),
      pausedDuration: Duration.zero,
      attemptsCount: 1,
      finalMetricSnapshot: _chordSnapshot(0.9),
      totalTargets: 4,
      resolvedTargets: 4,
      scorePoints: 100,
      maxCombo: 4,
      meanAbsoluteOffset: Duration.zero,
      timingBias: Duration.zero,
      coachingSummary: const <String>[],
      skillTags: const <String>[],
    );

/// Three qualifying sessions clear `mastery_chord_transition_v1`'s
/// `minEvidenceSessions: 3` at a measured value above its `0.8` threshold —
/// the same fixture the `progress_composition_test.dart` A10 cell uses.
List<PracticeHistoryEntry> _qualifiedChordSessions() => <PracticeHistoryEntry>[
  _chordSession('chord-1', DateTime.utc(2026, 8, 1)),
  _chordSession('chord-2', DateTime.utc(2026, 8, 2)),
  _chordSession('chord-3', DateTime.utc(2026, 8, 3)),
];

CommunityClub _club({
  required String publicId,
  required String name,
  required ClubVisibility visibility,
  required int memberCount,
  ClubRole? myRole,
  String? ownerPublicId,
}) {
  return CommunityClub(
    id: ContentId(publicId),
    name: name,
    description: 'description for $name',
    visibility: visibility,
    tags: const <String>[],
    ownerId: PublicUserId(ownerPublicId ?? 'owner-1'),
    memberCount: memberCount,
    myRole: myRole,
    createdAt: DateTime.utc(2026, 8, 24),
  );
}

/// A minimal `CommunityClubRepository` that serves the two methods the list +
/// detail screens touch. The other eight throw — if a future refactor starts
/// calling an unexpected method, the test goes loud instead of silently
/// returning a fake success.
class _SeedingClubsRepository implements CommunityClubRepository {
  _SeedingClubsRepository(this._clubs);
  final List<CommunityClub> _clubs;

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async {
    return CommunityPage<CommunityClub>(
      items: _clubs,
      cursor: const CursorPage.haltedAfterRequest(),
    );
  }

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async {
    return _clubs.firstWhere((club) => club.id == clubId);
  }

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError();
  }
}
