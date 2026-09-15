/// Dio-backed implementation of [CommunityClubRepository] (E09-R24
/// contract, ADR 0420; production wiring round 2026-09-15).
///
/// The repository rides the **shared** ``accountApiClientProvider``
/// (the ``communityApiClientProvider`` precedent in
/// ``profile_repository_impl.dart``); a ``null`` client (account layer
/// off) selects [DisabledCommunityClubRepository], whose every call
/// throws ``ConfigurationFailure`` — the shape the club screens'
/// ``FutureProvider``s already fold into their error view.
///
/// Backend: ``backend/app/community/routers/clubs.py`` (prefix
/// ``/community/clubs``), wire contracts in
/// ``backend/app/community/schemas/club.py`` — snake_case, every
/// identity a public UUID, list envelope ``{"items": [ClubOut...],
/// "next_cursor": "..."|null}``.
///
/// | Method                | Route (``…`` = ``/community/clubs``)           |
/// |-----------------------|------------------------------------------------|
/// | ``listClubs``         | ``GET …?limit=&cursor=``                       |
/// | ``fetchClub``         | ``GET …/{id}``                                 |
/// | ``createClub``        | ``POST …``                                     |
/// | ``updateClub``        | ``PATCH …/{id}`` — NOT sendable, see below     |
/// | ``requestJoin``       | ``POST …/{id}/join``                           |
/// | ``invite``            | ``POST …/{id}/invites``                        |
/// | ``leave``             | ``POST …/{id}/leave``                          |
/// | ``removeMember``      | ``DELETE …/{id}/members/{profile_id}``         |
/// | ``transferOwnership`` | ``POST …/{id}/transfer-ownership``             |
///
/// **``updateClub`` cannot be sent:** the backend route is ``PATCH``
/// and the shared ``ApiClient`` exposes GET / POST / PUT / DELETE only
/// (``api_client.dart`` is outside this round's files). The method
/// throws the typed [communityEndpointUnavailable] failure — the same
/// decision ``post_repository_impl.dart`` took for
/// ``PATCH /community/posts/{id}`` — so the caller sees a
/// ``ConfigurationFailure`` naming the route, never a silent no-op.
///
/// ``ClubOut`` → [CommunityClub] field map: ``public_id`` → ``id``,
/// ``owner_public_id`` → ``ownerId``, ``member_count`` →
/// ``memberCount``, ``my_role`` (``owner`` / ``moderator`` /
/// ``member`` / null) → ``myRole``, ``tags`` (always ``[]`` today) →
/// ``tags``. ``join_request_pending`` / ``updated_at`` /
/// ``resource_version`` have no entity field and are ignored.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../features/auth/public.dart';
import '../../domain/entities/community_club.dart';
import '../../domain/repositories/club_repository.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';
import 'community_repository_support.dart';

/// The shared account client, read lazily (the
/// ``communityApiClientProvider`` precedent).
final communityClubApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// Pick the implementation for the given client: the HTTP one when
/// the account layer is on, the disabled stand-in otherwise.
CommunityClubRepository createCommunityClubRepository(ApiClient? client) {
  if (client == null) return const DisabledCommunityClubRepository();
  return HttpCommunityClubRepository(client);
}

/// Disabled-mode fallback: every call throws ``ConfigurationFailure``.
final class DisabledCommunityClubRepository implements CommunityClubRepository {
  const DisabledCommunityClubRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async =>
      throw _disabled.error;

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async => throw _disabled.error;
}

/// Live HTTP-backed club repository.
class HttpCommunityClubRepository implements CommunityClubRepository {
  HttpCommunityClubRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async {
    // ``ApiClient.getJson`` takes no query map — the cursor / limit
    // are inlined (the Kör 23 leaderboard precedent).
    final cursorValue = communityCursorQueryValue(cursor);
    final querySegments = <String>[
      'limit=${Uri.encodeQueryComponent('$limit')}',
      if (cursorValue != null)
        'cursor=${Uri.encodeQueryComponent(cursorValue)}',
    ];
    final path = '/community/clubs?${querySegments.join('&')}';
    final result = await _client.getJson<dynamic>(
      path,
      decode: decodeClubListPage,
    );
    return switch (result) {
      Success(:final value) => value as CommunityPage<CommunityClub>,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async {
    final result = await _client.getJson<dynamic>(
      '/community/clubs/${clubId.value}',
      decode: decodeClub,
    );
    return switch (result) {
      Success(:final value) => value as CommunityClub,
      Failure(:final error) => throw error,
    };
  }

  /// ``POST /community/clubs`` — ``CreateClubRequest`` (``extra=
  /// 'forbid'``: only these five keys may travel). A 409
  /// (idempotency-key collision with a different payload) maps to
  /// ``FailureCode.communityConflict`` like the profile create path.
  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<dynamic>(
      '/community/clubs',
      data: <String, Object?>{
        'name': name,
        'description': description,
        'visibility': clubVisibilityToWire(visibility),
        'tags': tags,
        'idempotency_key': idempotencyKey,
      },
      decode: decodeClub,
      conflictCode: FailureCode.communityConflict,
    );
    return switch (result) {
      Success(:final value) => value as CommunityClub,
      Failure(:final error) => throw error,
    };
  }

  /// See the library comment — the route is ``PATCH`` and the shared
  /// transport has no PATCH; the typed failure names the route.
  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw communityEndpointUnavailable(
    'PATCH /community/clubs/{id} (ApiClient has no PATCH transport)',
  );

  /// ``POST /community/clubs/{id}/join`` — ``ClubActionRequest``.
  /// The server turns this into a membership row (public /
  /// discoverable) or a pending request (private); the response is
  /// the club row, which the caller re-reads through ``fetchClub``.
  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/clubs/${clubId.value}/join',
      data: <String, Object?>{'idempotency_key': idempotencyKey},
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  /// ``POST /community/clubs/{id}/invites`` — ``ClubInviteRequest``.
  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/clubs/${clubId.value}/invites',
      data: <String, Object?>{
        'invitee_public_id': target.value,
        'idempotency_key': idempotencyKey,
      },
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  /// ``POST /community/clubs/{id}/leave`` — ``ClubActionRequest``.
  /// The owner's leave is refused server-side until ownership is
  /// transferred (A1); the 409 surfaces as ``ValidationFailure``.
  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/clubs/${clubId.value}/leave',
      data: <String, Object?>{'idempotency_key': idempotencyKey},
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  /// ``DELETE /community/clubs/{id}/members/{profile_id}`` — the
  /// idempotency key rides the URL on DELETE (ADR 0401 §1, the
  /// ``unfollow`` precedent); the router reads it from
  /// ``?idempotency_key=``.
  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async {
    final path =
        '/community/clubs/${clubId.value}/members/${memberId.value}'
        '?idempotency_key=${Uri.encodeQueryComponent(idempotencyKey)}';
    final result = await _client.delete(path, headers: const {});
    if (result is Failure) {
      throw result.error;
    }
  }

  /// ``POST /community/clubs/{id}/transfer-ownership`` —
  /// ``TransferOwnershipRequest``.
  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/clubs/${clubId.value}/transfer-ownership',
      data: <String, Object?>{
        'new_owner_public_id': newOwnerId.value,
        'idempotency_key': idempotencyKey,
      },
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  // ---- internal ----------------------------------------------------------

  /// Decode the ``ClubPage`` envelope. Cursor mapping mirrors
  /// ``decodeChallengeListPage``: no ``next_cursor`` + no rows halts
  /// the pager, no ``next_cursor`` + rows resets to ``initial()``, a
  /// string produces ``continued()``.
  CommunityPage<CommunityClub> decodeClubListPage(Map<String, Object?> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('community club wire: items must be a list');
    }
    final items = rawItems
        .whereType<Map>()
        .map((row) {
          final typed = <String, Object?>{};
          row.forEach((key, value) {
            if (key is String) typed[key] = value;
          });
          return decodeClub(typed);
        })
        .toList(growable: false);
    final nextCursor = json['next_cursor'];
    final cursorPage = nextCursor == null
        ? (items.isEmpty
              ? const CursorPage.haltedAfterRequest()
              : const CursorPage.initial())
        : CursorPage.continued(nextCursor as String);
    return CommunityPage<CommunityClub>(items: items, cursor: cursorPage);
  }

  /// Decode one ``ClubOut`` row. The [CommunityClub] factory enforces
  /// the structural bounds (name ≤ 60, tags ≤ 10, 1 ≤ member_count ≤
  /// 500) — a violation surfaces as ``ArgumentError`` inside the
  /// ``getJson`` decode step, i.e. as ``networkBadResponse``, never as
  /// a half-decoded row.
  CommunityClub decodeClub(Map<String, Object?> json) {
    final publicId = json['public_id'];
    if (publicId is! String) {
      throw const FormatException(
        'community club wire: public_id must be a string',
      );
    }
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException(
        'community club wire: name must be a non-empty string',
      );
    }
    final description = json['description'];
    if (description != null && description is! String) {
      throw const FormatException(
        'community club wire: description must be a string',
      );
    }
    final visibilityWire = json['visibility'];
    if (visibilityWire is! String) {
      throw const FormatException(
        'community club wire: visibility must be a string',
      );
    }
    final visibility = clubVisibilityFromWire(visibilityWire);
    if (visibility == null) {
      throw FormatException(
        'community club wire: unknown visibility $visibilityWire',
      );
    }
    final ownerId = json['owner_public_id'];
    if (ownerId is! String) {
      throw const FormatException(
        'community club wire: owner_public_id must be a string',
      );
    }
    final memberCount = json['member_count'];
    if (memberCount is! int) {
      throw const FormatException(
        'community club wire: member_count must be an int',
      );
    }
    final createdAt = json['created_at'];
    if (createdAt is! String) {
      throw const FormatException(
        'community club wire: created_at must be a string',
      );
    }
    final parsedCreatedAt = DateTime.tryParse(createdAt);
    if (parsedCreatedAt == null) {
      throw FormatException(
        'community club wire: unparseable created_at "$createdAt"',
      );
    }
    final rawTags = json['tags'];
    if (rawTags != null && rawTags is! List) {
      throw const FormatException('community club wire: tags must be a list');
    }
    final tags = rawTags is List
        ? rawTags.whereType<String>().toList(growable: false)
        : const <String>[];
    return CommunityClub(
      id: ContentId(publicId),
      name: name,
      description: (description as String?) ?? '',
      visibility: visibility,
      tags: tags,
      ownerId: PublicUserId(ownerId),
      memberCount: memberCount,
      myRole: decodeClubRoleOrNull(json['my_role']),
      createdAt: parsedCreatedAt,
    );
  }

  /// ``my_role`` → [ClubRole]; ``null`` / absent means "not a member",
  /// an unknown role string is a wire error (the role vocabulary is
  /// server-authoritative and closed).
  ClubRole? decodeClubRoleOrNull(Object? wire) {
    if (wire == null) return null;
    if (wire is! String) {
      throw const FormatException(
        'community club wire: my_role must be a string or null',
      );
    }
    for (final role in ClubRole.values) {
      if (role.name == wire) return role;
    }
    throw FormatException('community club wire: unknown my_role $wire');
  }
}
