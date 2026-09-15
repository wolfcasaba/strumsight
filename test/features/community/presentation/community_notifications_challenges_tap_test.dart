/// Notifications inbox → challenge list navigation (production wiring
/// round 2026-09-15).
///
/// ``CommunityChallengesScreen`` has no route (``app_router.dart``
/// deliberately left it out while the backend had no challenge list);
/// this round makes it reachable from the inbox in two ways, both
/// pinned here:
///
/// * the AppBar "Challenges" action pushes the list — on an empty
///   inbox too, the action does not depend on the inbox state;
/// * tapping a ``challengeInvite`` row marks it read (the existing
///   single mutation path) AND pushes the list. No id from the row
///   crosses over (A4 — ``notification_deeplink_test.dart`` keeps
///   pinning that a club-invite tap navigates nowhere).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/features/community/application/controllers/challenge_controller.dart';
import 'package:strumsight/features/community/application/controllers/notification_controller.dart';
import 'package:strumsight/features/community/domain/entities/community_challenge.dart';
import 'package:strumsight/features/community/domain/entities/notification_item.dart';
import 'package:strumsight/features/community/domain/repositories/challenge_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/notification_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/community_challenges_screen.dart';
import 'package:strumsight/features/community/presentation/screens/community_notifications_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const String _leakMarker = 'SECRET-CHALLENGE-ID-MUST-NOT-LEAK-4b1e';

class _RecordingNotificationRepository
    implements CommunityNotificationRepository {
  _RecordingNotificationRepository({required this.items});

  final List<CommunityNotificationItem> items;
  final List<ContentId> markReadCalls = <ContentId>[];

  @override
  Future<CommunityPage<CommunityNotificationItem>> inboxPage({
    required Object cursor,
    required int limit,
  }) async => CommunityPage<CommunityNotificationItem>(
    items: items,
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<void> markRead({
    required ContentId notificationId,
    required String idempotencyKey,
  }) async {
    markReadCalls.add(notificationId);
  }

  @override
  Future<void> markAllReadUpTo({
    required ContentId upToId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<Object> preferences() async => const <String, String>{};

  @override
  Future<void> updatePreference({
    required String category,
    required String level,
    required String idempotencyKey,
  }) async {}
}

/// The challenge list the pushed screen loads — empty, so the cell
/// only needs the screen to mount and settle.
class _EmptyChallengeRepository implements CommunityChallengeRepository {
  const _EmptyChallengeRepository();

  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async => const CommunityPage<CommunityChallengeDefinition>(
    items: <CommunityChallengeDefinition>[],
    cursor: CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async => throw UnimplementedError('fetchDefinition is unused.');

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async => throw UnimplementedError('fetchMyParticipation is unused.');

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw UnimplementedError('invite is unused.');

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('acceptInvite is unused.');

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('declineInvite is unused.');

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw UnimplementedError('cancelInvite is unused.');

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('submitResult is unused.');

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async => throw UnimplementedError('leaderboard is unused.');
}

Widget _wrap(_RecordingNotificationRepository fake) {
  return ProviderScope(
    overrides: [
      communityNotificationRepositoryProvider.overrideWithValue(fake),
      communityChallengeRepositoryProvider.overrideWithValue(
        const _EmptyChallengeRepository(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en')],
      home: const CommunityNotificationsScreen(),
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _RecordingNotificationRepository fake,
) async {
  // Tall viewport: the seeded row + the 10-kind preference panel stay
  // inside the first layout pass (the deep-link test precedent).
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(fake));
  for (var i = 0; i < 3; i += 1) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

CommunityNotificationItem _invite({required bool isRead}) =>
    CommunityNotificationItem(
      id: ContentId('n1'),
      kind: CommunityNotificationKind.challengeInvite,
      titleKey: 'communityNotificationChallengeInviteTitle',
      createdAt: DateTime.utc(2026, 9, 15),
      isRead: isRead,
      relatedContentId: ContentId(_leakMarker),
    );

void main() {
  testWidgets('the AppBar action pushes the challenge list', (tester) async {
    final fake = _RecordingNotificationRepository(
      items: const <CommunityNotificationItem>[],
    );
    await _pumpScreen(tester, fake);
    expect(find.byType(CommunityChallengesScreen), findsNothing);

    await tester.tap(find.byTooltip('Challenges'));
    await tester.pumpAndSettle();

    expect(find.byType(CommunityChallengesScreen), findsOneWidget);
    expect(fake.markReadCalls, isEmpty);
  });

  testWidgets('tapping an unread challenge invite marks it read AND pushes '
      'the challenge list', (tester) async {
    final fake = _RecordingNotificationRepository(
      items: <CommunityNotificationItem>[_invite(isRead: false)],
    );
    await _pumpScreen(tester, fake);

    await tester.tap(find.text('Challenge invite'));
    await tester.pumpAndSettle();

    expect(fake.markReadCalls, <ContentId>[ContentId('n1')]);
    expect(find.byType(CommunityChallengesScreen), findsOneWidget);
    // A4 — the pushed LIST never sees the row's relatedContentId.
    expect(find.textContaining(_leakMarker), findsNothing);
  });

  testWidgets('an already-read challenge invite still opens the list, '
      'without a second markRead', (tester) async {
    final fake = _RecordingNotificationRepository(
      items: <CommunityNotificationItem>[_invite(isRead: true)],
    );
    await _pumpScreen(tester, fake);

    await tester.tap(find.text('Challenge invite'));
    await tester.pumpAndSettle();

    expect(fake.markReadCalls, isEmpty);
    expect(find.byType(CommunityChallengesScreen), findsOneWidget);
  });
}
