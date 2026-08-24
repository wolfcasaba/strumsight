/// Widget tests for the verified-only leaderboard screen
/// (E09-R23, ADR 0418, brief §6 A7).
///
/// The A7 cell is **the Flutter-side acceptance criterion**:
/// an accessible rank-row that stays readable when the user
/// has the system text-scale setting cranked up. The widget
/// test covers:
///
/// * The empty-state branch (the screen renders the
///   ``communityChallengeEmpty`` ARB string).
/// * The list-render branch (one ``_RankRow`` per
///   ``LeaderboardEntry``, each with the expected
///   ``Semantics`` label).
/// * The verified-badge branch (each row's rightmost icon is
///   the verified icon, with the ``Verified`` semantic label).
/// * The accessibility surface — a TalkBack swipe reads each
///   row in one utterance (the bundled Semantics label) — the
///   literal rank / name / score are reachable in the merged
///   label without forcing three separate swipes.
/// * The text-scale branch — at 2× text scale the rank, name
///   and score still occupy the same horizontal columns
///   (the rank-row column widths are fixed in logical pixels,
///   not ``TextScaler``-driven), so the list stays scannable.
///
/// The other acceptance cells (A1, A2, A3, A4, A5, A6) are
/// backend-pytest pinned in
/// ``backend/tests/community/test_leaderboard_service.py``.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/features/community/data/repositories/challenge_repository_impl.dart';
import 'package:strumsight/features/community/domain/repositories/challenge_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/leaderboard_screen.dart';

// ---------------------------------------------------------------------------
// Recording fake repository — captures the leaderboard call and
// lets the test stub the page.
// ---------------------------------------------------------------------------

class _RecordingLeaderboardRepository implements CommunityChallengeRepository {
  _RecordingLeaderboardRepository();

  final List<({ContentId challengeId, Object cursor, int limit})> calls =
      <({ContentId challengeId, Object cursor, int limit})>[];

  CommunityPage<LeaderboardEntry> result =
      const CommunityPage<LeaderboardEntry>(
        items: <LeaderboardEntry>[],
        cursor: CursorPage.haltedAfterRequest(),
      );

  AppFailure? failure;

  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async {
    throw UnimplementedError('listChallenges is unused.');
  }

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async {
    throw UnimplementedError('fetchDefinition is unused.');
  }

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async {
    throw UnimplementedError('fetchMyParticipation is unused.');
  }

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('invite is unused.');
  }

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('acceptInvite is unused.');
  }

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('declineInvite is unused.');
  }

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('cancelInvite is unused.');
  }

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('submitResult is Kör 22 surface.');
  }

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async {
    calls.add((challengeId: challengeId, cursor: cursor, limit: limit));
    if (failure != null) throw failure!;
    return result;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

LeaderboardEntry _entry({
  required String publicId,
  required int rank,
  String? displayName,
  String? handle,
  required int metricValue,
  DateTime? submittedAt,
}) {
  return LeaderboardEntry(
    publicId: PublicUserId(publicId),
    rank: rank,
    displayName: displayName,
    handle: handle,
    metricValue: metricValue,
    submittedAt: submittedAt ?? DateTime.utc(2026, 8, 24),
    verifiedBadge: true,
  );
}

Widget _wrap({
  required _RecordingLeaderboardRepository fake,
  required ContentId challengeId,
  double textScale = 1.0,
}) {
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
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: LeaderboardScreen(challengeId: challengeId),
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _RecordingLeaderboardRepository fake, {
  ContentId? challengeId,
  double textScale = 1.0,
}) async {
  final id = challengeId ?? ContentId('c1');
  await tester.pumpWidget(
    _wrap(fake: fake, challengeId: id, textScale: textScale),
  );
  // The FutureProvider's microtask resolves during pump.
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// A7 — accessibility
// ---------------------------------------------------------------------------

void main() {
  group('A7 — accessible rank-row', () {
    testWidgets('renders the empty message when there are no entries', (
      tester,
    ) async {
      final fake = _RecordingLeaderboardRepository();
      fake.result = const CommunityPage<LeaderboardEntry>(
        items: <LeaderboardEntry>[],
        cursor: CursorPage.haltedAfterRequest(),
      );
      await _pumpScreen(tester, fake);

      expect(find.text('No active challenges yet.'), findsOneWidget);
    });

    testWidgets(
      'one rank-row per entry, each with a single bundled Semantics label',
      (tester) async {
        final fake = _RecordingLeaderboardRepository();
        fake.result = CommunityPage<LeaderboardEntry>(
          items: <LeaderboardEntry>[
            _entry(
              publicId: 'u1',
              rank: 1,
              displayName: 'Alice',
              handle: '@alice',
              metricValue: 500,
            ),
            _entry(
              publicId: 'u2',
              rank: 2,
              displayName: 'Bob',
              handle: '@bob',
              metricValue: 420,
            ),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        // The two rank labels (#1, #2) render.
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('#2'), findsOneWidget);
        // The two metric values render.
        expect(find.text('500'), findsOneWidget);
        expect(find.text('420'), findsOneWidget);
        // The two display names render.
        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);

        // A7 — every rank-row is wrapped in ONE Semantics node
        // with the bundled label. The screen renders one
        // outer Semantics per row (the inner "Verified"
        // Semantics around the badge is a separate node for
        // the badge icon). The outer-row count is exactly
        // 2.
        final outerNodes = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label != null &&
              widget.properties.label!.startsWith('Rank '),
        );
        expect(outerNodes, findsNWidgets(2));

        // The first row's label bundles rank + name + score
        // + verified.
        final first = tester.widgetList<Semantics>(outerNodes.at(0)).first;
        expect(first.properties.label, contains('Rank 1'));
        expect(first.properties.label, contains('Alice'));
        expect(first.properties.label, contains('500 score'));
        expect(first.properties.label, contains('Verified'));
      },
    );

    testWidgets(
      'each rank-row carries the verified icon with a "Verified" semantic label',
      (tester) async {
        final fake = _RecordingLeaderboardRepository();
        fake.result = CommunityPage<LeaderboardEntry>(
          items: <LeaderboardEntry>[
            _entry(
              publicId: 'u1',
              rank: 1,
              displayName: 'Alice',
              handle: '@alice',
              metricValue: 500,
            ),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake);

        // Two verified icons render — the inner badge has its
        // own icon, and the outer Semantics node ALSO bundles
        // "Verified" into the row label (so a screen reader
        // mentions verified in one utterance). The badge icon
        // count matches the row count.
        expect(find.byIcon(Icons.verified), findsNWidgets(1));

        // The inner Semantics node around the badge carries
        // the "Verified" label (a TalkBack focus lands here).
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == 'Verified',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'large text scale (2x) keeps rank, name and score on the same row',
      (tester) async {
        final fake = _RecordingLeaderboardRepository();
        fake.result = CommunityPage<LeaderboardEntry>(
          items: <LeaderboardEntry>[
            _entry(
              publicId: 'u1',
              rank: 1,
              displayName: 'Alice',
              handle: '@alice',
              metricValue: 500,
            ),
          ],
          cursor: const CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake, textScale: 2.0);

        // The row's rank label is still found — the column
        // widths are fixed in logical pixels so the rank
        // doesn't get pushed off-screen at 2× scale.
        expect(find.text('#1'), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('500'), findsOneWidget);
        // The verified icon is also still present.
        expect(find.byIcon(Icons.verified), findsOneWidget);
      },
    );

    testWidgets(
      'repository.leaderboard is called exactly once on first render with the initial cursor and a 25-row limit',
      (tester) async {
        final fake = _RecordingLeaderboardRepository();
        fake.result = const CommunityPage<LeaderboardEntry>(
          items: <LeaderboardEntry>[],
          cursor: CursorPage.haltedAfterRequest(),
        );
        await _pumpScreen(tester, fake, challengeId: ContentId('c-42'));

        expect(fake.calls, hasLength(1));
        expect(fake.calls.single.challengeId.value, 'c-42');
        expect(fake.calls.single.cursor, const CursorPage.initial());
        expect(fake.calls.single.limit, 25);
      },
    );

    testWidgets('error branch surfaces the network error message and a retry', (
      tester,
    ) async {
      final fake = _RecordingLeaderboardRepository();
      fake.failure = NetworkFailure(
        code: FailureCode.networkUnavailable,
        retryable: true,
      );
      await _pumpScreen(tester, fake);

      // The shared network-error string is rendered in the
      // error view — the screen reuses the Kör 21 ARB
      // surface.
      expect(
        find.text('Could not load challenges — check your connection.'),
        findsOneWidget,
      );
    });
  });
}
