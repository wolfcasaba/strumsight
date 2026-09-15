/// Wire-format tests for ``HttpCommunityClubRepository`` against the
/// ``backend/app/community/routers/clubs.py`` contract
/// (``schemas/club.py``; production wiring round 2026-09-15).
///
/// Pins every route + body key set (the request models are
/// ``extra='forbid'``, so a stray key is a 422 on the device), the
/// ``ClubOut`` → ``CommunityClub`` decode, the DELETE idempotency key
/// on the URL (ADR 0401 §1), and the ``updateClub`` PATCH wire shape
/// (``UpdateClubRequest`` body, 200 → ``CommunityClub``, 403 / 404 /
/// 409 / 5xx mapping).
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/club_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_club.dart';
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

HttpCommunityClubRepository _buildRepo(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HttpCommunityClubRepository(ApiClient(dio));
}

_ScriptedAdapter _ok(String body, {int status = 200}) => _ScriptedAdapter(
  onFetch: (_) => _CannedResponse(body: body, status: status),
);

const String _ownerId = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fc0';
const String _clubId = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fc1';
const String _memberId = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fc2';

/// One ``ClubOut`` row — every field the schema emits, including the
/// ones the entity has no slot for (``join_request_pending`` /
/// ``updated_at`` / ``resource_version``), which must be ignored.
String _clubOut({String myRole = '"owner"'}) =>
    '{"public_id":"$_clubId","name":"Blues Lovers",'
    '"description":"Slow blues, every Tuesday.",'
    '"visibility":"discoverable","tags":[],'
    '"owner_public_id":"$_ownerId","member_count":12,'
    '"my_role":$myRole,"join_request_pending":false,'
    '"created_at":"2026-09-01T09:00:00Z",'
    '"updated_at":"2026-09-10T09:00:00Z",'
    '"resource_version":"2026-09-10T09:00:00Z"}';

void main() {
  group('reads', () {
    test('listClubs GETs /community/clubs?limit= and decodes items', () async {
      final adapter = _ok(
        '{"items":[${_clubOut()},${_clubOut(myRole: 'null')}],'
        '"next_cursor":"tok"}',
      );
      final repo = _buildRepo(adapter);

      final page = await repo.listClubs(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      final options = adapter.captured.single;
      expect(options.method, 'GET');
      expect(options.uri.path, '/community/clubs');
      expect(options.uri.queryParameters['limit'], '25');
      expect(options.uri.queryParameters.containsKey('cursor'), isFalse);
      expect(page.items, hasLength(2));
      final club = page.items.first;
      expect(club.id, ContentId(_clubId));
      expect(club.name, 'Blues Lovers');
      expect(club.visibility, ClubVisibility.discoverable);
      expect(club.ownerId, PublicUserId(_ownerId));
      expect(club.memberCount, 12);
      expect(club.myRole, ClubRole.owner);
      expect(club.tags, isEmpty);
      expect(page.items[1].myRole, isNull);
      expect(page.cursor, const CursorPage.continued('tok'));
    });

    test('listClubs forwards a continued cursor', () async {
      final adapter = _ok('{"items":[],"next_cursor":null}');
      final repo = _buildRepo(adapter);

      final page = await repo.listClubs(
        cursor: const CursorPage.continued('tok'),
        limit: 5,
      );

      expect(adapter.captured.single.uri.queryParameters['cursor'], 'tok');
      expect(page.cursor, const CursorPage.haltedAfterRequest());
    });

    test('fetchClub GETs /community/clubs/{id}', () async {
      final adapter = _ok(_clubOut(myRole: '"member"'));
      final repo = _buildRepo(adapter);

      final club = await repo.fetchClub(clubId: ContentId(_clubId));

      expect(adapter.captured.single.method, 'GET');
      expect(adapter.captured.single.path, '/community/clubs/$_clubId');
      expect(club.myRole, ClubRole.member);
    });

    test('an unknown my_role is a bad-response failure, not a guess', () {
      final adapter = _ok(_clubOut(myRole: '"emperor"'));
      final repo = _buildRepo(adapter);

      expect(
        repo.fetchClub(clubId: ContentId(_clubId)),
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

  group('writes', () {
    test('createClub POSTs exactly the CreateClubRequest keys', () async {
      final adapter = _ok(_clubOut(), status: 201);
      final repo = _buildRepo(adapter);

      final club = await repo.createClub(
        name: 'Blues Lovers',
        description: 'Slow blues, every Tuesday.',
        visibility: ClubVisibility.discoverable,
        tags: const <String>[],
        idempotencyKey: 'k-create',
      );

      final options = adapter.captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/clubs');
      final body = options.data as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'name',
        'description',
        'visibility',
        'tags',
        'idempotency_key',
      });
      expect(body['visibility'], 'discoverable');
      expect(body['idempotency_key'], 'k-create');
      expect(club.id, ContentId(_clubId));
    });

    test('createClub maps a 409 to communityConflict', () {
      final adapter = _ok('{"detail":"idempotency_collision"}', status: 409);
      final repo = _buildRepo(adapter);

      expect(
        repo.createClub(
          name: 'x',
          description: '',
          visibility: ClubVisibility.private,
          tags: const <String>[],
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

    test('updateClub PATCHes /community/clubs/{id} with exactly the '
        'UpdateClubRequest keys and decodes the 200 ClubOut', () async {
      final adapter = _ok(_clubOut());
      final repo = _buildRepo(adapter);

      final club = await repo.updateClub(
        clubId: ContentId(_clubId),
        description: 'Slow blues, every Tuesday.',
        visibility: ClubVisibility.discoverable,
        tags: const <String>['blues'],
        resourceVersion: '2026-09-10T09:00:00Z',
        idempotencyKey: 'k-update',
      );

      expect(adapter.captured, hasLength(1));
      final options = adapter.captured.single;
      expect(options.method, 'PATCH');
      expect(options.path, '/community/clubs/$_clubId');
      final body = options.data as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'description',
        'visibility',
        'tags',
        'resource_version',
        'idempotency_key',
      });
      expect(body['description'], 'Slow blues, every Tuesday.');
      expect(body['visibility'], 'discoverable');
      expect(body['tags'], <String>['blues']);
      expect(body['resource_version'], '2026-09-10T09:00:00Z');
      expect(body['idempotency_key'], 'k-update');
      expect(club.id, ContentId(_clubId));
      expect(club.visibility, ClubVisibility.discoverable);
      expect(club.myRole, ClubRole.owner);
    });

    test('updateClub sends a DateTime resourceVersion as UTC '
        'ISO-8601', () async {
      final adapter = _ok(_clubOut());
      final repo = _buildRepo(adapter);

      await repo.updateClub(
        clubId: ContentId(_clubId),
        description: 'd',
        visibility: ClubVisibility.public,
        tags: const <String>[],
        resourceVersion: DateTime.utc(2026, 9, 10, 9),
        idempotencyKey: 'k',
      );

      final body = adapter.captured.single.data as Map<String, Object?>;
      expect(body['resource_version'], '2026-09-10T09:00:00.000Z');
    });

    test('updateClub maps a 409 (stale resource_version) to '
        'communityConflict', () {
      final adapter = _ok(
        '{"detail":{"error":"stale_resource_version",'
        '"resource_version":"2026-09-11T09:00:00Z"}}',
        status: 409,
      );
      final repo = _buildRepo(adapter);

      expect(
        repo.updateClub(
          clubId: ContentId(_clubId),
          description: 'd',
          visibility: ClubVisibility.public,
          tags: const <String>[],
          resourceVersion: '2026-09-10T09:00:00Z',
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

    test('updateClub maps a 403 (non-owner) to '
        'AuthenticationFailure(auth.forbidden)', () {
      final adapter = _ok('{"detail":"owner only"}', status: 403);
      final repo = _buildRepo(adapter);

      expect(
        repo.updateClub(
          clubId: ContentId(_clubId),
          description: 'd',
          visibility: ClubVisibility.public,
          tags: const <String>[],
          resourceVersion: '2026-09-10T09:00:00Z',
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<AuthenticationFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.authForbidden,
          ),
        ),
      );
    });

    test('updateClub maps a 404 (not visible) to '
        'NetworkFailure(network.bad_response)', () {
      final adapter = _ok('{"detail":"club not found"}', status: 404);
      final repo = _buildRepo(adapter);

      expect(
        repo.updateClub(
          clubId: ContentId(_clubId),
          description: 'd',
          visibility: ClubVisibility.public,
          tags: const <String>[],
          resourceVersion: '2026-09-10T09:00:00Z',
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

    test('updateClub maps a 5xx to a retryable '
        'NetworkFailure(network.server)', () {
      final adapter = _ok('{"detail":"boom"}', status: 500);
      final repo = _buildRepo(adapter);

      expect(
        repo.updateClub(
          clubId: ContentId(_clubId),
          description: 'd',
          visibility: ClubVisibility.public,
          tags: const <String>[],
          resourceVersion: '2026-09-10T09:00:00Z',
          idempotencyKey: 'k',
        ),
        throwsA(
          isA<NetworkFailure>()
              .having((f) => f.code, 'code', FailureCode.networkServer)
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('requestJoin POSTs …/join with the idempotency key', () async {
      final adapter = _ok(_clubOut(myRole: '"member"'));
      final repo = _buildRepo(adapter);

      await repo.requestJoin(clubId: ContentId(_clubId), idempotencyKey: 'kj');

      final options = adapter.captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/clubs/$_clubId/join');
      expect((options.data as Map<String, Object?>)['idempotency_key'], 'kj');
    });

    test('leave POSTs …/leave', () async {
      final adapter = _ok('{"club_public_id":"$_clubId","left":true}');
      final repo = _buildRepo(adapter);

      await repo.leave(clubId: ContentId(_clubId), idempotencyKey: 'kl');

      expect(adapter.captured.single.method, 'POST');
      expect(adapter.captured.single.path, '/community/clubs/$_clubId/leave');
    });

    test('invite POSTs …/invites with invitee_public_id', () async {
      final adapter = _ok('{}', status: 201);
      final repo = _buildRepo(adapter);

      await repo.invite(
        clubId: ContentId(_clubId),
        target: PublicUserId(_memberId),
        idempotencyKey: 'ki',
      );

      final options = adapter.captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/clubs/$_clubId/invites');
      final body = options.data as Map<String, Object?>;
      expect(body['invitee_public_id'], _memberId);
      expect(body['idempotency_key'], 'ki');
    });

    test('removeMember DELETEs …/members/{id}?idempotency_key=', () async {
      final adapter = _ok('{}');
      final repo = _buildRepo(adapter);

      await repo.removeMember(
        clubId: ContentId(_clubId),
        memberId: PublicUserId(_memberId),
        idempotencyKey: 'kr',
      );

      final options = adapter.captured.single;
      expect(options.method, 'DELETE');
      expect(
        options.uri.path,
        '/community/clubs/$_clubId/members/$_memberId',
      );
      expect(options.uri.queryParameters['idempotency_key'], 'kr');
    });

    test('transferOwnership POSTs …/transfer-ownership', () async {
      final adapter = _ok(_clubOut(myRole: '"member"'));
      final repo = _buildRepo(adapter);

      await repo.transferOwnership(
        clubId: ContentId(_clubId),
        newOwnerId: PublicUserId(_memberId),
        idempotencyKey: 'kt',
      );

      final options = adapter.captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/clubs/$_clubId/transfer-ownership');
      final body = options.data as Map<String, Object?>;
      expect(body['new_owner_public_id'], _memberId);
      expect(body['idempotency_key'], 'kt');
    });

    test('a failed write throws — no silent no-op (L309)', () {
      final adapter = _ok('{}', status: 500);
      final repo = _buildRepo(adapter);

      expect(
        repo.leave(clubId: ContentId(_clubId), idempotencyKey: 'k'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('factory', () {
    test('null client → disabled stand-in throwing ConfigurationFailure', () {
      final repo = createCommunityClubRepository(null);

      expect(repo, isA<DisabledCommunityClubRepository>());
      expect(
        repo.listClubs(cursor: const CursorPage.initial(), limit: 1),
        throwsA(isA<ConfigurationFailure>()),
      );
    });

    test('a client → the HTTP implementation', () {
      expect(
        createCommunityClubRepository(ApiClient(Dio())),
        isA<HttpCommunityClubRepository>(),
      );
    });
  });
}
