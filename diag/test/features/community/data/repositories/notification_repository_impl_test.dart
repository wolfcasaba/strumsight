/// Wire-format tests for ``HttpCommunityNotificationRepository``
/// (production wiring round 2026-09-15).
///
/// Pins the five routes the implementation is coded against (the
/// backend inbox SERVICE exists, its HTTP router does not yet — see
/// the impl's library comment), the ``items`` / ``next_cursor``
/// envelope decode, the unknown-kind drop (A3), and the measured
/// today-behaviour: a 404 from the missing router surfaces as the
/// typed ``NetworkFailure(networkBadResponse)``, never as a silent
/// empty page.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/notification_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/notification_item.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';

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

HttpCommunityNotificationRepository _buildRepo(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HttpCommunityNotificationRepository(ApiClient(dio));
}

_ScriptedAdapter _ok(String body) => _ScriptedAdapter(
  onFetch: (_) => _CannedResponse(body: body, status: 200),
);

const String _inboxBody =
    '{"items":['
    '{"public_id":"n1","type":"challenge_invite",'
    '"title_key":"communityNotificationChallengeInviteTitle",'
    '"body_key":null,"entity_type":"challenge","entity_id":"ch-1",'
    '"is_read":false,"created_at":"2026-09-15T10:00:00Z"},'
    '{"public_id":"n2","type":"comment",'
    '"title_key":"communityNotificationCommentTitle",'
    '"body_key":"communityNotificationCommentBody",'
    '"related_content_id":null,'
    '"is_read":true,"created_at":"2026-09-14T10:00:00Z"},'
    '{"public_id":"n3","type":"kind_from_the_future",'
    '"title_key":"communityNotificationCommentTitle",'
    '"is_read":false,"created_at":"2026-09-13T10:00:00Z"}'
    '],"next_cursor":"tok-2"}';

void main() {
  group('inboxPage', () {
    test('GETs /community/notifications with limit, no cursor first', () async {
      final adapter = _ok(_inboxBody);
      final repo = _buildRepo(adapter);

      final page = await repo.inboxPage(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      final options = adapter.captured.single;
      expect(options.method, 'GET');
      expect(options.uri.path, '/community/notifications');
      expect(options.uri.queryParameters['limit'], '25');
      expect(options.uri.queryParameters.containsKey('cursor'), isFalse);
      // Two decodable rows; the unknown-kind row is dropped (A3),
      // not fatal.
      expect(page.items, hasLength(2));
      expect(page.items[0].id, ContentId('n1'));
      expect(page.items[0].kind, CommunityNotificationKind.challengeInvite);
      expect(page.items[0].isRead, isFalse);
      expect(page.items[0].relatedContentId, ContentId('ch-1'));
      expect(page.items[1].kind, CommunityNotificationKind.comment);
      expect(page.items[1].bodyKey, 'communityNotificationCommentBody');
      expect(page.items[1].relatedContentId, isNull);
      expect(page.cursor, const CursorPage.continued('tok-2'));
    });

    test('forwards a continued cursor', () async {
      final adapter = _ok('{"items":[],"next_cursor":null}');
      final repo = _buildRepo(adapter);

      final page = await repo.inboxPage(
        cursor: const CursorPage.continued('tok-2'),
        limit: 10,
      );

      expect(adapter.captured.single.uri.queryParameters['cursor'], 'tok-2');
      expect(page.items, isEmpty);
      expect(page.cursor, const CursorPage.haltedAfterRequest());
    });

    test('a 404 (router not deployed) is a typed bad-response failure', () {
      final adapter = _ScriptedAdapter(
        onFetch: (_) =>
            const _CannedResponse(body: '{"detail":"Not Found"}', status: 404),
      );
      final repo = _buildRepo(adapter);

      expect(
        repo.inboxPage(cursor: const CursorPage.initial(), limit: 25),
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

  group('mutations', () {
    test('markRead POSTs /community/notifications/{id}/read', () async {
      final adapter = _ok('{}');
      final repo = _buildRepo(adapter);

      await repo.markRead(
        notificationId: ContentId('n1'),
        idempotencyKey: 'k-1',
      );

      final options = adapter.captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/notifications/n1/read');
      expect((options.data as Map<String, Object?>)['idempotency_key'], 'k-1');
    });

    test('markAllReadUpTo POSTs read-all with the cutoff id', () async {
      final adapter = _ok('{}');
      final repo = _buildRepo(adapter);

      await repo.markAllReadUpTo(
        upToId: ContentId('n9'),
        idempotencyKey: 'k-2',
      );

      final options = adapter.captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/notifications/read-all');
      final body = options.data as Map<String, Object?>;
      expect(body['up_to_public_id'], 'n9');
      expect(body['idempotency_key'], 'k-2');
    });

    test('updatePreference PUTs preferences/{category}', () async {
      final adapter = _ok('{}');
      final repo = _buildRepo(adapter);

      await repo.updatePreference(
        category: 'comment',
        level: 'push',
        idempotencyKey: 'k-3',
      );

      final options = adapter.captured.single;
      expect(options.method, 'PUT');
      expect(options.path, '/community/notifications/preferences/comment');
      final body = options.data as Map<String, Object?>;
      expect(body['level'], 'push');
      expect(body['idempotency_key'], 'k-3');
    });

    test('a failed mutation throws — no silent no-op (L309)', () {
      final adapter = _ScriptedAdapter(
        onFetch: (_) => const _CannedResponse(body: '{}', status: 500),
      );
      final repo = _buildRepo(adapter);

      expect(
        repo.markRead(notificationId: ContentId('n1'), idempotencyKey: 'k'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('preferences', () {
    test('GETs the bare category→level map', () async {
      final adapter = _ok('{"comment":"push","mention":"disabled"}');
      final repo = _buildRepo(adapter);

      final prefs = await repo.preferences();

      expect(adapter.captured.single.method, 'GET');
      expect(
        adapter.captured.single.path,
        '/community/notifications/preferences',
      );
      expect(prefs, <String, String>{'comment': 'push', 'mention': 'disabled'});
    });

    test('accepts a {"preferences": {...}} envelope too', () async {
      final adapter = _ok('{"preferences":{"comment":"inApp","x":1}}');
      final repo = _buildRepo(adapter);

      final prefs = await repo.preferences();

      expect(prefs, <String, String>{'comment': 'inApp'});
    });
  });

  group('factory', () {
    test('null client → disabled stand-in throwing ConfigurationFailure', () {
      final repo = createCommunityNotificationRepository(null);

      expect(repo, isA<DisabledCommunityNotificationRepository>());
      expect(
        repo.inboxPage(cursor: const CursorPage.initial(), limit: 1),
        throwsA(isA<ConfigurationFailure>()),
      );
      expect(repo.preferences(), throwsA(isA<ConfigurationFailure>()));
    });

    test('a client → the HTTP implementation', () {
      final repo = createCommunityNotificationRepository(ApiClient(Dio()));

      expect(repo, isA<HttpCommunityNotificationRepository>());
    });
  });
}
