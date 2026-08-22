/// E09-R08 — Blocked / Muted screen widget tests.
///
/// Covers the §6 / §D6 acceptance for the safety-relationships
/// screen — its own Riverpod state lives in the screen file (the
/// ``application/controllers/`` tree is OUT of scope, ADR 0402
/// §D6).
///
/// The cells:
///
/// * A — Blocked tab renders the caller's blocked list with an
///   "Unblock" action that fires the repository's ``unblock``.
/// * A — Muted tab renders the caller's muted list with an
///   "Unmute" action that fires the repository's ``unmute``.
/// * A — an empty list renders the empty-state copy (no spinner,
///   no error).
/// * F — the unblock / unmute optimistic local removal: a tapped
///   "Unblock" removes the row from the visible list before any
///   page reload.
///
/// A real ``HttpSocialGraphRepository`` is mounted via the
/// ``socialGraphRepositoryProvider`` override, but the API is
/// driven by a recording ``HttpClientAdapter`` (the same pattern
/// the §F3 group uses for the follow endpoints).
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/community_profile_repository.dart';
import 'package:strumsight/features/community/domain/repositories/social_graph_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/safety_relationships_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({required this.onFetch});

  final _CannedResponse Function(RequestOptions options) onFetch;
  final List<RequestOptions> captured = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(options);
    final canned = onFetch(options);
    return ResponseBody.fromString(
      canned.body,
      canned.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CannedResponse {
  const _CannedResponse({required this.body, required this.status});
  final String body;
  final int status;
}

class _FakeCommunityProfileRepository implements CommunityProfileRepository {
  _FakeCommunityProfileRepository(this.profile);

  final CommunityProfile profile;

  @override
  Future<CommunityProfile?> fetchMyProfile() async => profile;

  @override
  Future<CommunityProfile> fetchById(PublicUserId userId) async {
    if (userId == profile.userId) return profile;
    return CommunityProfile(
      userId: userId,
      handle: CommunityHandle('h-${userId.value.substring(0, 6)}'),
      displayName: 'Resolved ${userId.value.substring(0, 6)}',
      visibility: ProfileVisibility.public,
      avatarUrl: null,
      bio: null,
      skillInterests: const <String>[],
      badges: const <String>[],
      relationship: CommunityRelationshipToViewer.notRelated,
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  Future<CommunityProfile?> fetchByHandle(CommunityHandle handle) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityProfile>> searchProfiles({
    required String query,
    required Object cursor,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<AppResult<CommunityProfile>> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  }) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) =>
      throw UnsupportedError('not used in this test');
}

HttpSocialGraphRepository _buildRepo(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HttpSocialGraphRepository(ApiClient(dio));
}

CommunityProfile _makeProfile(String suffix) {
  return CommunityProfile(
    userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5$suffix'),
    handle: CommunityHandle('handle-$suffix'),
    displayName: 'Profile $suffix',
    visibility: ProfileVisibility.public,
    avatarUrl: null,
    bio: null,
    skillInterests: const <String>[],
    badges: const <String>[],
    relationship: CommunityRelationshipToViewer.notRelated,
    createdAt: DateTime.utc(2026),
  );
}

Widget _harness({
  required SocialGraphRepository repo,
  required CommunityProfileRepository profileRepo,
}) {
  return ProviderScope(
    overrides: <Override>[
      socialGraphRepositoryProvider.overrideWithValue(repo),
      communityProfileRepositoryProvider.overrideWithValue(profileRepo),
    ],
    child: const MaterialApp(
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SafetyRelationshipsScreen(),
    ),
  );
}

void main() {
  testWidgets(
    'Blocked tab renders the caller's blocked list with Unblock action',
    (tester) async {
      final adapter = _ScriptedAdapter(
        onFetch: (_) => const _CannedResponse(
          body:
              '{"public_ids":["01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01",'
              '"01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a02"],'
              '"next_cursor":null}',
          status: 200,
        ),
      );
      final repo = _buildRepo(adapter);
      // Replace later unblock responses.
      int unblockCallCount = 0;
      adapter.onFetch = (options) {
        if (options.method == 'DELETE' &&
            options.path.contains('/block') &&
            options.path.contains('idempotency_key=')) {
          unblockCallCount++;
          return const _CannedResponse(body: '{}', status: 200);
        }
        return const _CannedResponse(
          body:
              '{"public_ids":["01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01",'
              '"01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a02"],'
              '"next_cursor":null}',
          status: 200,
        );
      };

      await tester.pumpWidget(
        _harness(
          repo: repo,
          profileRepo: _FakeCommunityProfileRepository(
            _makeProfile('a00'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The Blocked tab is the initial tab — it must show the
      // resolved profile rows (the fetchById fallback fills in a
      // displayName when the placeholder is not enough).
      expect(find.text('Blocked'), findsWidgets);
      expect(find.text('Muted'), findsOneWidget);

      // The two rows are present, identified by the suffix of
      // their public_id (the fake profile repo maps suffix-a01 →
      // "Resolved a01"). The fetchById composes the title from
      // the suffix.
      expect(find.textContaining('Resolved a01'), findsOneWidget);
      expect(find.textContaining('Resolved a02'), findsOneWidget);

      // Tap "Unblock" on the first row.
      await tester.tap(find.text('Unblock').first);
      await tester.pumpAndSettle();

      expect(unblockCallCount, 1, reason: 'unblock should fire on tap');
      // Optimistic removal — the resolved row disappears from the
      // visible list.
      expect(find.textContaining('Resolved a01'), findsNothing);
      expect(find.textContaining('Resolved a02'), findsOneWidget);
    },
  );

  testWidgets(
    'Muted tab renders the caller's muted list with Unmute action',
    (tester) async {
      final adapter = _ScriptedAdapter(
        onFetch: (_) => const _CannedResponse(
          body:
              '{"public_ids":["01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5b01"],'
              '"next_cursor":null}',
          status: 200,
        ),
      );
      final repo = _buildRepo(adapter);
      int unmuteCallCount = 0;
      adapter.onFetch = (options) {
        if (options.method == 'DELETE' &&
            options.path.contains('/mute') &&
            options.path.contains('idempotency_key=')) {
          unmuteCallCount++;
          return const _CannedResponse(body: '{}', status: 200);
        }
        return const _CannedResponse(
          body:
              '{"public_ids":["01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5b01"],'
              '"next_cursor":null}',
          status: 200,
        );
      };

      await tester.pumpWidget(
        _harness(
          repo: repo,
          profileRepo: _FakeCommunityProfileRepository(
            _makeProfile('b00'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to the Muted tab.
      await tester.tap(find.text('Muted'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Resolved b01'), findsOneWidget);

      await tester.tap(find.text('Unmute'));
      await tester.pumpAndSettle();

      expect(unmuteCallCount, 1, reason: 'unmute should fire on tap');
      expect(find.textContaining('Resolved b01'), findsNothing);
    },
  );

  testWidgets(
    'Empty list renders the empty-state copy (no spinner, no error)',
    (tester) async {
      final adapter = _ScriptedAdapter(
        onFetch: (_) => const _CannedResponse(
          body: '{"public_ids":[],"next_cursor":null}',
          status: 200,
        ),
      );
      final repo = _buildRepo(adapter);

      await tester.pumpWidget(
        _harness(
          repo: repo,
          profileRepo: _FakeCommunityProfileRepository(
            _makeProfile('c00'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("You haven't blocked anyone yet."),
        findsOneWidget,
      );
    },
  );
}
