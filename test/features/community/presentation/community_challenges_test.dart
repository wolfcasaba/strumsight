/// Community challenges widget tests (E09-R21, ADR 0415, brief
/// §6 A6).
///
/// The screen + controller are exercised against a recording
/// fake repository. The A6 cell — the deep-link Play action
/// only renders on Practice / Song / PersonalBest challenge
/// types — is the only Flutter-side acceptance cell (the A1-A5
/// + A7 cells are backend-pytest pinned, see
/// ``backend/tests/community/test_challenge_invite_service.py``).
///
/// The widget also covers:
/// * the empty-state branch (no challenges);
/// * the list-render branch (one row per challenge definition);
/// * the controller-mediated accept / decline / cancel calls
///   landing the right repository method with the right
///   arguments;
/// * the failure-rollback branch (a failed ``acceptInvite``
///   surfaces the error and leaves the row in place).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/features/community/application/controllers/challenge_controller.dart';
import 'package:strumsight/features/community/domain/entities/community_challenge.dart';
import 'package:strumsight/features/community/domain/repositories/challenge_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/community_challenges_screen.dart';

// ---------------------------------------------------------------------------
// Recording fake repository — captures every call the controller
// makes and lets the test stub specific outcomes.
// ---------------------------------------------------------------------------

class _RecordingChallengeRepository implements CommunityChallengeRepository {
  _RecordingChallengeRepository();

  final List<
    ({ContentId challengeId, PublicUserId target, String idempotencyKey})
  >
  inviteCalls =
      <({ContentId challengeId, PublicUserId target, String idempotencyKey})>[];
  final List<({ContentId inviteId, String idempotencyKey})> acceptCalls =
      <({ContentId inviteId, String idempotencyKey})>[];
  final List<({ContentId inviteId, String idempotencyKey})> declineCalls =
      <({ContentId inviteId, String idempotencyKey})>[];
  final List<({ContentId inviteId, PublicUserId target, String idempotencyKey})>
  cancelCalls =
      <({ContentId inviteId, PublicUserId target, String idempotencyKey})>[];
  final List<({Object cursor, int limit})> listCalls =
      <({Object cursor, int limit})>[];

  CommunityPage<CommunityChallengeDefinition> listResult =
      const CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[],
        cursor: CursorPage.haltedAfterRequest(),
      );

  AppFailure? acceptFailure;
  AppFailure? declineFailure;

  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async {
    listCalls.add((cursor: cursor, limit: limit));
    return listResult;
  }

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async {
    throw UnimplementedError('fetchDefinition is unused in the widget tests.');
  }

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async {
    throw UnimplementedError(
      'fetchMyParticipation is unused in the widget tests.',
    );
  }

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    inviteCalls.add((
      challengeId: challengeId,
      target: target,
      idempotencyKey: idempotencyKey,
    ));
  }

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {
    acceptCalls.add((inviteId: challengeId, idempotencyKey: idempotencyKey));
    if (acceptFailure != null) throw acceptFailure!;
  }

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {
    declineCalls.add((inviteId: challengeId, idempotencyKey: idempotencyKey));
    if (declineFailure != null) throw declineFailure!;
  }

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    cancelCalls.add((
      inviteId: challengeId,
      target: target,
      idempotencyKey: idempotencyKey,
    ));
  }

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError(
      'submitResult is Kör 22 scope; the Kör 21 surface is invite-only.',
    );
  }

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async {
    throw UnimplementedError(
      'leaderboard is Kör 23 scope; the Kör 21 surface is invite-only.',
    );
  }
}

Widget _wrap(Widget child, _RecordingChallengeRepository fake) {
  return ProviderScope(
    overrides: [communityChallengeRepositoryProvider.overrideWithValue(fake)],
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
  _RecordingChallengeRepository fake,
) async {
  await tester.pumpWidget(_wrap(const CommunityChallengesScreen(), fake));
  for (var i = 0; i < 3; i += 1) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

CommunityChallengeDefinition _challenge({
  required String id,
  required ChallengeType type,
  DateTime? startsAt,
  DateTime? endsAt,
}) {
  final start = startsAt ?? DateTime.utc(2026, 1, 1);
  final end = endsAt ?? DateTime.utc(2026, 1, 8);
  return CommunityChallengeDefinition(
    id: ContentId(id),
    version: 1,
    type: type,
    metric: 'score',
    difficulty: 1,
    startsAt: start,
    endsAt: end,
    authorId: PublicUserId('author-id'),
    clubId: null,
  );
}

void main() {
  group('A6 deep-link action', () {
    testWidgets('personalBest challenge shows the deep-link Play action', (
      tester,
    ) async {
      final fake = _RecordingChallengeRepository();
      fake.listResult = CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[
          _challenge(id: 'c1', type: ChallengeType.personalBest),
        ],
        cursor: const CursorPage.haltedAfterRequest(),
      );
      await _pumpScreen(tester, fake);

      // The deep-link Play icon is present — the row
      // exposes the A6 mapping for ``personalBest``.
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets(
      'friends / club / dailyCommunity / periodicGlobal challenges do NOT show a deep link',
      (tester) async {
        final fake = _RecordingChallengeRepository();
        fake.listResult = CommunityPage<CommunityChallengeDefinition>(
          items: <CommunityChallengeDefinition>[
            _challenge(id: 'c1', type: ChallengeType.friends),
            _challenge(id: 'c2', type: ChallengeType.club),
            _challenge(id: 'c3', type: ChallengeType.dailyCommunity),
            _challenge(id: 'c4', type: ChallengeType.periodicGlobal),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        // No deep-link Play icons — these types resolve to
        // ``ChallengeDeepLinkTarget.none``.
        expect(find.byIcon(Icons.play_arrow), findsNothing);
      },
    );
  });

  group('controller-mediated invite actions', () {
    testWidgets(
      'controller.acceptInvite calls repository.acceptInvite with the right id',
      (tester) async {
        final fake = _RecordingChallengeRepository();
        fake.listResult = CommunityPage<CommunityChallengeDefinition>(
          items: <CommunityChallengeDefinition>[
            _challenge(id: 'inv-1', type: ChallengeType.friends),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(CommunityChallengesScreen)),
        );
        await container
            .read(challengeControllerProvider.notifier)
            .acceptInvite(ContentId('inv-1'));
        await tester.pumpAndSettle();

        expect(fake.acceptCalls, hasLength(1));
        expect(fake.acceptCalls.single.inviteId.value, 'inv-1');
        expect(fake.acceptCalls.single.idempotencyKey, isNotEmpty);
      },
    );

    testWidgets('controller.declineInvite calls repository.declineInvite', (
      tester,
    ) async {
      final fake = _RecordingChallengeRepository();
      fake.listResult = CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[
          _challenge(id: 'inv-2', type: ChallengeType.friends),
        ],
        cursor: const CursorPage.haltedAfterRequest(),
      );
      await _pumpScreen(tester, fake);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CommunityChallengesScreen)),
      );
      await container
          .read(challengeControllerProvider.notifier)
          .declineInvite(ContentId('inv-2'));
      await tester.pumpAndSettle();

      expect(fake.declineCalls, hasLength(1));
      expect(fake.declineCalls.single.inviteId.value, 'inv-2');
    });

    testWidgets(
      'controller.cancelInvite calls repository.cancelInvite with the right target',
      (tester) async {
        final fake = _RecordingChallengeRepository();
        fake.listResult = CommunityPage<CommunityChallengeDefinition>(
          items: <CommunityChallengeDefinition>[
            _challenge(id: 'inv-3', type: ChallengeType.friends),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(CommunityChallengesScreen)),
        );
        await container
            .read(challengeControllerProvider.notifier)
            .cancelInvite(
              invitePublicId: ContentId('inv-3'),
              target: PublicUserId('target-1'),
            );
        await tester.pumpAndSettle();

        expect(fake.cancelCalls, hasLength(1));
        expect(fake.cancelCalls.single.inviteId.value, 'inv-3');
        expect(fake.cancelCalls.single.target.value, 'target-1');
      },
    );

    testWidgets('accept failure surfaces the error and keeps the row visible', (
      tester,
    ) async {
      final fake = _RecordingChallengeRepository();
      fake.acceptFailure = NetworkFailure(
        code: FailureCode.networkBadResponse,
        retryable: false,
      );
      fake.listResult = CommunityPage<CommunityChallengeDefinition>(
        items: <CommunityChallengeDefinition>[
          _challenge(id: 'inv-4', type: ChallengeType.friends),
        ],
        cursor: const CursorPage.haltedAfterRequest(),
      );
      await _pumpScreen(tester, fake);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CommunityChallengesScreen)),
      );
      await container
          .read(challengeControllerProvider.notifier)
          .acceptInvite(ContentId('inv-4'));
      await tester.pumpAndSettle();

      final state = container.read(challengeControllerProvider).value!;
      expect(state.lastError, isA<NetworkFailure>());
      // The row is still visible (the controller does NOT
      // remove it on failure — the server is the source of
      // truth, the optimistic UI is the controller's
      // own invariant).
      expect(find.text('score'), findsOneWidget);
    });
  });

  group('list / empty state', () {
    testWidgets('empty list shows the empty message', (tester) async {
      final fake = _RecordingChallengeRepository();
      await _pumpScreen(tester, fake);

      expect(find.text('Challenges'), findsOneWidget);
      expect(find.text('No active challenges yet.'), findsOneWidget);
    });

    testWidgets(
      'list with one row shows the challenge metric and the window label',
      (tester) async {
        final fake = _RecordingChallengeRepository();
        fake.listResult = CommunityPage<CommunityChallengeDefinition>(
          items: <CommunityChallengeDefinition>[
            _challenge(
              id: 'c1',
              type: ChallengeType.friends,
              startsAt: DateTime.utc(2026, 1, 1),
              endsAt: DateTime.utc(2026, 1, 8),
            ),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        expect(find.text('score'), findsOneWidget);
        // The window label is templated — the assertion
        // checks the prefix the screen renders.
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != null &&
                widget.data!.startsWith('Window:'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
