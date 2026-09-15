/// Wire-format tests for ``HttpCommunitySocialGraphRepository``
/// (production wiring round 2026-09-15).
///
/// The decorator exists for one measured defect: the wrapped
/// ``HttpSocialGraphRepository`` never sends ``limit`` / ``cursor``
/// on the two follow-list reads (its ``params`` map is built and
/// dropped). These cells pin that the decorator DOES send them, that
/// the ``public_ids`` envelope still decodes to placeholder rows, and
/// that every other method reaches the wrapped implementation's
/// route unchanged.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/social_graph_repository_impl.dart';
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

HttpCommunitySocialGraphRepository _buildRepo(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final client = ApiClient(dio);
  return HttpCommunitySocialGraphRepository(
    client,
    delegate: HttpSocialGraphRepository(client),
  );
}

_ScriptedAdapter _ok(String body) =>
    _ScriptedAdapter(onFetch: (_) => _CannedResponse(body: body, status: 200));

final PublicUserId _peer = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fb0');

void main() {
  group('follow lists forward the query string', () {
    test('followingPage sends limit=50 and no cursor first', () async {
      final adapter = _ok('{"public_ids":[],"next_cursor":null}');
      final repo = _buildRepo(adapter);

      final page = await repo.followingPage(
        userId: _peer,
        cursor: const CursorPage.initial(),
      );

      final options = adapter.captured.single;
      expect(options.method, 'GET');
      expect(options.uri.path, '/community/profiles/${_peer.value}/following');
      expect(options.uri.queryParameters['limit'], '50');
      expect(options.uri.queryParameters.containsKey('cursor'), isFalse);
      expect(page.items, isEmpty);
      expect(page.cursor, const CursorPage.haltedAfterRequest());
    });

    test('followersPage forwards a continued cursor', () async {
      final adapter = _ok('{"public_ids":[],"next_cursor":null}');
      final repo = _buildRepo(adapter);

      await repo.followersPage(
        userId: _peer,
        cursor: const CursorPage.continued('page-2'),
      );

      final options = adapter.captured.single;
      expect(options.uri.path, '/community/profiles/${_peer.value}/followers');
      expect(options.uri.queryParameters['limit'], '50');
      expect(options.uri.queryParameters['cursor'], 'page-2');
    });

    test('decodes the public_ids envelope into placeholder rows', () async {
      final adapter = _ok(
        '{"public_ids":["01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fb1",'
        '"01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fb2"],'
        '"next_cursor":"page-2"}',
      );
      final repo = _buildRepo(adapter);

      final page = await repo.followersPage(
        userId: _peer,
        cursor: const CursorPage.initial(),
      );

      expect(page.items, hasLength(2));
      expect(
        page.items[0].userId.value,
        '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fb1',
      );
      expect(
        page.items[1].userId.value,
        '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fb2',
      );
      expect(page.cursor, const CursorPage.continued('page-2'));
    });
  });

  group('every other method delegates unchanged', () {
    test('block reaches POST /community/profiles/{id}/block', () async {
      final adapter = _ok('{}');
      final repo = _buildRepo(adapter);

      await repo.block(target: _peer, idempotencyKey: 'k-block');

      final options = adapter.captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/profiles/${_peer.value}/block');
      expect(
        (options.data as Map<String, Object?>)['idempotency_key'],
        'k-block',
      );
    });

    test('unfollow reaches DELETE …/follow?idempotency_key=', () async {
      final adapter = _ok('{}');
      final repo = _buildRepo(adapter);

      await repo.unfollow(target: _peer, idempotencyKey: 'k-unfollow');

      final options = adapter.captured.single;
      expect(options.method, 'DELETE');
      expect(options.uri.path, '/community/profiles/${_peer.value}/follow');
      expect(options.uri.queryParameters['idempotency_key'], 'k-unfollow');
    });

    test('blockedProfilesPage reaches GET /community/blocked', () async {
      final adapter = _ok('{"public_ids":[],"next_cursor":null}');
      final repo = _buildRepo(adapter);

      await repo.blockedProfilesPage(cursor: const CursorPage.initial());

      expect(adapter.captured.single.uri.path, '/community/blocked');
    });
  });

  group('factory', () {
    test('null client → the disabled stand-in', () {
      expect(
        createCommunitySocialGraphRepository(null),
        isA<DisabledSocialGraphRepository>(),
      );
    });

    test('a client → the cursor-forwarding decorator', () {
      expect(
        createCommunitySocialGraphRepository(ApiClient(Dio())),
        isA<HttpCommunitySocialGraphRepository>(),
      );
    });
  });
}
