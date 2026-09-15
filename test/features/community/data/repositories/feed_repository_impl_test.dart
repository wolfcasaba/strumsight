/// Feed repository wiring tests — the ``HttpCommunityFeedRepository``
/// over the backend ``GET /community/feed`` router (``feed.py``).
///
/// Pins the wire format the same way the E09-R08 social-graph tests
/// do (a scripted ``HttpClientAdapter``, no network):
///
/// * the path + query string (``page_size`` — the backend's name, not
///   ``limit`` — and the forwarded opaque ``cursor``);
/// * the ``FeedPage`` envelope decode: ``items`` → ``CommunityPost``
///   rows (snake_case ``artifact_payload`` → the typed
///   ``ShareArtifact``; a missing artifact → the Unfilled fallback),
///   ``next_cursor`` → ``CursorPage.continued`` /
///   ``haltedAfterRequest``;
/// * the error taxonomy (5xx / 401 / 404 / malformed body) — every
///   failure is a thrown ``AppFailure``, never a Dio type;
/// * the two routes the backend does not have (``profilePosts`` /
///   ``clubPinned``) throw the typed ``ConfigurationFailure`` without
///   touching the transport.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/dto/post_dto.dart';
import 'package:strumsight/features/community/data/repositories/feed_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';

class _CannedResponse {
  const _CannedResponse({required this.body, required this.status});
  final String body;
  final int status;
}

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

HttpCommunityFeedRepository _buildRepo(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HttpCommunityFeedRepository(ApiClient(dio));
}

_ScriptedAdapter _adapterWith(String body, {int status = 200}) {
  return _ScriptedAdapter(
    onFetch: (_) => _CannedResponse(body: body, status: status),
  );
}

const String _postA = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa0';
const String _postB = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa1';
const String _authorA = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01';

/// The backend ``ShareArtifactEnvelope`` shape — snake_case keys under
/// an ``artifact`` wrapper (``test_post_service.py::
/// test_artifact_persists_through_round_trip``).
Map<String, Object?> _practiceEnvelope() => <String, Object?>{
  'artifact': <String, Object?>{
    'type': 'practiceSummary',
    'schema_version': 1,
    'source_id': 'practice-1',
    'created_at': '2026-08-23T12:00:00Z',
    'active_seconds': 90,
    'paused_seconds': 10,
    'attempt_count': 5,
    'finish_reason_code': 'completed',
    'best_score': 0.85,
    'coaching_codes': <String>['strongDownBeats'],
  },
};

/// One ``FeedPostItem`` / ``PostOut`` row.
Map<String, Object?> _postJson({
  required String publicId,
  String audience = 'public',
  String body = 'Fixture body text.',
  Map<String, Object?>? artifactPayload,
  String moderationState = 'visible',
  String? deletedAt,
}) => <String, Object?>{
  'public_id': publicId,
  'author_public_id': _authorA,
  'audience': audience,
  'club_id': null,
  'body': body,
  'artifact_type': artifactPayload == null ? null : 'practiceSummary',
  'artifact_schema_version': artifactPayload == null ? null : 1,
  'artifact_payload': artifactPayload,
  'moderation_state': moderationState,
  'created_at': '2026-08-23T12:00:00Z',
  'resource_version': '2026-08-23T12:00:00Z',
  'deleted_at': deletedAt,
};

String _pageJson(List<Map<String, Object?>> items, {String? nextCursor}) =>
    jsonEncode(<String, Object?>{'items': items, 'next_cursor': nextCursor});

void main() {
  group('followingFeed() wire format', () {
    test('GETs /community/feed with page_size and no cursor on the '
        'initial page', () async {
      final adapter = _adapterWith(_pageJson(const []));
      final repo = _buildRepo(adapter);

      await repo.followingFeed(cursor: const CursorPage.initial(), limit: 20);

      expect(adapter.captured, hasLength(1));
      final options = adapter.captured.single;
      expect(options.method, 'GET');
      expect(options.path, '/community/feed?page_size=20');
      expect(options.uri.queryParameters['page_size'], '20');
      expect(options.uri.queryParameters.containsKey('cursor'), isFalse);
    });

    test('forwards a continued cursor verbatim', () async {
      final adapter = _adapterWith(_pageJson(const []));
      final repo = _buildRepo(adapter);

      await repo.followingFeed(
        cursor: const CursorPage.continued('opaque token/1'),
        limit: 20,
      );

      final options = adapter.captured.single;
      expect(options.uri.queryParameters['cursor'], 'opaque token/1');
      expect(options.uri.queryParameters['page_size'], '20');
    });
  });

  group('followingFeed() page decode', () {
    test('maps every FeedPostItem to a CommunityPost and next_cursor to '
        'CursorPage.continued', () async {
      final adapter = _adapterWith(
        _pageJson(<Map<String, Object?>>[
          _postJson(
            publicId: _postA,
            audience: 'followers',
            artifactPayload: _practiceEnvelope(),
          ),
          _postJson(publicId: _postB, body: 'no artifact'),
        ], nextCursor: 'cursor-2'),
      );
      final repo = _buildRepo(adapter);

      final page = await repo.followingFeed(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      expect(page.items, hasLength(2));
      expect(page.cursor, const CursorPage.continued('cursor-2'));
      expect(page.isHaltedAfterRequest, isFalse);

      final first = page.items[0];
      expect(first.id, ContentId(_postA));
      expect(first.authorId, PublicUserId(_authorA));
      expect(first.audience, CommunityAudience.followers);
      expect(first.body, 'Fixture body text.');
      expect(first.moderationState, ModerationState.visible);
      expect(first.createdAt, DateTime.utc(2026, 8, 23, 12));
      expect(first.editedAt, isNull);
      // Counts / viewer state are not on the wire — zero / empty, not
      // invented.
      expect(first.counts.reactionCount, 0);
      expect(first.counts.commentCount, 0);
      expect(first.counts.bookmarkCount, 0);
      expect(first.viewerState, const CommunityViewerPostState.empty());
      // The snake_case envelope decodes to the typed artifact.
      final artifact = first.artifact;
      expect(artifact, isA<PracticeSummaryArtifact>());
      artifact as PracticeSummaryArtifact;
      expect(artifact.activeSeconds, 90);
      expect(artifact.pausedSeconds, 10);
      expect(artifact.attemptCount, 5);
      expect(artifact.finishReasonCode, 'completed');
      expect(artifact.bestScore, 0.85);
      expect(artifact.coachingCodes, <String>['strongDownBeats']);
      expect(artifact.sourceId, 'practice-1');

      final second = page.items[1];
      expect(second.id, ContentId(_postB));
      expect(second.body, 'no artifact');
      expect(second.artifact, isA<UnfilledCommunityShareArtifact>());
    });

    test('next_cursor null becomes haltedAfterRequest even with items — '
        'the controller reads it as end-of-feed', () async {
      final adapter = _adapterWith(
        _pageJson(<Map<String, Object?>>[_postJson(publicId: _postA)]),
      );
      final repo = _buildRepo(adapter);

      final page = await repo.followingFeed(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      expect(page.items, hasLength(1));
      expect(page.cursor, const CursorPage.haltedAfterRequest());
      expect(page.isHaltedAfterRequest, isTrue);
    });

    test('an unknown artifact type falls back to the Unfilled artifact '
        'instead of failing the whole page (A5)', () async {
      final adapter = _adapterWith(
        _pageJson(<Map<String, Object?>>[
          _postJson(
            publicId: _postA,
            artifactPayload: <String, Object?>{
              'artifact': <String, Object?>{
                'type': 'thisIsNotAValidType',
                'schema_version': 1,
                'source_id': 'x',
                'created_at': '2026-08-23T12:00:00Z',
              },
            },
          ),
        ]),
      );
      final repo = _buildRepo(adapter);

      final page = await repo.followingFeed(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      expect(page.items.single.artifact, isA<UnfilledCommunityShareArtifact>());
    });

    test('deleted_at / removed moderation decode to a removed '
        'tombstone', () async {
      final adapter = _adapterWith(
        _pageJson(<Map<String, Object?>>[
          _postJson(publicId: _postA, moderationState: 'removed'),
          _postJson(publicId: _postB, deletedAt: '2026-08-24T12:00:00Z'),
        ]),
      );
      final repo = _buildRepo(adapter);

      final page = await repo.followingFeed(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      expect(page.items[0].moderationState, ModerationState.removed);
      expect(page.items[1].moderationState, ModerationState.removed);
    });
  });

  group('followingFeed() error mapping', () {
    test('5xx surfaces as a retryable '
        'NetworkFailure(network.server)', () async {
      final adapter = _adapterWith('{"detail":"boom"}', status: 503);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.followingFeed(cursor: const CursorPage.initial(), limit: 20),
        throwsA(
          isA<NetworkFailure>()
              .having((f) => f.code, 'code', FailureCode.networkServer)
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('401 surfaces as '
        'AuthenticationFailure(auth.session_expired)', () async {
      final adapter = _adapterWith('{"detail":"nope"}', status: 401);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.followingFeed(cursor: const CursorPage.initial(), limit: 20),
        throwsA(
          isA<AuthenticationFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.authSessionExpired,
          ),
        ),
      );
    });

    test('404 (no community profile) surfaces as a non-retryable '
        'NetworkFailure(network.bad_response)', () async {
      final adapter = _adapterWith('{"detail":"no profile"}', status: 404);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.followingFeed(cursor: const CursorPage.initial(), limit: 20),
        throwsA(
          isA<NetworkFailure>()
              .having((f) => f.code, 'code', FailureCode.networkBadResponse)
              .having((f) => f.retryable, 'retryable', isFalse),
        ),
      );
    });

    test('a malformed envelope (items not a list) surfaces as '
        'NetworkFailure(network.bad_response), not a '
        'FormatException', () async {
      final adapter = _adapterWith('{"items":"nope","next_cursor":null}');
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.followingFeed(cursor: const CursorPage.initial(), limit: 20),
        throwsA(
          isA<NetworkFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.networkBadResponse,
          ),
        ),
      );
    });

    test('a row with an unknown audience fails the page (contract '
        'violation, not a silent widen to public)', () async {
      final adapter = _adapterWith(
        _pageJson(<Map<String, Object?>>[
          _postJson(publicId: _postA, audience: 'everyone'),
        ]),
      );
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.followingFeed(cursor: const CursorPage.initial(), limit: 20),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('routes the backend does not have', () {
    test('profilePosts() throws the typed ConfigurationFailure without a '
        'request', () async {
      final adapter = _adapterWith('{}');
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.profilePosts(
          userId: PublicUserId(_authorA),
          cursor: const CursorPage.initial(),
          limit: 20,
        ),
        throwsA(
          isA<ConfigurationFailure>().having(
            (f) => f.cause,
            'cause',
            isA<UnsupportedError>(),
          ),
        ),
      );
      expect(adapter.captured, isEmpty);
    });

    test('clubPinned() throws the typed ConfigurationFailure without a '
        'request', () async {
      final adapter = _adapterWith('{}');
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.clubPinned(
          clubId: ContentId('club-1'),
          cursor: const CursorPage.initial(),
          limit: 20,
        ),
        throwsA(isA<ConfigurationFailure>()),
      );
      expect(adapter.captured, isEmpty);
    });
  });

  group('factory + disabled fallback', () {
    test('createCommunityFeedRepository(null) is the disabled stand-in', () {
      expect(
        createCommunityFeedRepository(null),
        isA<DisabledCommunityFeedRepository>(),
      );
    });

    test('createCommunityFeedRepository(client) is the HTTP impl', () {
      final client = ApiClient(Dio()..httpClientAdapter = _adapterWith('{}'));
      expect(
        createCommunityFeedRepository(client),
        isA<HttpCommunityFeedRepository>(),
      );
    });

    test('the disabled repository throws ConfigurationFailure', () async {
      const repo = DisabledCommunityFeedRepository();
      await expectLater(
        repo.followingFeed(cursor: const CursorPage.initial(), limit: 20),
        throwsA(isA<ConfigurationFailure>()),
      );
    });
  });

  group('artifact wire casing (post_dto.dart)', () {
    test('communityArtifactToWire wraps and snake_cases a toJson() map', () {
      final artifact = PracticeSummaryArtifact(
        schemaVersion: shareArtifactSchemaVersion,
        sourceId: 'practice-1',
        createdAt: DateTime.utc(2026, 8, 23, 12),
        activeSeconds: 90,
        pausedSeconds: 10,
        attemptCount: 5,
        finishReasonCode: 'completed',
        bestScore: 0.85,
        coachingCodes: const <String>['strongDownBeats'],
      );

      final wire = communityArtifactToWire(artifact.toJson());

      final inner = wire['artifact'] as Map<String, Object?>;
      expect(inner['type'], 'practiceSummary');
      expect(inner['schema_version'], 1);
      expect(inner['source_id'], 'practice-1');
      expect(inner['created_at'], '2026-08-23T12:00:00.000Z');
      expect(inner['active_seconds'], 90);
      expect(inner['finish_reason_code'], 'completed');
      expect(inner['coaching_codes'], <String>['strongDownBeats']);
      // Only KEYS are re-cased — the string values stay verbatim.
      expect(inner.containsKey('schemaVersion'), isFalse);
    });

    test('communityArtifactFromWire round-trips a snake_case envelope '
        'back into the typed ShareArtifact', () {
      final original = PracticeSummaryArtifact(
        schemaVersion: shareArtifactSchemaVersion,
        sourceId: 'practice-1',
        createdAt: DateTime.utc(2026, 8, 23, 12),
        activeSeconds: 90,
        pausedSeconds: 10,
        attemptCount: 5,
        finishReasonCode: 'completed',
        bestScore: 0.85,
        coachingCodes: const <String>['strongDownBeats'],
      );

      final wire = communityArtifactToWire(original.toJson());
      final json = communityArtifactFromWire(wire);

      expect(json, isNotNull);
      expect(ShareArtifact.fromJson(json), equals(original));
    });

    test('nested artifact lists are re-cased too (analysis metrics)', () {
      final original = AnalysisImprovementArtifact(
        schemaVersion: shareArtifactSchemaVersion,
        sourceId: 'analysis-1',
        createdAt: DateTime.utc(2026, 8, 23, 12),
        metrics: const <MetricImprovement>[
          MetricImprovement(
            metricId: 'tempo',
            directionCode: 'improved',
            beforeValue: 80,
            afterValue: 90,
            relativeDelta: 0.125,
          ),
        ],
      );

      final wire = communityArtifactToWire(original.toJson());
      final inner = wire['artifact'] as Map<String, Object?>;
      final metrics = inner['metrics'] as List<Object?>;
      final metric = metrics.single as Map<String, Object?>;
      expect(metric['metric_id'], 'tempo');
      expect(metric['direction_code'], 'improved');
      expect(metric['relative_delta'], 0.125);

      expect(
        ShareArtifact.fromJson(communityArtifactFromWire(wire)),
        equals(original),
      );
    });

    test('communityArtifactFromWire is null for a missing / unwrapped '
        'payload', () {
      expect(communityArtifactFromWire(null), isNull);
      expect(communityArtifactFromWire(<String, Object?>{}), isNull);
      expect(communityArtifactFromWire(<String, Object?>{'type': 'x'}), isNull);
    });
  });
}
