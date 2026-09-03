/// E13-R33 — block/mute local-immediate filtering (A5).
///
/// ADR 0291 §4: blocking/muting hits the follower list LOCALLY and
/// IMMEDIATELY — the user must not keep seeing the person they're
/// protecting themselves from just because the server hasn't confirmed the
/// action yet. `followers_screen.dart` removes the row from its own list
/// FIRST (before the repository call is even awaited); the repository call
/// itself is best-effort.
///
/// The repository fake's `block`/`mute` methods return a [Completer]-backed
/// Future that is NEVER completed during the test — proving the row
/// disappears without waiting on (or requiring) a server response.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/design_system/components/surfaces/ss_card.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/social_graph_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/followers_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Widget _harness(SocialGraphRepository repo) {
  return ProviderScope(
    overrides: [socialGraphRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      // R2 (§0.0): FollowersScreen's SsCard now reads the design-system
      // theme extensions — a themeless MaterialApp null-check crashes
      // (L593-class defect). CommunityThemeScope also merges these in
      // internally (R6), but the round's own instruction is to make the
      // harness carry the real runtime theme regardless.
      theme: SsLightTheme.data(),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: FollowersScreen(
        profileId: PublicUserId('user-viewer'),
        mode: FollowersMode.followers,
      ),
    ),
  );
}

/// A3 (§6/§0.0/R5) variant harness: same theme/screen, plus a controllable
/// locale and textScale so the migrated screen's overflow behaviour can be
/// measured at the required threshold pair.
Widget _harnessVariant(
  SocialGraphRepository repo, {
  required double textScale,
  required Locale locale,
}) {
  return ProviderScope(
    overrides: [socialGraphRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: SsLightTheme.data(),
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FollowersScreen(
        profileId: PublicUserId('user-viewer'),
        mode: FollowersMode.followers,
      ),
    ),
  );
}

CommunityProfile _profile(String id, String handle, String displayName) {
  return CommunityProfile(
    userId: PublicUserId(id),
    handle: CommunityHandle(handle),
    displayName: displayName,
    visibility: ProfileVisibility.followers,
    avatarUrl: null,
    bio: null,
    skillInterests: const <String>[],
    badges: const <String>[],
    relationship: CommunityRelationshipToViewer.notRelated,
    createdAt: DateTime.utc(2026, 8, 1),
  );
}

/// Records every block/mute call but never resolves them during the test —
/// this is the deliberate "server never confirms" scenario A5 measures.
class _StuckSocialGraphRepository implements SocialGraphRepository {
  _StuckSocialGraphRepository(this._page);

  final CommunityPage<CommunityProfile> _page;
  final List<PublicUserId> blockCalls = <PublicUserId>[];
  final List<PublicUserId> muteCalls = <PublicUserId>[];

  @override
  Future<CommunityPage<CommunityProfile>> followersPage({
    required PublicUserId userId,
    required Object cursor,
  }) async => _page;

  @override
  Future<CommunityPage<CommunityProfile>> followingPage({
    required PublicUserId userId,
    required Object cursor,
  }) async => _page;

  @override
  Future<void> block({
    required PublicUserId target,
    required String idempotencyKey,
  }) {
    blockCalls.add(target);
    return Completer<void>().future; // never completes
  }

  @override
  Future<void> mute({
    required PublicUserId target,
    required String idempotencyKey,
  }) {
    muteCalls.add(target);
    return Completer<void>().future; // never completes
  }

  @override
  Future<ContentId> follow({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> unfollow({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> removeFollower({
    required PublicUserId follower,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> acceptFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> declineFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> unblock({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> unmute({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityProfile>> blockedProfilesPage({
    required Object cursor,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityProfile>> mutedProfilesPage({
    required Object cursor,
  }) => throw UnsupportedError('not used in this test');
}

void main() {
  testWidgets(
    'A5 — blocking a follower removes their row immediately, before the '
    'repository call resolves',
    (tester) async {
      final alice = _profile('user-alice', 'alice', 'Alice');
      final bob = _profile('user-bob', 'bob', 'Bob');
      final repo = _StuckSocialGraphRepository(
        CommunityPage<CommunityProfile>(
          items: <CommunityProfile>[alice, bob],
          cursor: const CursorPage.haltedAfterRequest(),
        ),
      );

      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      await tester.tap(find.byKey(const Key('follower-block-user-alice')));
      // A SINGLE frame — NOT pumpAndSettle. The repository's Future for
      // this call never resolves, so if the row's removal depended on
      // waiting for it, this pump would still show Alice.
      await tester.pump();

      expect(
        find.text('Alice'),
        findsNothing,
        reason:
            'A5 violation: the row must disappear locally BEFORE the '
            'server confirms the block',
      );
      expect(find.text('Bob'), findsOneWidget, reason: 'Bob was not blocked');
      // The repository call was still issued (best-effort) — it just
      // hasn't (and, in this test, never will) resolve.
      expect(repo.blockCalls, <PublicUserId>[PublicUserId('user-alice')]);
    },
  );

  testWidgets(
    'A5 — muting a follower removes their row immediately, before the '
    'repository call resolves',
    (tester) async {
      final alice = _profile('user-alice', 'alice', 'Alice');
      final bob = _profile('user-bob', 'bob', 'Bob');
      final repo = _StuckSocialGraphRepository(
        CommunityPage<CommunityProfile>(
          items: <CommunityProfile>[alice, bob],
          cursor: const CursorPage.haltedAfterRequest(),
        ),
      );

      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('follower-mute-user-bob')));
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget, reason: 'Alice was not muted');
      expect(
        find.text('Bob'),
        findsNothing,
        reason:
            'A5 violation: the row must disappear locally BEFORE the '
            'server confirms the mute',
      );
      expect(repo.muteCalls, <PublicUserId>[PublicUserId('user-bob')]);
    },
  );

  // A3 (§6/§0.0/R5) — the migrated screen must not overflow at the required
  // 1.5/2.0 textScale threshold pair, in both `en` and `hu`.
  group('A3 — textScale variant matrix (1.5 / 2.0 × en / hu)', () {
    CommunityPage<CommunityProfile> page() {
      final alice = _profile('user-alice', 'alice', 'Alice');
      final bob = _profile('user-bob', 'bob', 'Bob');
      return CommunityPage<CommunityProfile>(
        items: <CommunityProfile>[alice, bob],
        cursor: const CursorPage.haltedAfterRequest(),
      );
    }

    for (final textScale in [1.5, 2.0]) {
      for (final locale in [const Locale('en'), const Locale('hu')]) {
        testWidgets('renders without overflow at $textScale ($locale)', (
          tester,
        ) async {
          final repo = _StuckSocialGraphRepository(page());
          await tester.pumpWidget(
            _harnessVariant(repo, textScale: textScale, locale: locale),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the follower row uses the design-system SsCard', (
      tester,
    ) async {
      final repo = _StuckSocialGraphRepository(page());
      await tester.pumpWidget(
        _harnessVariant(repo, textScale: 1.0, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SsCard), findsWidgets);
    });
  });
}
