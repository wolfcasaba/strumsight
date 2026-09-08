/// Javító sáv R27 — a média-feltöltés kimenő kérése.
///
/// A repository média-metódusai egy RÖGZÍTŐ Dio-adapter fölött, hálózat
/// nélkül. Amit a cellák mérnek, az a HUZAL: milyen kérés megy ki, és mit
/// csinál a hívó a válasszal.
///
/// * A1 — a feltöltés `multipart/form-data`, a bájtok egy `file` nevű
///   részben. A fa egyetlen többrészes kérése; ha a törzs JSON-ná
///   csúszna, a szerver 422-t adna, és a hiba csak élesben derülne ki.
/// * A2 — a FELHASZNÁLÓ fájlneve nem megy ki. A szerver eldobja (a
///   tárolt út a tartalom lenyomatából áll), a naplóba viszont
///   bekerülhetne.
/// * A3 — az ELUTASÍTÁS nem kivétel: a 201 + `state: rejected` válasz
///   leíróként tér vissza, hogy a szerkesztő az okot ki tudja írni. Egy
///   dobott kivétel itt a felhasználót „a feltöltés elromlott" üzenettel
///   hagyná ott, holott a szerver pontosan megmondta, mi a baj.
/// * A4 — a valóban kivételes kimenetek (413, 409, 429) DOBNAK.
/// * A5 — a törlés a publikus azonosítóra megy, `DELETE` igével.
/// * A6 — a `media_ids` csak akkor kerül a poszt törzsébe, ha van mit
///   küldeni; az üres lista nem fogyaszt kulcsot.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_media.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';

const String _mediaPublicId = '55555555-5555-4555-8555-555555555555';
const String _clubPublicId = '44444444-4444-4444-8444-444444444444';

/// Hálózat NÉLKÜLI adapter: rögzíti a kérést (a törzset bájtokká
/// olvasva, hogy a többrészes keret is látszódjon) és egy előre megadott
/// választ ad vissza.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.status = 201, Map<String, Object?>? body})
    : body = body ?? _readyMediaBody();

  final int status;
  final Map<String, Object?> body;

  final List<RequestOptions> requests = <RequestOptions>[];
  final List<String> bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final flattened = <int>[for (final chunk in chunks) ...chunk];
      bodies.add(String.fromCharCodes(flattened));
    } else {
      bodies.add('');
    }
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

Map<String, Object?> _readyMediaBody({
  String state = 'ready',
  Object? rejectionCode,
}) {
  return <String, Object?>{
    'public_id': _mediaPublicId,
    'kind': 'image',
    'state': state,
    'rejection_code': rejectionCode,
    'content_type': 'image/jpeg',
    'size_bytes': 1234,
    'width': 640,
    'height': 480,
    'duration_ms': null,
    'created_at': '2026-09-08T10:00:00Z',
  };
}

Map<String, Object?> _postBody() => <String, Object?>{
  'public_id': '11111111-1111-4111-8111-111111111111',
  'author_public_id': '22222222-2222-4222-8222-222222222222',
  'audience': 'public',
  'body': 'törzs',
  'moderation_state': 'visible',
  'created_at': '2026-09-08T10:00:00Z',
  'resource_version': '2026-09-08T10:00:00Z',
  'media': <Map<String, Object?>>[_readyMediaBody()],
};

({HttpCommunityPostRepository repository, _RecordingAdapter adapter}) _build({
  int status = 201,
  Map<String, Object?>? body,
}) {
  final adapter = _RecordingAdapter(status: status, body: body);
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = adapter;
  return (
    repository: HttpCommunityPostRepository(ApiClient(dio)),
    adapter: adapter,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1/A2 — a feltöltés huzal-alakja', () {
    test('multipart törzs, a bájtok a `file` részben', () async {
      final built = _build();
      final bytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x11, 0x22, 0x33];

      await built.repository.uploadMedia(bytes: bytes, filename: 'x.bin');

      final request = built.adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/community/media');
      expect(
        request.headers[Headers.contentTypeHeader].toString(),
        contains('multipart/form-data'),
      );
      final wire = built.adapter.bodies.single;
      expect(wire, contains('name="file"'));
      // A bájtok tényleg a törzsben vannak (latin-1 olvasatban a
      // JPEG-szignatúra karakterei).
      expect(wire, contains(String.fromCharCodes(bytes)));
    });

    test('a FELHASZNÁLÓ fájlneve nem megy ki', () async {
      final built = _build();

      await built.repository.uploadMedia(
        bytes: <int>[1, 2, 3],
        filename: 'community-upload',
      );

      final wire = built.adapter.bodies.single;
      expect(wire, contains('filename="community-upload"'));
      // A hívó által megadott semleges név megy ki, nem az OS-é. A
      // szerkesztő ezt a konstanst adja, sosem a `PickedCommunityMedia`
      // `displayName`-jét.
      expect(wire, isNot(contains('IMG_20260908_gps.jpg')));
    });
  });

  group('A3 — az elutasítás LEÍRÓ, nem kivétel', () {
    test('201 + rejected ⇒ visszaadott leíró az okkal', () async {
      final built = _build(
        body: _readyMediaBody(
          state: 'rejected',
          rejectionCode: 'scriptable_media_rejected',
        ),
      );

      final media = await built.repository.uploadMedia(bytes: <int>[1]);

      expect(media.state, CommunityMediaState.rejected);
      expect(media.rejectionCode, 'scriptable_media_rejected');
      expect(media.isReady, isFalse);
    });

    test('201 + ready ⇒ kész leíró', () async {
      final built = _build();
      final media = await built.repository.uploadMedia(bytes: <int>[1]);
      expect(media.isReady, isTrue);
      expect(media.publicId, _mediaPublicId);
      expect(media.contentType, 'image/jpeg');
    });
  });

  group('A4 — a kivételes kimenetek dobnak', () {
    test('413 (túl nagy) dob', () async {
      final built = _build(status: 413, body: const <String, Object?>{});
      await expectLater(
        built.repository.uploadMedia(bytes: <int>[1]),
        throwsA(isA<AppFailure>()),
      );
    });

    test('409 (kvóta) dob', () async {
      final built = _build(status: 409, body: const <String, Object?>{});
      await expectLater(
        built.repository.uploadMedia(bytes: <int>[1]),
        throwsA(isA<AppFailure>()),
      );
    });

    test('429 (fojtás) dob', () async {
      final built = _build(status: 429, body: const <String, Object?>{});
      await expectLater(
        built.repository.uploadMedia(bytes: <int>[1]),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('A5 — törlés', () {
    test('DELETE a publikus azonosítóra', () async {
      final built = _build(status: 200, body: const <String, Object?>{});

      await built.repository.deleteMedia(mediaPublicId: _mediaPublicId);

      final request = built.adapter.requests.single;
      expect(request.method, 'DELETE');
      expect(request.path, '/community/media/$_mediaPublicId');
    });
  });

  group('A6 — media_ids a poszt törzsében', () {
    test('a megadott azonosítók kimennek, sorrendben', () async {
      final built = _build(body: _postBody());

      final post = await built.repository.createPost(
        audience: CommunityAudience.public,
        body: 'törzs',
        artifact: const <String, Object?>{},
        idempotencyKey: 'k-1',
        mediaIds: <String>[_mediaPublicId, 'aaaa'],
      );

      final sent = built.adapter.requests.single.data! as Map;
      expect(sent['media_ids'], <String>[_mediaPublicId, 'aaaa']);
      // A válasz csatolmánya az entitásra kerül.
      expect(post.media.single.publicId, _mediaPublicId);
    });

    test('ÜRES lista esetén a kulcs ki sem megy', () async {
      final built = _build(body: _postBody());

      await built.repository.createPost(
        audience: CommunityAudience.public,
        body: 'törzs',
        artifact: const <String, Object?>{},
        idempotencyKey: 'k-2',
      );

      final sent = built.adapter.requests.single.data! as Map;
      expect(sent.containsKey('media_ids'), isFalse);
    });

    test('az üres sztringeket kiszűri, a listát nem nyeli el', () async {
      final built = _build(body: _postBody());

      await built.repository.createPost(
        audience: CommunityAudience.public,
        body: 'törzs',
        artifact: const <String, Object?>{},
        idempotencyKey: 'k-3',
        mediaIds: <String>['', _mediaPublicId],
      );

      final sent = built.adapter.requests.single.data! as Map;
      expect(sent['media_ids'], <String>[_mediaPublicId]);
    });

    test('a klub-poszt is viszi a csatolmányokat', () async {
      final built = _build(body: _postBody());

      await built.repository.createClubPost(
        clubId: ContentId(_clubPublicId),
        audience: CommunityAudience.public,
        body: 'törzs',
        artifact: const <String, Object?>{},
        idempotencyKey: 'k-4',
        mediaIds: <String>[_mediaPublicId],
      );

      final sent = built.adapter.requests.single.data! as Map;
      expect(sent['media_ids'], <String>[_mediaPublicId]);
      expect(sent['club_public_id'], isNotNull);
    });
  });
}
