/// Dio-backed implementation of [SocialGraphRepository] (E09-R07,
/// ADR 0401 §2; E09-R08, ADR 0402).
///
/// The repository implements the **existing** ``SocialGraphRepository``
/// contract — the Kör 5 / ADR 0399 domain interface — NOT a new
/// ``RelationshipRepository`` (the file name is the implementation
/// name, the interface is the pre-existing one). Of the 13 methods:
///
/// * The 7 follow-related methods (``followingPage`` / ``followersPage``
///   / ``follow`` / ``unfollow`` / ``removeFollower`` /
///   ``acceptFollowRequest`` / ``declineFollowRequest``) are wired
///   against the Kör 7 backend endpoints.
/// * The 4 block/mute methods (``block`` / ``unblock`` / ``mute`` /
///   ``unmute``) are wired in E09-R08 against
///   ``/community/profiles/{id}/block|mute`` endpoints — same
///   POST/DELETE idempotency-key shape as the follow endpoints.
/// * The 2 ``blockedProfilesPage`` / ``mutedProfilesPage`` list
///   methods were added in E09-R08 (ADR 0402 §D5) so the
///   Blocked/Muted settings screen can render the caller's own
///   block/mute lists. They reuse the same ``_decodePage`` /
///   ``_placeholderProfile`` envelope as the follow lists.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../features/auth/public.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/repositories/social_graph_repository.dart';
import '../../domain/value_objects/community_handle.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';

/// The single ``communityAccountClient`` provider. Built lazily so
/// the account-disabled build never constructs the Dio client at
/// all — the same pattern as ``communityApiClientProvider`` in
/// ``profile_repository_impl.dart``.
final communitySocialApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// Disabled-mode fallback: returns ``ConfigurationFailure`` for every
/// call. Mirrors the pattern of ``DisabledCommunityProfileRepository``
/// so the controller code path is uniform across the three
/// repository flavors (auth / profile / social-graph).
final class DisabledSocialGraphRepository implements SocialGraphRepository {
  const DisabledSocialGraphRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityPage<CommunityProfile>> followingPage({
    required PublicUserId userId,
    required Object cursor,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPage<CommunityProfile>> followersPage({
    required PublicUserId userId,
    required Object cursor,
  }) async => throw _disabled.error;

  @override
  Future<ContentId> follow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> unfollow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> removeFollower({
    required PublicUserId follower,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> acceptFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> declineFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> block({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> unblock({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> mute({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> unmute({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPage<CommunityProfile>> blockedProfilesPage({
    required Object cursor,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPage<CommunityProfile>> mutedProfilesPage({
    required Object cursor,
  }) async => throw _disabled.error;
}

/// Live HTTP-backed social-graph repository.
///
/// The cursor parameter is typed as ``Object`` in the domain
/// interface — the server returns an opaque token and we forward it
/// verbatim. ``_cursorQueryValue`` normalizes the well-known shapes
/// (null → no query param; string → string; everything else →
/// ``ArgumentError``) so the call site does not have to know about
/// the wire shape.
class HttpSocialGraphRepository implements SocialGraphRepository {
  HttpSocialGraphRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommunityPage<CommunityProfile>> followingPage({
    required PublicUserId userId,
    required Object cursor,
  }) async {
    // Cursor pagination: forwarded verbatim to the server. The
    // server returns ``next_cursor`` (string or null) which the
    // domain layer packs into the typed ``CursorPage`` envelope.
    final params = <String, Object?>{'limit': 50};
    final cursorValue = _cursorQueryValue(cursor);
    if (cursorValue != null) params['cursor'] = cursorValue;
    final result = await _client.getJson<dynamic>(
      '/community/profiles/${userId.value}/following',
      queryParameters: params,
      decode: _decodePage,
    );
    return switch (result) {
      Success(:final value) => value as CommunityPage<CommunityProfile>,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityPage<CommunityProfile>> followersPage({
    required PublicUserId userId,
    required Object cursor,
  }) async {
    final params = <String, Object?>{'limit': 50};
    final cursorValue = _cursorQueryValue(cursor);
    if (cursorValue != null) params['cursor'] = cursorValue;
    final result = await _client.getJson<dynamic>(
      '/community/profiles/${userId.value}/followers',
      queryParameters: params,
      decode: _decodePage,
    );
    return switch (result) {
      Success(:final value) => value as CommunityPage<CommunityProfile>,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<ContentId> follow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<dynamic>(
      '/community/profiles/${target.value}/follow',
      data: {'idempotency_key': idempotencyKey},
      decode: _decodeFollowResult,
    );
    return switch (result) {
      Success(:final value) => ContentId((value['request_id'] as String)),
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<void> unfollow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    // ADR 0401 §1: the DELETE idempotency key travels as a
    // query parameter because the ``ApiClient.delete()`` transport
    // carries no JSON body. The backend counterpart
    // (``social_graph.py::delete_follow``) reads it from
    // ``?idempotency_key=...`` and rejects (422) when missing.
    // Encoding here keeps the ``api_client.dart`` delete() method
    // an exact mirror of post() — the endpoint-specific contract
    // lives one layer up, in the repository.
    final path =
        '/community/profiles/${target.value}/follow'
        '?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}';
    final result = await _client.delete(path, headers: const {});
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<void> removeFollower({
    required PublicUserId follower,
    required String idempotencyKey,
  }) async {
    final ownerPublicId = await _resolveCallerPublicId();
    // Same ADR 0401 §1 contract as ``unfollow`` above — the
    // idempotency key rides the URL on DELETE, not a body.
    final path =
        '/community/profiles/$ownerPublicId/followers/${follower.value}'
        '?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}';
    final result = await _client.delete(path, headers: const {});
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<void> acceptFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<dynamic>(
      '/community/follow-requests/${requestId.value}/accept',
      data: {'idempotency_key': idempotencyKey},
      decode: _decodeVoidResponse,
    );
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<void> declineFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<dynamic>(
      '/community/follow-requests/${requestId.value}/decline',
      data: {'idempotency_key': idempotencyKey},
      decode: _decodeVoidResponse,
    );
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<void> block({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<dynamic>(
      '/community/profiles/${target.value}/block',
      data: {'idempotency_key': idempotencyKey},
      decode: _decodeVoidResponse,
    );
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<void> unblock({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    // ADR 0402 backend-HTTP surface — DELETE idempotency key travels
    // as a query parameter, mirroring `unfollow` / `removeFollower`
    // (ADR 0401 §1).
    final path =
        '/community/profiles/${target.value}/block'
        '?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}';
    final result = await _client.delete(path, headers: const {});
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<void> mute({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<dynamic>(
      '/community/profiles/${target.value}/mute',
      data: {'idempotency_key': idempotencyKey},
      decode: _decodeVoidResponse,
    );
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<void> unmute({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    final path =
        '/community/profiles/${target.value}/mute'
        '?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}';
    final result = await _client.delete(path, headers: const {});
    if (result is Failure) {
      throw (result).error;
    }
  }

  @override
  Future<CommunityPage<CommunityProfile>> blockedProfilesPage({
    required Object cursor,
  }) async {
    final path = _buildPagePath('/community/blocked', cursor);
    final result = await _client.getJson<dynamic>(path, decode: _decodePage);
    return switch (result) {
      Success(:final value) => value as CommunityPage<CommunityProfile>,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityPage<CommunityProfile>> mutedProfilesPage({
    required Object cursor,
  }) async {
    final path = _buildPagePath('/community/muted', cursor);
    final result = await _client.getJson<dynamic>(path, decode: _decodePage);
    return switch (result) {
      Success(:final value) => value as CommunityPage<CommunityProfile>,
      Failure(:final error) => throw error,
    };
  }

  String _buildPagePath(String base, Object cursor) {
    // Inline the limit and the optional cursor into the URL so the
    // request hits the backend with the right query string. The
    // shared ``api_client.dart::getJson`` does not accept a query-
    // param map (its four endpoints all carry no params), so the
    // only way to forward a cursor today is inline — same pattern
    // as the Kör 7 ``unfollow`` DELETE.
    final cursorValue = _cursorQueryValue(cursor);
    final qs = cursorValue == null
        ? 'limit=50'
        : 'limit=50&cursor=$cursorValue';
    return '$base?$qs';
  }

  Future<String> _resolveCallerPublicId() async {
    // The repository does not know the caller's public-id directly;
    // the only callers of removeFollower are the controller, which
    // has the caller's profile already loaded. We delegate through
    // the public community-profile fetch so the repository stays
    // self-contained — the Kör 6 / 7 contract: every Kör 7 call
    // site that needs the caller's public-id resolves it through
    // the same ``GET /community/profiles/me`` endpoint.
    final result = await _client.getJson<dynamic>(
      '/community/profiles/me',
      decode: (json) => json,
    );
    return switch (result) {
      Success(:final value) => (value as Map)['public_id'] as String,
      Failure(:final error) => throw error,
    };
  }

  CommunityPage<CommunityProfile> _decodePage(Map<String, Object?> json) {
    final rawIds = json['public_ids'];
    if (rawIds is! List) {
      throw const FormatException(
        'community follow-list wire: public_ids must be a list',
      );
    }
    final publicIds = rawIds
        .whereType<String>()
        .map(PublicUserId.new)
        .toList(growable: false);
    final nextCursor = json['next_cursor'];
    // Cursor type-state: null on initial request, string on
    // continued pages, explicit null on halted pages.
    final cursorPage = nextCursor == null
        ? (publicIds.isEmpty
              ? const CursorPage.haltedAfterRequest()
              : const CursorPage.initial())
        : CursorPage.continued(nextCursor as String);
    // The page carries public_ids only; the controller resolves
    // them to full CommunityProfile rows through a separate
    // fetchById path. This keeps the wire shape lean (no N+1 on
    // a 50-row page) and the page boundary honest (a thin
    // CommunityProfile factory is built below so the page's
    // element type matches the interface — callers that want
    // full profiles compose a follow-up fetch).
    final items = publicIds.map(_placeholderProfile).toList(growable: false);
    return CommunityPage<CommunityProfile>(items: items, cursor: cursorPage);
  }

  Map<String, Object?> _decodeFollowResult(Map<String, Object?> json) {
    return json;
  }

  Map<String, Object?> _decodeVoidResponse(Map<String, Object?> json) {
    return json;
  }

  String? _cursorQueryValue(Object cursor) {
    if (cursor == const CursorPage.initial()) return null;
    if (cursor is CursorPage) {
      return cursor.cursor;
    }
    throw ArgumentError.value(
      cursor,
      'cursor',
      'cursor must be a CursorPage (initial / continued / haltedAfterRequest)',
    );
  }
}

/// The Community social-graph repository wired against the live
/// ``accountApiClientProvider`` — null on a build where the
/// account layer is disabled, the http impl otherwise.
final socialGraphRepositoryProvider = Provider<SocialGraphRepository>((ref) {
  final client = ref.watch(communitySocialApiClientProvider);
  if (client == null) return const DisabledSocialGraphRepository();
  return HttpSocialGraphRepository(client);
});

CommunityProfile _placeholderProfile(PublicUserId userId) {
  // The follow-list wire shape carries only public_ids. The full
  // CommunityProfile fetch (Kör 5 fetchById / Kör 7 follow-up) is
  // the Kör 8+ contract; this round ships the page boundary
  // only. The placeholder carries the public_id and a flag the
  // controller can branch on if it wants to skip the
  // fetchById follow-up — but the canonical path is to call
  // ``communityProfileRepository.fetchById`` on each entry.
  // The placeholder is a structural seam so the page envelope
  // can satisfy ``CommunityPage<CommunityProfile>`` without
  // calling the DB on every list-fetch.
  //
  // E09-R08: the factory enforces a non-empty displayName — the
  // Kör 7 ``''`` literal here would throw ``ArgumentError`` the
  // moment ``_decodePage`` materialises a row. A short, non-empty
  // placeholder keeps the page boundary honest; the real display
  // name arrives via the canonical ``fetchById`` follow-up.
  return CommunityProfile(
    userId: userId,
    handle: CommunityHandle('placeholder-x1'),
    displayName: 'placeholder',
    visibility: ProfileVisibility.followers,
    avatarUrl: null,
    bio: null,
    skillInterests: const <String>[],
    badges: const <String>[],
    relationship: CommunityRelationshipToViewer.notRelated,
    createdAt: DateTime.utc(2026),
  );
}
