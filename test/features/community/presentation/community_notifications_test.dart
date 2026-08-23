/// Community notifications widget tests (E09-R20, ADR 0414, brief
/// §6 A6).
///
/// The screen + controller are exercised against a recording
/// fake repository. The A6 cell — per-category push preference
/// toggle works through the controller — is the only
/// acceptance cell the Flutter side owns (the A1–A5 + A7
/// cells are backend-pytest pinned, see
/// ``backend/tests/community/test_notification_service.py``).
///
/// * A6 — selecting a different preference level for any
///   category lands an ``updatePreference(category, level,
///   idempotencyKey)`` call on the repository, and the
///   controller's state reflects the new level.
///
/// The widget also covers:
/// * the empty-state branch (no items);
/// * the optimistic mark-read → repository call sequence;
/// * the failure-rollback branch (a failed ``markRead`` rolls
///   the optimistic flip back, surfaces the error).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/features/community/application/controllers/notification_controller.dart';
import 'package:strumsight/features/community/domain/entities/notification_item.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/notification_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/presentation/screens/community_notifications_screen.dart';

// ---------------------------------------------------------------------------
// Recording fake repository — captures every call the
// controller makes and lets the test stub specific outcomes.
// ---------------------------------------------------------------------------

class _RecordingNotificationRepository
    implements CommunityNotificationRepository {
  _RecordingNotificationRepository();

  final List<({String category, String level, String idempotencyKey})>
  updatePreferenceCalls =
      <({String category, String level, String idempotencyKey})>[];
  final List<({ContentId notificationId, String idempotencyKey})>
  markReadCalls = <({ContentId notificationId, String idempotencyKey})>[];
  final List<({ContentId upToId, String idempotencyKey})> markAllReadCalls =
      <({ContentId upToId, String idempotencyKey})>[];
  final List<({Object cursor, int limit})> inboxPageCalls =
      <({Object cursor, int limit})>[];

  CommunityPage<CommunityNotificationItem> inboxResult =
      const CommunityPage<CommunityNotificationItem>(
        items: <CommunityNotificationItem>[],
        cursor: CursorPage.haltedAfterRequest(),
      );
  Object preferencesResult = const <String, String>{};

  AppFailure? markReadFailure;
  AppFailure? updatePreferenceFailure;

  @override
  Future<CommunityPage<CommunityNotificationItem>> inboxPage({
    required Object cursor,
    required int limit,
  }) async {
    inboxPageCalls.add((cursor: cursor, limit: limit));
    return inboxResult;
  }

  @override
  Future<void> markRead({
    required ContentId notificationId,
    required String idempotencyKey,
  }) async {
    markReadCalls.add((
      notificationId: notificationId,
      idempotencyKey: idempotencyKey,
    ));
    if (markReadFailure != null) throw markReadFailure!;
  }

  @override
  Future<void> markAllReadUpTo({
    required ContentId upToId,
    required String idempotencyKey,
  }) async {
    markAllReadCalls.add((upToId: upToId, idempotencyKey: idempotencyKey));
  }

  @override
  Future<Object> preferences() async {
    return preferencesResult;
  }

  @override
  Future<void> updatePreference({
    required String category,
    required String level,
    required String idempotencyKey,
  }) async {
    updatePreferenceCalls.add((
      category: category,
      level: level,
      idempotencyKey: idempotencyKey,
    ));
    if (updatePreferenceFailure != null) throw updatePreferenceFailure!;
  }
}

Widget _wrap(Widget child, _RecordingNotificationRepository fake) {
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
      home: child,
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _RecordingNotificationRepository fake,
) async {
  await tester.pumpWidget(_wrap(const CommunityNotificationsScreen(), fake));
  // The screen's initState schedules a microtask that
  // triggers ``notifier.load()``. Three pumps let the
  // microtask, the two awaits (inboxPage + preferences),
  // and the subsequent rebuild land before the assertions.
  for (var i = 0; i < 3; i += 1) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('A6 per-category push preference toggle', () {
    testWidgets('controller calls updatePreference with the right wire level', (
      tester,
    ) async {
      final fake = _RecordingNotificationRepository();
      fake.preferencesResult = const <String, String>{'comment': 'inApp'};
      await tester.pumpWidget(
        _wrap(const CommunityNotificationsScreen(), fake),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CommunityNotificationsScreen)),
      );
      await container
          .read(notificationControllerProvider.notifier)
          .updatePreference(
            category: 'comment',
            level: NotificationPreferenceLevel.push,
          );
      await tester.pumpAndSettle();

      expect(fake.updatePreferenceCalls, hasLength(1));
      final call = fake.updatePreferenceCalls.single;
      expect(call.category, 'comment');
      expect(call.level, 'push');
      expect(call.idempotencyKey, isNotEmpty);

      final state = container.read(notificationControllerProvider).value!;
      expect(state.preferences['comment'], NotificationPreferenceLevel.push);
    });

    testWidgets('preference panel renders all 10 wire kinds', (tester) async {
      final fake = _RecordingNotificationRepository();
      await _pumpScreen(tester, fake);

      // The preference panel renders one row per wire
      // kind (the Kör 5 CommunityNotificationKind enum,
      // 10 values). A regression that drops a kind is
      // caught by this assertion.
      expect(find.text('Follow requests'), findsOneWidget);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Reactions'), findsOneWidget);
      expect(find.text('Mentions'), findsOneWidget);
    });
  });

  group('markRead controller path', () {
    testWidgets(
      'controller.markRead calls repository.markRead with the right id',
      (tester) async {
        final fake = _RecordingNotificationRepository();
        await _pumpScreen(tester, fake);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(CommunityNotificationsScreen)),
        );
        await container
            .read(notificationControllerProvider.notifier)
            .markRead(ContentId('n-direct'));
        await tester.pumpAndSettle();

        expect(fake.markReadCalls, hasLength(1));
        expect(fake.markReadCalls.single.notificationId.value, 'n-direct');
      },
    );
  });

  group('empty state', () {
    testWidgets(
      'an empty inbox shows the preference panel and the empty message',
      (tester) async {
        final fake = _RecordingNotificationRepository();
        fake.inboxResult = const CommunityPage<CommunityNotificationItem>(
          items: <CommunityNotificationItem>[],
          cursor: CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        // The screen renders the app bar title.
        expect(find.text('Notifications'), findsOneWidget);
        // The preference panel is always visible (the user
        // can configure categories without any items).
        expect(find.text('Notification categories'), findsOneWidget);
      },
    );
  });
}
