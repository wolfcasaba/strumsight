// A tartalom-bejelentés kimenő kérésének mérése (R33, M10).
//
// A `showReportContentSheet` E09-R26 óta készen állt, a
// `POST /community/reports` router szintén — és `lib/**`-ban SENKI nem
// hívta egyiket sem. Ez a fájl a most bekötött adat-réteget méri a
// TÉNYLEGES kimenő kérésen (Dio-adapter), nem fake repository-n:
//
//   R1 — az útvonal, az ige és a törzs NÉGY kulcsa,
//   R2 — az `extra_metadata` NEM megy ki (a lap nem gyűjt szabad szöveget),
//   R3 — a sanitizált válasz két olvasott mezője,
//   R4 — a hiányzó `deduplicated` „friss sor", nem hiba,
//   R5 — a `report_public_id` nélküli válasz NEM ad nyugtát.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';

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

const String _reportId = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01';
const String _postId = '11111111-1111-4111-8111-111111111111';

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityPostRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityPostRepository(ApiClient(dio));
  });

  Map<String, Object?> sentBody() => adapter.last.data! as Map<String, Object?>;

  test('R1 — POST /community/reports a négy kötelező kulccsal', () async {
    adapter.body = const <String, Object?>{
      'report_public_id': _reportId,
      'deduplicated': false,
    };

    await repository.submitReport(
      targetType: 'post',
      targetId: _postId,
      category: 'spam',
      idempotencyKey: 'rp-1',
    );

    expect(adapter.last.path, '/community/reports');
    expect(adapter.last.method, 'POST');
    expect(sentBody()['target_type'], 'post');
    expect(sentBody()['target_id'], _postId);
    expect(sentBody()['category'], 'spam');
    expect(sentBody()['idempotency_key'], 'rp-1');
  });

  test('R2 — az extra_metadata NEM megy ki', () async {
    // A lap ma nem gyűjti be a bejelentő szabad szövegét. Egy üres
    // objektum kiküldése azt sugallná, hogy van mit beleírni.
    adapter.body = const <String, Object?>{
      'report_public_id': _reportId,
      'deduplicated': false,
    };

    await repository.submitReport(
      targetType: 'comment',
      targetId: _postId,
      category: 'harassment',
      idempotencyKey: 'rp-2',
    );

    expect(sentBody().containsKey('extra_metadata'), isFalse);
    expect(sentBody().keys.toSet(), <String>{
      'target_type',
      'target_id',
      'category',
      'idempotency_key',
    });
  });

  test('R3 — a nyugta a két olvasott mezőt hozza', () async {
    adapter.body = const <String, Object?>{
      'report_public_id': _reportId,
      'target_type': 'post',
      'target_id': _postId,
      'category': 'spam',
      'created_at': '2026-09-08T10:00:00Z',
      'deduplicated': true,
    };

    final receipt = await repository.submitReport(
      targetType: 'post',
      targetId: _postId,
      category: 'spam',
      idempotencyKey: 'rp-3',
    );

    expect(receipt.reportPublicId, _reportId);
    expect(receipt.deduplicated, isTrue);
  });

  test('R4 — a hiányzó deduplicated friss sort jelent', () async {
    adapter.body = const <String, Object?>{'report_public_id': _reportId};

    final receipt = await repository.submitReport(
      targetType: 'post',
      targetId: _postId,
      category: 'spam',
      idempotencyKey: 'rp-4',
    );

    expect(receipt.deduplicated, isFalse);
  });

  test('R5 — azonosító nélküli válasz nem ad nyugtát', () async {
    // Nyugta nélkül nem mondhatjuk a bejelentőnek, hogy megérkezett.
    adapter.body = const <String, Object?>{'deduplicated': false};

    await expectLater(
      repository.submitReport(
        targetType: 'post',
        targetId: _postId,
        category: 'spam',
        idempotencyKey: 'rp-5',
      ),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          FailureCode.networkBadResponse,
        ),
      ),
    );
  });
}
