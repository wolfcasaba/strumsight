/// Dio-backed implementation of [CommunityPostRepository].
///
/// Wired against the backend ``posts.py`` (E09-R11, ADR 0405) and
/// ``bookmarks.py`` routers. Endpoint ↔ method map (the backend is
/// the source of truth — every path below was read off the router
/// decorators, not the SDD):
///
/// | method          | route                                          |
/// |-----------------|------------------------------------------------|
/// | ``createPost``  | ``POST /community/posts`` → 201 ``PostOut``     |
/// | ``fetchPost``   | ``GET /community/posts/{id}`` (404 → ``null``)  |
/// | ``updatePost``  | ``PATCH /community/posts/{id}`` → ``PostOut``   |
/// | ``deletePost``  | ``DELETE /community/posts/{id}``                |
/// | ``setBookmark`` | ``POST`` / ``DELETE /community/bookmarks/{id}`` |
/// | ``setReaction`` | no route                                        |
/// | ``comments`` / ``createComment`` / ``updateComment`` /
///   ``deleteComment`` | no route                                    |
///
/// **``updatePost``** rides ``ApiClient.patchJson`` with the
/// ``PatchPostRequest`` body (``extra="forbid"``): ``audience``,
/// ``body`` and the required ``resource_version`` token. The router
/// applies "absent field = leave alone" (``exclude_unset``), so a
/// ``null`` domain body OMITS the ``body`` key rather than sending
/// ``""`` (the backend's ``min_length=1`` would 422 that). The
/// ``artifact`` key is never sent — the domain contract has no slot
/// for it, and an absent key leaves the stored artifact intact. A
/// stale ``resource_version`` answers 409 → ``communityConflict``.
///
/// **Missing routes** (reactions, comments) throw the typed
/// ``ConfigurationFailure`` [communityEndpointUnavailable]: the
/// controllers catch ``AppFailure`` and surface a failure state;
/// nothing crashes, nothing pretends.
///
/// **Idempotency keys:** ``POST /community/posts`` reads
/// ``idempotency_key`` from the JSON body (``CreatePostRequest``).
/// The bookmark, delete and PATCH routes take no key today
/// (``PatchPostRequest`` is ``extra="forbid"``, so it must NOT ride
/// the body) — the key still travels as ``?idempotency_key=…`` (the
/// ADR 0401 §1 DELETE convention the social-graph impl uses) so the
/// wire carries the mutation identity the moment the backend starts
/// reading it; the router ignores unknown query parameters.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../features/auth/public.dart';
import '../../domain/entities/community_comment.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/share_artifact.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../dto/post_dto.dart';
import 'community_repository_support.dart';

/// The shared account client, read lazily (the
/// ``communityApiClientProvider`` precedent).
final communityPostApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// Pick the implementation for the given client: the HTTP one when
/// the account layer is on, the disabled stand-in otherwise.
CommunityPostRepository createCommunityPostRepository(ApiClient? client) {
  if (client == null) return const DisabledCommunityPostRepository();
  return HttpCommunityPostRepository(client);
}

/// Disabled-mode fallback: every call throws ``ConfigurationFailure``.
final class DisabledCommunityPostRepository implements CommunityPostRepository {
  const DisabledCommunityPostRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) async =>
      throw _disabled.error;

  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;

  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) async => throw _disabled.error;
}

/// Live HTTP-backed post repository.
class HttpCommunityPostRepository implements CommunityPostRepository {
  HttpCommunityPostRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) async {
    final payload = communityPostCreatePayload(
      audience: audience,
      body: body,
      artifactJson: _artifactJson(artifact),
      idempotencyKey: idempotencyKey,
    );
    final result = await _client.postJson<CommunityPostDto>(
      '/community/posts',
      data: payload,
      decode: CommunityPostDto.fromJson,
      conflictCode: FailureCode.communityConflict,
    );
    return switch (result) {
      Success(:final value) => value.toDomain(),
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) async {
    // ``GET /community/posts/{id}`` answers 404 both for a missing
    // row and for a post the viewer may not see (the §0.0 D7
    // uniform-404 rule) — both map to ``null`` per the interface.
    final result = await _client.getJson<CommunityPostDto>(
      '/community/posts/${postId.value}',
      decode: CommunityPostDto.fromJson,
    );
    return switch (result) {
      Success(:final value) => value.toDomain(),
      Failure(:final error) when _isNotFound(error) => null,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async {
    // ``PATCH /community/posts/{id}`` answers 404 both for a missing
    // row and for a post the viewer does not own (the §0.0 D7
    // uniform-404 rule) — the interface has no null channel for an
    // update, so the ``networkBadResponse`` failure propagates.
    final path =
        '/community/posts/${postId.value}'
        '?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}';
    final result = await _client.patchJson<CommunityPostDto>(
      path,
      data: <String, Object?>{
        'audience': audience.wireValue,
        if (body != null) 'body': body,
        'resource_version': _resourceVersionWire(resourceVersion),
      },
      decode: CommunityPostDto.fromJson,
      conflictCode: FailureCode.communityConflict,
    );
    return switch (result) {
      Success(:final value) => value.toDomain(),
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) async {
    final path =
        '/community/posts/${postId.value}'
        '?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}';
    final result = await _client.delete(path, headers: const {});
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) async => throw communityEndpointUnavailable(
    'PUT /community/posts/{id}/reaction',
  );

  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) async {
    // ``POST`` sets, ``DELETE`` clears — both idempotent server-side
    // (``bookmarks.py``: a repeat answers ``{"status": "noop"}`` with
    // 200, never 409). The response body is ignored on purpose.
    final path =
        '/community/bookmarks/${postId.value}'
        '?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}';
    final result = bookmarked
        ? await _client.post(path, headers: const {})
        : await _client.delete(path, headers: const {});
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) async => throw communityEndpointUnavailable(
    'GET /community/posts/{id}/comments',
  );

  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) async => throw communityEndpointUnavailable(
    'POST /community/posts/{id}/comments',
  );

  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) async => throw communityEndpointUnavailable(
    'PATCH /community/comments/{id}',
  );

  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) async => throw communityEndpointUnavailable(
    'DELETE /community/comments/{id}',
  );

  /// Normalise the ``Object``-typed artifact of the domain contract.
  ///
  /// * a JSON map (what the outbox forwards — the persisted
  ///   ``sourceArtifactJson``) is used as-is;
  /// * a typed [ShareArtifact] is serialised through its own
  ///   ``toJson()``;
  /// * the Kör 5 [UnfilledCommunityShareArtifact] (or any other
  ///   non-sealed base instance) means "no artifact" → ``null``;
  /// * anything else is a programming error at the call site.
  static Map<String, Object?>? _artifactJson(Object artifact) {
    if (artifact is Map) {
      return <String, Object?>{
        for (final entry in artifact.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    if (artifact is ShareArtifact) return artifact.toJson();
    if (artifact is CommunityShareArtifact) return null;
    throw ArgumentError.value(
      artifact,
      'artifact',
      'artifact must be a JSON map, a ShareArtifact or an '
      'UnfilledCommunityShareArtifact',
    );
  }

  /// Normalise the ``Object``-typed ``resourceVersion`` of the domain
  /// contract into the ``resource_version`` wire token — the
  /// ``updated_at`` ISO-8601 timestamp a prior read echoed
  /// (``CommunityPostDto.resourceVersion`` holds it as a [DateTime];
  /// a caller may also forward the raw wire string).
  ///
  /// * a [String] is sent as-is (the server parses it as a datetime);
  /// * a [DateTime] is serialised as UTC ISO-8601;
  /// * anything else is a programming error at the call site.
  static String _resourceVersionWire(Object resourceVersion) {
    if (resourceVersion is String) return resourceVersion;
    if (resourceVersion is DateTime) {
      return resourceVersion.toUtc().toIso8601String();
    }
    throw ArgumentError.value(
      resourceVersion,
      'resourceVersion',
      'resourceVersion must be the wire String or a DateTime',
    );
  }

  static bool _isNotFound(AppFailure error) {
    if (error is NetworkFailure) {
      return error.code == FailureCode.networkBadResponse;
    }
    return false;
  }
}
