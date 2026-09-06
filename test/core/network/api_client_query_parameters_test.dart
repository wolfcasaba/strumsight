// A `getJson` query-paraméter továbbításának őre.
//
// MÉRT hibaosztály (2026-09-05): az `ApiClient.getJson` NEM fogadott
// query-paramétert, miközben három community-repository felépítette a
// `{'limit': …, 'cursor': …}` térképet — és NEM adta át sehova. A Dart
// analyzer erre néma (a lokális változó fel van használva a `params[...] =`
// sorban), a tesztek pedig fake repository-kkal mentek, tehát a rés a
// szerverig sosem látszott: minden community-lista lapozása az első
// alapértelmezett oldalt kérte újra.
//
// Ez a teszt a TÉNYLEGES kimenő kérést méri egy Dio-interceptorral, nem a
// hívó szándékát.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/network/api_client.dart';

/// A kimenő kérést rögzítő, hálózat NÉLKÜLI adapter.
class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      '{"ok": true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late _RecordingAdapter adapter;
  late ApiClient client;

  setUp(() {
    adapter = _RecordingAdapter();
    dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.httpClientAdapter = adapter;
    client = ApiClient(dio);
  });

  test('a getJson query-paraméterei ELMENNEK a kérésben', () async {
    await client.getJson<Object?>(
      '/community/feed',
      queryParameters: const {'page_size': 25, 'cursor': 'opaque-token'},
      decode: (json) => json,
      requiresAuthentication: false,
    );

    // A hibaosztály mércéje: a paraméterek eldobása esetén ez üres.
    expect(adapter.lastRequest, isNotNull);
    expect(adapter.lastRequest!.queryParameters, <String, Object?>{
      'page_size': 25,
      'cursor': 'opaque-token',
    });
  });

  test(
    'a null értékű kulcsok KIMARADNAK — az extra="forbid" sémák miatt',
    () async {
      await client.getJson<Object?>(
        '/community/feed',
        queryParameters: const {'page_size': 25, 'cursor': null},
        decode: (json) => json,
        requiresAuthentication: false,
      );

      expect(adapter.lastRequest!.queryParameters, <String, Object?>{
        'page_size': 25,
      });
      expect(
        adapter.lastRequest!.queryParameters.containsKey('cursor'),
        isFalse,
      );
    },
  );

  test(
    'query-paraméter NÉLKÜL a kérés változatlan (visszafelé kompatibilis)',
    () async {
      await client.getJson<Object?>(
        '/settings',
        decode: (json) => json,
        requiresAuthentication: false,
      );

      expect(adapter.lastRequest!.queryParameters, isEmpty);
    },
  );
}
