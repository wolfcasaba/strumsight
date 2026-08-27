/// A1 / A7 — the ranglista stays opt-in and its "load more" is idempotent
/// (E13-R34, brief §6, §0.0.B/B5).
///
/// **A1 — opt-in stays server-owned.** The client has no opt-in switch
/// (§0.0.B/B5) — the mercy this round can measure from the Flutter side is
/// that the challenge join / invite-accept path never calls
/// `CommunityChallengeRepository.leaderboard()` and never synthesizes a
/// local rank row for the caller.
///
/// **A7 — "load more" is idempotent.** Re-invoking the load-more action
/// re-fetches the SAME first page and re-renders it as-is (no accumulation)
/// — a second tap must not duplicate a row or drop one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/features/community/application/controllers/challenge_controller.dart'
    hide communityChallengeRepositoryProvider;
import 'package:strumsight/features/community/application/controllers/challenge_controller.dart'
    as challenge_controller;
import 'package:strumsight/features/community/data/repositories/challenge_repository_impl.dart'
    show communityChallengeRepositoryProvider;
import 'package:strumsight/features/community/domain/entities/community_challenge.dart';
import 'package:strumsight/features/community/domain/repositories/challenge_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/leaderboard_screen.dart';

/// The `challenge_controller.dart`-owned repository provider — a
/// SEPARATE top-level `Provider` from the identically-named one in
/// `challenge_repository_impl.dart` that `leaderboard_screen.dart`
/// reads. Overriding the wrong one is a real measured trap (this
/// file's own git history): the A7 widget test below MUST override
/// the `challenge_repository_impl.dart` copy, and the A1
/// controller test MUST override this one.
final _controllerRepositoryProvider =
    challenge_controller.communityChallengeRepositoryProvider;

class _RecordingRepository implements CommunityChallengeRepository {
  _RecordingRepository();

  int leaderboardCalls = 0;
  int acceptCalls = 0;

  CommunityPage<LeaderboardEntry> leaderboardResult =
      const CommunityPage<LeaderboardEntry>(
        items: <LeaderboardEntry>[],
        cursor: CursorPage.haltedAfterRequest(),
      );

  CommunityPage<CommunityChallengeDefinition> listResult =
      const CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[],
        cursor: CursorPage.haltedAfterRequest(),
      );

  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async => listResult;

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async => throw UnimplementedError('unused');

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async => null;

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {
    acceptCalls++;
  }

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async {
    leaderboardCalls++;
    return leaderboardResult;
  }
}

LeaderboardEntry _entry({
  required String publicId,
  required int rank,
  required String displayName,
  required int metricValue,
}) {
  return LeaderboardEntry(
    publicId: PublicUserId(publicId),
    rank: rank,
    displayName: displayName,
    handle: '@$publicId',
    metricValue: metricValue,
    submittedAt: DateTime.utc(2026, 8, 24),
    verifiedBadge: true,
  );
}

void main() {
  group('A1 — the join path never touches the leaderboard', () {
    test(
      'ChallengeController.acceptInvite never calls repository.leaderboard()',
      () async {
        final fake = _RecordingRepository();
        final container = ProviderContainer(
          overrides: [_controllerRepositoryProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        await container.read(challengeControllerProvider.future);
        await container
            .read(challengeControllerProvider.notifier)
            .acceptInvite(ContentId('c1'));

        expect(fake.acceptCalls, 1);
        expect(
          fake.leaderboardCalls,
          0,
          reason:
              'accepting a challenge invite must not enroll the viewer '
              'onto a ranking — the opt-in stays server-owned (§0.0.B/B5)',
        );
      },
    );
  });

  group('A7 — leaderboard "load more" is idempotent', () {
    Widget wrap(_RecordingRepository fake, ContentId challengeId) {
      return ProviderScope(
        overrides: [
          communityChallengeRepositoryProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('en')],
          home: LeaderboardScreen(challengeId: challengeId),
        ),
      );
    }

    testWidgets('tapping "load more" twice does not duplicate or drop a row', (
      tester,
    ) async {
      final fake = _RecordingRepository();
      fake.leaderboardResult = CommunityPage<LeaderboardEntry>(
        items: <LeaderboardEntry>[
          _entry(
            publicId: 'u1',
            rank: 1,
            displayName: 'Alice',
            metricValue: 500,
          ),
          _entry(publicId: 'u2', rank: 2, displayName: 'Bob', metricValue: 420),
        ],
        cursor: const CursorPage.haltedAfterRequest(),
      );
      final challengeId = ContentId('c1');
      await tester.pumpWidget(wrap(fake, challengeId));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(fake.leaderboardCalls, 1);

      // Tap "load more" — re-fetches the SAME first page.
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(fake.leaderboardCalls, 2);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Tap it again — still no duplication, still no drop.
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(fake.leaderboardCalls, 3);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
    });
  });
}
