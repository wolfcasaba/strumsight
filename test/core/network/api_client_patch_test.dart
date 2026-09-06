// Az `ApiClient.patchJson` primitív őre.
//
// MÉRT hibaosztály (2026-09-06): az `ApiClient` öt igét ismert
// (`getJson` / `postJson` / `putJson` / `post` / `delete`), a szerver
// HÁROM szerkesztő végpontja viszont `PATCH`-et vár
// (`PATCH /community/posts/{id}`, `.../comments/{id}`, `.../clubs/{id}`).
// A három repository-metódus emiatt `UnimplementedError`-t dobott, és a
// `comment_controller.editComment` ÉLESEN ebbe futott bele: a komment
// szerkesztése a CommentsScreen-en kivétellel végződött.
//
// A cellák a TÉNYLEGES kimenő kérést és a TÉNYLEGES hibaleképezést mérik,
// nem a hívó szándékát. A `putJson` a referencia: a `patchJson` annak
// pontos párja, csak az ige más — ezért minden állítás párban áll.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/core/network/auth_interceptor.dart';

/// A kimenő kérést rögzítő, hálózat NÉLKÜLI adapter.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  Object? body = const <String, Object?>{'ok': true};
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

void main() {
  late _RecordingAdapter adapter;
  late ApiClient client;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = adapter;
    client = ApiClient(dio);
  });

  test('a patchJson PATCH igével megy ki, a törzzsel együtt', () async {
    adapter.body = const <String, Object?>{'public_id': 'p-1'};

    final result = await client.patchJson<String>(
      '/community/posts/p-1',
      data: const <String, Object?>{
        'body': 'új törzs',
        'resource_version': '2026-09-06T10:00:00.000Z',
      },
      decode: (json) => json['public_id']! as String,
    );

    // A hibaosztály mércéje: `PUT`-tal a FastAPI 405-öt adna.
    expect(adapter.last.method, 'PATCH');
    expect(adapter.last.path, '/community/posts/p-1');
    expect(adapter.last.data, <String, Object?>{
      'body': 'új törzs',
      'resource_version': '2026-09-06T10:00:00.000Z',
    });
    expect(result, isA<Success<String>>());
    expect((result as Success<String>).value, 'p-1');
  });

  test('a patchJson dekódolja a JSON-objektumot', () async {
    adapter.body = const <String, Object?>{'count': 7};

    final result = await client.patchJson<int>(
      '/community/clubs/c-1',
      data: const <String, Object?>{'description': 'x'},
      decode: (json) => json['count']! as int,
    );

    expect((result as Success<int>).value, 7);
  });

  test('a nem-objektum válasz networkBadResponse, nem néma siker', () async {
    adapter.body = const <Object?>[1, 2, 3];

    final result = await client.patchJson<Object?>(
      '/community/clubs/c-1',
      data: const <String, Object?>{'description': 'x'},
      decode: (json) => json,
    );

    expect(result, isA<Failure<Object?>>());
    expect(
      (result as Failure<Object?>).error.code,
      FailureCode.networkBadResponse,
    );
  });

  test(
    'a 409 ugyanúgy a conflictCode-ra képződik, mint a putJson-nál',
    () async {
      adapter.status = 409;
      adapter.body = const <String, Object?>{
        'detail': {'code': 'stale_resource_version'},
      };

      final patched = await client.patchJson<Object?>(
        '/community/comments/c-1',
        data: const <String, Object?>{'body': 'x'},
        decode: (json) => json,
        conflictCode: FailureCode.communityConflict,
      );
      final put = await client.putJson<Object?>(
        '/community/comments/c-1',
        data: const <String, Object?>{'body': 'x'},
        decode: (json) => json,
        conflictCode: FailureCode.communityConflict,
      );

      expect(patched, isA<Failure<Object?>>());
      final patchedFailure = (patched as Failure<Object?>).error;
      expect(patchedFailure, isA<ValidationFailure>());
      expect(patchedFailure.code, FailureCode.communityConflict);
      // A PUT referencia: a két leképezés ugyanaz.
      expect((put as Failure<Object?>).error.code, patchedFailure.code);
      expect(put.error.runtimeType, patchedFailure.runtimeType);
    },
  );

  test('a 401 / 403 / 422 leképezése a putJson-éval azonos', () async {
    for (final status in <int>[401, 403, 422, 500]) {
      adapter.status = status;
      adapter.body = const <String, Object?>{'detail': 'x'};

      final patched = await client.patchJson<Object?>(
        '/community/posts/p-1',
        data: const <String, Object?>{'body': 'x'},
        decode: (json) => json,
      );
      final put = await client.putJson<Object?>(
        '/community/posts/p-1',
        data: const <String, Object?>{'body': 'x'},
        decode: (json) => json,
      );

      final patchedFailure = (patched as Failure<Object?>).error;
      final putFailure = (put as Failure<Object?>).error;
      expect(patchedFailure.code, putFailure.code, reason: 'HTTP $status');
      expect(
        patchedFailure.runtimeType,
        putFailure.runtimeType,
        reason: 'HTTP $status',
      );
    }
  });

  test('a requiresAuthentication metaadat kimegy a kérés extráiban', () async {
    await client.patchJson<Object?>(
      '/community/posts/p-1',
      data: const <String, Object?>{'body': 'x'},
      decode: (json) => json,
      requiresAuthentication: false,
    );

    expect(
      adapter.last.extra[NetworkRequestMetadata.requiresAuthentication],
      isFalse,
    );
  });
}
