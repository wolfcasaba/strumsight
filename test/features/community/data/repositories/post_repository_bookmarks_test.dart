// A könyvjelző-lista bekötésének mérése (javító sáv R5, 2026-09-06) — a
// TÉNYLEGES kimenő kérésen és a TÉNYLEGES szerver-válasz alakján.
//
// MÉRT hiány: a `BookmarksScreen` egy no-op vezérlőre épült, a
// `GET /community/bookmarks` (E09-R17) végpontot a kliens SOHA nem hívta.
//
// A bekötés négy ponton dönthetett rosszul, mindegyiket cella méri:
//
//   1. a lapméret neve — a végpont `limit`-et olvas, NEM `page_size`-t
//      (a komment-lista mintája itt némán eldobott paraméter volna),
//   2. a lapozás elnyelése (a kurzor felépül, de nem megy ki),
//   3. a lista végének összemosása az első kéréssel (`halted` vs
//      `initial`),
//   4. a sírkő-zászló (`is_tombstone`) elvesztése — a képernyő §A3 felülete.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  Map<String, Object?> body = const <String, Object?>{};
  int status = 200;

  RequestOptions get last => requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const String _postA = '11111111-1111-4111-8111-111111111111';
const String _postB = '22222222-2222-4222-8222-222222222222';

Map<String, Object?> _bookmarkJson({
  required int id,
  required String postId,
  bool tombstone = false,
}) => <String, Object?>{
  'bookmark_id': id,
  'post_public_id': postId,
  'created_at': '2026-09-06T10:00:00Z',
  'is_tombstone': tombstone,
};

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityPostRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityPostRepository(ApiClient(dio));
  });

  group('listBookmarks', () {
    test('K1 — a lista a /community/bookmarks-ra megy, `limit`-tel és '
        'kurzor nélkül az első kérésen', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      await repository.listBookmarks(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(adapter.last.path, '/community/bookmarks');
      expect(adapter.last.method, 'GET');
      expect(adapter.last.queryParameters['limit'], 25);
      expect(adapter.last.queryParameters.containsKey('page_size'), isFalse);
      expect(adapter.last.queryParameters.containsKey('cursor'), isFalse);
    });

    test('K2 — a kurzor kimegy, és a következő kurzor visszajön', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': 'next-token',
      };

      final page = await repository.listBookmarks(
        cursor: const CursorPage.continued('opaque'),
        limit: 10,
      );

      expect(adapter.last.queryParameters['cursor'], 'opaque');
      expect(page.cursor, const CursorPage.continued('next-token'));
    });

    test(
      'K3 — a lista vége HALTED, nem INITIAL, és a sírkő megmarad',
      () async {
        adapter.body = <String, Object?>{
          'items': <Object?>[
            _bookmarkJson(id: 7, postId: _postA),
            _bookmarkJson(id: 3, postId: _postB, tombstone: true),
          ],
          'next_cursor': null,
        };

        final page = await repository.listBookmarks(
          cursor: const CursorPage.continued('t'),
          limit: 25,
        );

        expect(page.cursor, const CursorPage.haltedAfterRequest());
        expect(page.isHaltedAfterRequest, isTrue);
        expect(page.items.map((row) => row.id), <int>[7, 3]);
        expect(page.items.first.postId, ContentId(_postA));
        expect(page.items.first.isTombstone, isFalse);
        expect(page.items.last.isTombstone, isTrue);
        expect(page.items.first.createdAt, DateTime.utc(2026, 9, 6, 10));
      },
    );

    test('K4 — a hiányzó kötelező mező kivétel, nem üres sor', () async {
      adapter.body = <String, Object?>{
        'items': <Object?>[
          <String, Object?>{'post_public_id': _postA},
        ],
        'next_cursor': null,
      };

      await expectLater(
        repository.listBookmarks(cursor: const CursorPage.initial(), limit: 5),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
