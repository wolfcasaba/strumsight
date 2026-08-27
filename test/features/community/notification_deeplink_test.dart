/// A4 — the notification row surface is structural abstinence
/// (E13-R34, brief §6, §0.0.B/B8).
///
/// `CommunityNotificationItem` carries no route / URL / deep-link
/// field, only `relatedContentId`. The screen's visible AND
/// `Semantics` surface must be built EXCLUSIVELY from
/// `titleKey` / `bodyKey` / `kind` / `isRead` — content DERIVED from
/// `relatedContentId` (e.g. a private club's name fetched by that id)
/// must never appear. Tapping a row must only call `markRead`; there
/// is no navigation surface to falsify (the community screens are
/// not registered in `lib/app/routing/**`, out of this round's scope).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/features/community/application/controllers/notification_controller.dart';
import 'package:strumsight/features/community/domain/entities/notification_item.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/notification_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/presentation/screens/community_notifications_screen.dart';

/// A marker string that would ONLY appear on screen if the row
/// resolved and rendered content derived from `relatedContentId` —
/// e.g. a private club's name fetched by that id. No production
/// code path may print this string.
const _forbiddenLeakedContent = 'SECRET-CLUB-CONTENT-MUST-NOT-LEAK-9f3c';

class _RecordingNotificationRepository
    implements CommunityNotificationRepository {
  _RecordingNotificationRepository();

  final List<ContentId> markReadCalls = <ContentId>[];

  CommunityPage<CommunityNotificationItem> inboxResult =
      const CommunityPage<CommunityNotificationItem>(
        items: <CommunityNotificationItem>[],
        cursor: CursorPage.haltedAfterRequest(),
      );

  @override
  Future<CommunityPage<CommunityNotificationItem>> inboxPage({
    required Object cursor,
    required int limit,
  }) async => inboxResult;

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

Widget _wrap(_RecordingNotificationRepository fake) {
  return ProviderScope(
    overrides: [
      communityNotificationRepositoryProvider.overrideWithValue(fake),
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
  // The inbox body is a sliver-backed ListView (production behaviour —
  // real devices scroll to reach off-screen rows); a tall test viewport
  // keeps the single seeded row + the 10-kind preference panel both
  // within the initial layout pass so this test does not need to
  // simulate a scroll to reach it.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(fake));
  for (var i = 0; i < 3; i += 1) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('A4 — the row surface never derives content from relatedContentId', () {
    testWidgets(
      'a club-invite notification with a relatedContentId never renders the '
      'marker text anywhere in the tree',
      (tester) async {
        final fake = _RecordingNotificationRepository();
        fake.inboxResult = CommunityPage<CommunityNotificationItem>(
          items: <CommunityNotificationItem>[
            CommunityNotificationItem(
              id: ContentId('n1'),
              kind: CommunityNotificationKind.clubInvite,
              titleKey: 'communityNotificationClubInviteTitle',
              createdAt: DateTime.utc(2026, 8, 24),
              isRead: false,
              // The id itself intentionally carries the marker
              // string — if the row EVER resolved and rendered
              // content by this id (e.g. "fetch the club name for
              // display"), the marker would leak onto the screen.
              relatedContentId: ContentId(_forbiddenLeakedContent),
            ),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        expect(find.textContaining(_forbiddenLeakedContent), findsNothing);
        // The row DOES render — from titleKey alone.
        expect(find.text('Club invite'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping an unread row calls ONLY markRead — no navigation surface '
      'exists to falsify',
      (tester) async {
        final fake = _RecordingNotificationRepository();
        fake.inboxResult = CommunityPage<CommunityNotificationItem>(
          items: <CommunityNotificationItem>[
            CommunityNotificationItem(
              id: ContentId('n1'),
              kind: CommunityNotificationKind.clubInvite,
              titleKey: 'communityNotificationClubInviteTitle',
              createdAt: DateTime.utc(2026, 8, 24),
              isRead: false,
              relatedContentId: ContentId(_forbiddenLeakedContent),
            ),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        await tester.tap(find.text('Club invite'));
        await tester.pumpAndSettle();

        expect(fake.markReadCalls, <ContentId>[ContentId('n1')]);
        // No navigator push happened — the screen is still on the
        // notifications route (still shows the AppBar title).
        expect(find.text('Notifications'), findsOneWidget);
      },
    );

    testWidgets(
      'a challenge-completed notification with a relatedContentId also '
      'never leaks the marker',
      (tester) async {
        final fake = _RecordingNotificationRepository();
        fake.inboxResult = CommunityPage<CommunityNotificationItem>(
          items: <CommunityNotificationItem>[
            CommunityNotificationItem(
              id: ContentId('n2'),
              kind: CommunityNotificationKind.challengeCompleted,
              titleKey: 'communityNotificationChallengeCompletedTitle',
              createdAt: DateTime.utc(2026, 8, 24),
              isRead: true,
              relatedContentId: ContentId(_forbiddenLeakedContent),
            ),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        expect(find.textContaining(_forbiddenLeakedContent), findsNothing);
        expect(find.text('Challenge completed'), findsOneWidget);
      },
    );
  });
}
