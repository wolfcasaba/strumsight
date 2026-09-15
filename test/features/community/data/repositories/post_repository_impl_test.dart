/// Post repository wiring tests — the ``HttpCommunityPostRepository``
/// over the backend ``posts.py`` + ``bookmarks.py`` routers.
///
/// Pins the wire format with a scripted ``HttpClientAdapter`` (the
/// E09-R08 social-graph precedent — no network):
///
/// * ``createPost`` → ``POST /community/posts`` with the
///   ``CreatePostRequest`` body (``audience`` / ``body`` /
///   ``idempotency_key`` and the snake_case ``{"artifact": {…}}``
///   envelope), decoding the 201 ``PostOut``;
/// * ``fetchPost`` → ``GET /community/posts/{id}``, 404 → ``null``;
/// * ``updatePost`` → ``PATCH /community/posts/{id}?idempotency_key=…``
///   with the ``PatchPostRequest`` body (``audience`` / ``body`` /
///   ``resource_version`` — the ``extra="forbid"`` whitelist; a null
///   body omits the key), decoding the 200 ``PostOut``; 404 / 409 /
///   5xx mapping;
/// * ``deletePost`` → ``DELETE /community/posts/{id}?idempotency_key=…``;
/// * ``setBookmark`` → ``POST`` / ``DELETE /community/bookmarks/{id}``;
/// * the error taxonomy (409 → ``community.conflict``, 422, 5xx, 401);
/// * every method with no backend route (reactions, comments) throws
///   the typed ``ConfigurationFailure`` without a request.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/community_reaction.dart';
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

HttpCommunityPostRepository _buildRepo(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HttpCommunityPostRepository(ApiClient(dio));
}

_ScriptedAdapter _adapterWith(String body, {int status = 200}) {
  return _ScriptedAdapter(
    onFetch: (_) => _CannedResponse(body: body, status: status),
  );
}

const String _postA = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa0';
const String _authorA = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01';

PracticeSummaryArtifact _practiceArtifact() => PracticeSummaryArtifact(
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

String _postOutJson({
  String audience = 'followers',
  String body = 'with artifact',
  Map<String, Object?>? artifactPayload,
}) => jsonEncode(<String, Object?>{
  'public_id': _postA,
  'author_public_id': _authorA,
  'audience': audience,
  'club_id': null,
  'body': body,
  'artifact_type': artifactPayload == null ? null : 'practiceSummary',
  'artifact_schema_version': artifactPayload == null ? null : 1,
  'artifact_payload': artifactPayload,
  'moderation_state': 'visible',
  'created_at': '2026-08-23T12:00:00Z',
  'resource_version': '2026-08-23T12:00:00Z',
  'deleted_at': null,
});

Matcher _unavailable() => throwsA(
  isA<ConfigurationFailure>().having(
    (f) => f.cause,
    'cause',
    isA<UnsupportedError>(),
  ),
);

void main() {
  group('createPost()', () {
    test('POSTs the CreatePostRequest body with the snake_case artifact '
        'envelope and decodes the 201 PostOut', () async {
      final adapter = _adapterWith(
        _postOutJson(artifactPayload: _practiceEnvelope()),
        status: 201,
      );
      final repo = _buildRepo(adapter);

      final post = await repo.createPost(
        audience: CommunityAudience.followers,
        body: 'with artifact',
        // The outbox forwards the persisted JSON map, not the typed
        // artifact — this is the production call shape.
        artifact: _practiceArtifact().toJson(),
        idempotencyKey: 'artifact-1',
      );

      expect(adapter.captured, hasLength(1));
      final options = adapter.captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/posts');
      final data = options.data as Map<String, Object?>;
      expect(data['audience'], 'followers');
      expect(data['body'], 'with artifact');
      expect(data['idempotency_key'], 'artifact-1');
      // The backend `extra="forbid"` whitelist — nothing else crosses.
      expect(
        data.keys.toSet(),
        <String>{'audience', 'body', 'artifact', 'idempotency_key'},
      );
      final envelope = data['artifact'] as Map<String, Object?>;
      final inner = envelope['artifact'] as Map<String, Object?>;
      expect(inner['type'], 'practiceSummary');
      expect(inner['schema_version'], 1);
      expect(inner['source_id'], 'practice-1');
      expect(inner['active_seconds'], 90);
      expect(inner.containsKey('schemaVersion'), isFalse);

      expect(post.id, ContentId(_postA));
      expect(post.authorId, PublicUserId(_authorA));
      expect(post.audience, CommunityAudience.followers);
      expect(post.body, 'with artifact');
      expect(post.moderationState, ModerationState.visible);
      expect(post.artifact, equals(_practiceArtifact()));
    });

    test('a typed ShareArtifact is serialised through its own '
        'toJson()', () async {
      final adapter = _adapterWith(_postOutJson(), status: 201);
      final repo = _buildRepo(adapter);

      await repo.createPost(
        audience: CommunityAudience.public,
        body: 'typed',
        artifact: _practiceArtifact(),
        idempotencyKey: 'typed-1',
      );

      final data = adapter.captured.single.data as Map<String, Object?>;
      final envelope = data['artifact'] as Map<String, Object?>;
      final inner = envelope['artifact'] as Map<String, Object?>;
      expect(inner['source_id'], 'practice-1');
    });

    test('an Unfilled artifact / empty map omits the artifact key', () async {
      final adapter = _adapterWith(_postOutJson(), status: 201);
      final repo = _buildRepo(adapter);

      await repo.createPost(
        audience: CommunityAudience.public,
        body: 'plain',
        artifact: UnfilledCommunityShareArtifact(),
        idempotencyKey: 'plain-1',
      );
      await repo.createPost(
        audience: CommunityAudience.public,
        body: 'plain',
        artifact: const <String, Object?>{},
        idempotencyKey: 'plain-2',
      );

      for (final options in adapter.captured) {
        final data = options.data as Map<String, Object?>;
        expect(data.containsKey('artifact'), isFalse);
      }
      final decoded = await repo.fetchPost(postId: ContentId(_postA));
      expect(decoded?.artifact, isA<UnfilledCommunityShareArtifact>());
    });

    test('a null body is sent as an empty string (the backend 422 is the '
        'verdict on artifact-only posts)', () async {
      final adapter = _adapterWith(_postOutJson(), status: 201);
      final repo = _buildRepo(adapter);

      await repo.createPost(
        audience: CommunityAudience.public,
        body: null,
        artifact: _practiceArtifact().toJson(),
        idempotencyKey: 'null-body',
      );

      final data = adapter.captured.single.data as Map<String, Object?>;
      expect(data['body'], '');
    });

    test('409 surfaces as ValidationFailure(community.conflict)', () async {
      final adapter = _adapterWith('{"detail":"conflict"}', status: 409);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.createPost(
          audience: CommunityAudience.public,
          body: 'x',
          artifact: const <String, Object?>{},
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.communityConflict,
          ),
        ),
      );
    });

    test('422 surfaces as '
        'ValidationFailure(validation.invalid_input)', () async {
      final adapter = _adapterWith('{"detail":[]}', status: 422);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.createPost(
          audience: CommunityAudience.public,
          body: '<script>',
          artifact: const <String, Object?>{},
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.validationInvalidInput,
          ),
        ),
      );
    });

    test('5xx surfaces as a retryable '
        'NetworkFailure(network.server)', () async {
      final adapter = _adapterWith('{"detail":"boom"}', status: 500);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.createPost(
          audience: CommunityAudience.public,
          body: 'x',
          artifact: const <String, Object?>{},
          idempotencyKey: 'k',
        ),
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
        repo.createPost(
          audience: CommunityAudience.public,
          body: 'x',
          artifact: const <String, Object?>{},
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<AuthenticationFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.authSessionExpired,
          ),
        ),
      );
    });

    test('a malformed PostOut (missing public_id) surfaces as '
        'NetworkFailure(network.bad_response)', () async {
      final adapter = _adapterWith('{"body":"x"}', status: 201);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.createPost(
          audience: CommunityAudience.public,
          body: 'x',
          artifact: const <String, Object?>{},
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<NetworkFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.networkBadResponse,
          ),
        ),
      );
    });
  });

  group('fetchPost()', () {
    test('GETs /community/posts/{id} and decodes the PostOut', () async {
      final adapter = _adapterWith(
        _postOutJson(artifactPayload: _practiceEnvelope()),
      );
      final repo = _buildRepo(adapter);

      final post = await repo.fetchPost(postId: ContentId(_postA));

      final options = adapter.captured.single;
      expect(options.method, 'GET');
      expect(options.path, '/community/posts/$_postA');
      expect(post, isNotNull);
      expect(post!.id, ContentId(_postA));
      expect(post.artifact, isA<PracticeSummaryArtifact>());
    });

    test('404 (missing or not visible) returns null', () async {
      final adapter = _adapterWith('{"detail":"post not found"}', status: 404);
      final repo = _buildRepo(adapter);

      expect(await repo.fetchPost(postId: ContentId(_postA)), isNull);
    });

    test('5xx still throws', () async {
      final adapter = _adapterWith('{"detail":"boom"}', status: 500);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.fetchPost(postId: ContentId(_postA)),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('updatePost()', () {
    test('PATCHes /community/posts/{id}?idempotency_key=… with the '
        'PatchPostRequest body and decodes the 200 PostOut', () async {
      final adapter = _adapterWith(
        _postOutJson(audience: 'public', body: 'edited'),
      );
      final repo = _buildRepo(adapter);

      final post = await repo.updatePost(
        postId: ContentId(_postA),
        body: 'edited',
        audience: CommunityAudience.public,
        resourceVersion: '2026-08-23T12:00:00Z',
        idempotencyKey: 'u-1',
      );

      expect(adapter.captured, hasLength(1));
      final options = adapter.captured.single;
      expect(options.method, 'PATCH');
      expect(options.path, '/community/posts/$_postA?idempotency_key=u-1');
      expect(options.uri.queryParameters['idempotency_key'], 'u-1');
      final data = options.data as Map<String, Object?>;
      expect(data['audience'], 'public');
      expect(data['body'], 'edited');
      expect(data['resource_version'], '2026-08-23T12:00:00Z');
      // The backend `extra="forbid"` whitelist — the idempotency key
      // rides the URL, never the body; `artifact` is never sent.
      expect(
        data.keys.toSet(),
        <String>{'audience', 'body', 'resource_version'},
      );

      expect(post.id, ContentId(_postA));
      expect(post.audience, CommunityAudience.public);
      expect(post.body, 'edited');
      expect(post.moderationState, ModerationState.visible);
    });

    test('a null body omits the body key (absent field = leave '
        'alone)', () async {
      final adapter = _adapterWith(_postOutJson(audience: 'private'));
      final repo = _buildRepo(adapter);

      await repo.updatePost(
        postId: ContentId(_postA),
        body: null,
        audience: CommunityAudience.private,
        resourceVersion: '2026-08-23T12:00:00Z',
        idempotencyKey: 'u-2',
      );

      final data = adapter.captured.single.data as Map<String, Object?>;
      expect(data.containsKey('body'), isFalse);
      expect(data['audience'], 'private');
      expect(data.keys.toSet(), <String>{'audience', 'resource_version'});
    });

    test('a DateTime resourceVersion is sent as UTC ISO-8601', () async {
      final adapter = _adapterWith(_postOutJson());
      final repo = _buildRepo(adapter);

      await repo.updatePost(
        postId: ContentId(_postA),
        body: 'x',
        audience: CommunityAudience.followers,
        resourceVersion: DateTime.utc(2026, 8, 23, 12),
        idempotencyKey: 'u-3',
      );

      final data = adapter.captured.single.data as Map<String, Object?>;
      expect(data['resource_version'], '2026-08-23T12:00:00.000Z');
    });

    test('an unsupported resourceVersion type is an ArgumentError '
        'before any request', () async {
      final adapter = _adapterWith(_postOutJson());
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.updatePost(
          postId: ContentId(_postA),
          body: 'x',
          audience: CommunityAudience.public,
          resourceVersion: 42,
          idempotencyKey: 'u-4',
        ),
        throwsArgumentError,
      );
      expect(adapter.captured, isEmpty);
    });

    test('409 (stale resource_version) surfaces as '
        'ValidationFailure(community.conflict)', () async {
      final adapter = _adapterWith(
        '{"detail":{"error":"stale_resource_version",'
        '"current_resource_version":"2026-08-24T12:00:00Z"}}',
        status: 409,
      );
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.updatePost(
          postId: ContentId(_postA),
          body: 'x',
          audience: CommunityAudience.public,
          resourceVersion: '2026-08-23T12:00:00Z',
          idempotencyKey: 'u-5',
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.communityConflict,
          ),
        ),
      );
    });

    test('404 (missing or not owned) throws '
        'NetworkFailure(network.bad_response)', () async {
      final adapter = _adapterWith('{"detail":"post not found"}', status: 404);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.updatePost(
          postId: ContentId(_postA),
          body: 'x',
          audience: CommunityAudience.public,
          resourceVersion: '2026-08-23T12:00:00Z',
          idempotencyKey: 'u-6',
        ),
        throwsA(
          isA<NetworkFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.networkBadResponse,
          ),
        ),
      );
    });

    test('5xx surfaces as a retryable '
        'NetworkFailure(network.server)', () async {
      final adapter = _adapterWith('{"detail":"boom"}', status: 503);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.updatePost(
          postId: ContentId(_postA),
          body: 'x',
          audience: CommunityAudience.public,
          resourceVersion: '2026-08-23T12:00:00Z',
          idempotencyKey: 'u-7',
        ),
        throwsA(
          isA<NetworkFailure>()
              .having((f) => f.code, 'code', FailureCode.networkServer)
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('a malformed PostOut surfaces as '
        'NetworkFailure(network.bad_response)', () async {
      final adapter = _adapterWith('{"body":"x"}');
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.updatePost(
          postId: ContentId(_postA),
          body: 'x',
          audience: CommunityAudience.public,
          resourceVersion: '2026-08-23T12:00:00Z',
          idempotencyKey: 'u-8',
        ),
        throwsA(
          isA<NetworkFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.networkBadResponse,
          ),
        ),
      );
    });
  });

  group('deletePost()', () {
    test('DELETEs /community/posts/{id} with ?idempotency_key=…', () async {
      final adapter = _adapterWith('{"status":"deleted"}');
      final repo = _buildRepo(adapter);

      await repo.deletePost(postId: ContentId(_postA), idempotencyKey: 'del-1');

      final options = adapter.captured.single;
      expect(options.method, 'DELETE');
      expect(options.path, '/community/posts/$_postA?idempotency_key=del-1');
      expect(options.uri.queryParameters['idempotency_key'], 'del-1');
    });

    test('404 throws (the interface has no null channel for delete)', () async {
      final adapter = _adapterWith('{"detail":"post not found"}', status: 404);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.deletePost(postId: ContentId(_postA), idempotencyKey: 'del-1'),
        throwsA(
          isA<NetworkFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.networkBadResponse,
          ),
        ),
      );
    });
  });

  group('setBookmark()', () {
    test('bookmarked: true POSTs /community/bookmarks/{id}', () async {
      final adapter = _adapterWith(
        '{"status":"ok","post_public_id":"$_postA"}',
      );
      final repo = _buildRepo(adapter);

      await repo.setBookmark(
        postId: ContentId(_postA),
        bookmarked: true,
        idempotencyKey: 'bm-1',
      );

      final options = adapter.captured.single;
      expect(options.method, 'POST');
      expect(
        options.path,
        '/community/bookmarks/$_postA?idempotency_key=bm-1',
      );
      expect(options.uri.queryParameters['idempotency_key'], 'bm-1');
    });

    test('bookmarked: false DELETEs /community/bookmarks/{id}', () async {
      final adapter = _adapterWith(
        '{"status":"noop","post_public_id":"$_postA"}',
      );
      final repo = _buildRepo(adapter);

      await repo.setBookmark(
        postId: ContentId(_postA),
        bookmarked: false,
        idempotencyKey: 'bm-2',
      );

      final options = adapter.captured.single;
      expect(options.method, 'DELETE');
      expect(
        options.path,
        '/community/bookmarks/$_postA?idempotency_key=bm-2',
      );
    });

    test('404 (post gone) throws '
        'NetworkFailure(network.bad_response)', () async {
      final adapter = _adapterWith('{"detail":"post not found"}', status: 404);
      final repo = _buildRepo(adapter);

      await expectLater(
        repo.setBookmark(
          postId: ContentId(_postA),
          bookmarked: true,
          idempotencyKey: 'bm-3',
        ),
        throwsA(
          isA<NetworkFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.networkBadResponse,
          ),
        ),
      );
    });
  });

  group('methods with no backend route throw the typed failure and '
      'never touch the transport', () {
    late _ScriptedAdapter adapter;
    late HttpCommunityPostRepository repo;

    setUp(() {
      adapter = _adapterWith('{}');
      repo = _buildRepo(adapter);
    });

    tearDown(() {
      expect(adapter.captured, isEmpty, reason: 'no request may be sent');
    });

    test('setReaction()', () async {
      await expectLater(
        repo.setReaction(
          postId: ContentId(_postA),
          kind: ReactionKind.support,
          idempotencyKey: 'r-1',
        ),
        _unavailable(),
      );
    });

    test('comments()', () async {
      await expectLater(
        repo.comments(
          postId: ContentId(_postA),
          cursor: const CursorPage.initial(),
          limit: 25,
        ),
        _unavailable(),
      );
    });

    test('createComment()', () async {
      await expectLater(
        repo.createComment(
          postId: ContentId(_postA),
          parentCommentId: null,
          body: 'hi',
          idempotencyKey: 'c-1',
        ),
        _unavailable(),
      );
    });

    test('updateComment()', () async {
      await expectLater(
        repo.updateComment(
          commentId: ContentId('c-1'),
          body: 'hi',
          idempotencyKey: 'c-2',
        ),
        _unavailable(),
      );
    });

    test('deleteComment()', () async {
      await expectLater(
        repo.deleteComment(commentId: ContentId('c-1'), idempotencyKey: 'c-3'),
        _unavailable(),
      );
    });
  });

  group('factory + disabled fallback', () {
    test('createCommunityPostRepository(null) is the disabled stand-in', () {
      expect(
        createCommunityPostRepository(null),
        isA<DisabledCommunityPostRepository>(),
      );
    });

    test('createCommunityPostRepository(client) is the HTTP impl', () {
      final client = ApiClient(Dio()..httpClientAdapter = _adapterWith('{}'));
      expect(
        createCommunityPostRepository(client),
        isA<HttpCommunityPostRepository>(),
      );
    });

    test('the disabled repository throws ConfigurationFailure', () async {
      const repo = DisabledCommunityPostRepository();
      await expectLater(
        repo.createPost(
          audience: CommunityAudience.public,
          body: 'x',
          artifact: const <String, Object?>{},
          idempotencyKey: 'k',
        ),
        throwsA(isA<ConfigurationFailure>()),
      );
      await expectLater(
        repo.setBookmark(
          postId: ContentId(_postA),
          bookmarked: true,
          idempotencyKey: 'k',
        ),
        throwsA(isA<ConfigurationFailure>()),
      );
    });
  });
}
