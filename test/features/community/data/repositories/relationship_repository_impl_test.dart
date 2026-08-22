/// E09-R08 — Block / mute repository wiring tests.
///
/// Pin the wire-format of the Kör 8 block / mute methods on the
/// real ``HttpSocialGraphRepository``. The Kör 7 §F3 group already
/// proves the same shape for ``unfollow`` / ``removeFollower`` —
///
/// * ``POST /community/profiles/{id}/block`` with
///   ``idempotency_key`` in the JSON body.
/// * ``DELETE /community/profiles/{id}/block?idempotency_key=...``
///   for unblock.
/// * Same for ``mute`` / ``unmute``.
/// * ``GET /community/blocked?cursor=&limit=`` and
///   ``GET /community/muted?cursor=&limit=`` for the list
///   endpoints the §D5 Blocked/Muted settings screen consumes.
///
/// A regression that drops the ``?idempotency_key=...`` query
/// parameter on the DELETE paths would land here — the same
/// measured footgun the §F3 group captured for the follow
/// endpoints.
///
/// The list-endpoint tests also assert the placeholder-profile
/// decode (the Kör 7 ``_decodePage`` envelope — a list of
/// ``public_ids`` becomes ``CommunityPage<CommunityProfile>`` with
/// placeholder profiles, the Kör 8 §3 documented contract).
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
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

HttpSocialGraphRepository _buildRepo(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HttpSocialGraphRepository(ApiClient(dio));
}

void main() {
  group('E09-R08 block / mute wire format', () {
    late List<RequestOptions> captured;
    late _ScriptedAdapter adapter;

    setUp(() {
      captured = <RequestOptions>[];
      adapter = _ScriptedAdapter(
        onFetch: (_) => const _CannedResponse(body: '{}', status: 200),
      );
      // Make the captured list shared between adapter + test.
      captured = adapter.captured;
    });

    test('block() POSTs to /community/profiles/{id}/block with body', () async {
      final repo = _buildRepo(adapter);
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa0');
      final key = 'block-key-1';

      await repo.block(target: target, idempotencyKey: key);

      expect(captured, hasLength(1));
      final options = captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/profiles/${target.value}/block');
      // Body carries the idempotency_key as a JSON field — same
      // shape as the Kör 7 follow POST.
      expect(options.data, isA<Map<String, Object?>>());
      expect(
        (options.data as Map<String, Object?>)['idempotency_key'],
        key,
      );
    });

    test('unblock() DELETEs with ?idempotency_key=...', () async {
      final repo = _buildRepo(adapter);
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa1');
      final key = 'unblock-key-1';

      await repo.unblock(target: target, idempotencyKey: key);

      expect(captured, hasLength(1));
      final options = captured.single;
      expect(options.method, 'DELETE');
      expect(
        options.path,
        '/community/profiles/${target.value}/block'
        '?idempotency_key=$key',
      );
      expect(options.uri.queryParameters['idempotency_key'], key);
    });

    test('mute() POSTs to /community/profiles/{id}/mute with body', () async {
      final repo = _buildRepo(adapter);
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa2');
      final key = 'mute-key-1';

      await repo.mute(target: target, idempotencyKey: key);

      expect(captured, hasLength(1));
      final options = captured.single;
      expect(options.method, 'POST');
      expect(options.path, '/community/profiles/${target.value}/mute');
      expect(
        (options.data as Map<String, Object?>)['idempotency_key'],
        key,
      );
    });

    test('unmute() DELETEs with ?idempotency_key=...', () async {
      final repo = _buildRepo(adapter);
      final target = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa3');
      final key = 'unmute-key-1';

      await repo.unmute(target: target, idempotencyKey: key);

      expect(captured, hasLength(1));
      final options = captured.single;
      expect(options.method, 'DELETE');
      expect(
        options.path,
        '/community/profiles/${target.value}/mute'
        '?idempotency_key=$key',
      );
      expect(options.uri.queryParameters['idempotency_key'], key);
    });
  });

  group('E09-R08 block / mute list endpoints', () {
    late _ScriptedAdapter adapter;

    setUp(() {
      adapter = _ScriptedAdapter(
        onFetch: (_) => const _CannedResponse(
          body: '{"public_ids":[],"next_cursor":null}',
          status: 200,
        ),
      );
    });

    test('blockedProfilesPage() GETs /community/blocked with limit',
        () async {
      final repo = _buildRepo(adapter);

      final page = await repo.blockedProfilesPage(
        cursor: const CursorPage.initial(),
      );

      expect(adapter.captured, hasLength(1));
      final options = adapter.captured.single;
      expect(options.method, 'GET');
      expect(options.path, '/community/blocked');
      // The cursor-less initial request must NOT carry a cursor
      // query parameter — only the limit.
      expect(options.uri.queryParameters['limit'], '50');
      expect(options.uri.queryParameters.containsKey('cursor'), isFalse);
      // The decoded page is an empty CommunityPage envelope.
      expect(page.items, isEmpty);
    });

    test('mutedProfilesPage() GETs /community/muted with limit', () async {
      final repo = _buildRepo(adapter);

      final page = await repo.mutedProfilesPage(
        cursor: const CursorPage.initial(),
      );

      expect(adapter.captured, hasLength(1));
      final options = adapter.captured.single;
      expect(options.method, 'GET');
      expect(options.path, '/community/muted');
      expect(options.uri.queryParameters['limit'], '50');
      expect(options.uri.queryParameters.containsKey('cursor'), isFalse);
      expect(page.items, isEmpty);
    });

    test('blockedProfilesPage() forwards a non-initial cursor', () async {
      final repo = _buildRepo(adapter);
      final token = 'next-page-token';

      await repo.blockedProfilesPage(
        cursor: CursorPage.continued(token),
      );

      final options = adapter.captured.single;
      expect(options.uri.queryParameters['cursor'], token);
    });

    test(
      'blockedProfilesPage() decodes a public_ids envelope into '
      'placeholder CommunityProfile rows',
      () async {
        adapter = _ScriptedAdapter(
          onFetch: (_) => const _CannedResponse(
            body:
                '{"public_ids":["01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa4",'
                '"01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa5"],'
                '"next_cursor":null}',
            status: 200,
          ),
        );
        final repo = _buildRepo(adapter);

        final CommunityPage<CommunityProfile> page = await repo
            .blockedProfilesPage(cursor: const CursorPage.initial());

        expect(page.items, hasLength(2));
        expect(
          page.items[0].userId.value,
          '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa4',
        );
        expect(
          page.items[1].userId.value,
          '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5fa5',
        );
      },
    );
  });
}
