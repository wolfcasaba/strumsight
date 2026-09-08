/// Javító sáv R27 — a csatolt média wire-alakja.
///
/// A `MediaOut` (`backend/app/community/schemas/media.py`) → entitás
/// dekódolás, és a poszt `media` tömbjének beolvasása. A cellák azt
/// mérik, hogy a dekóder a HIÁNYZÓ és az ISMERETLEN mezőt
/// megkülönbözteti, és hogy az ismeretlen érték a SZŰKEBB irányba dől.
///
/// * A1 — a teljes leíró minden mezője megérkezik.
/// * A2 — a szerver `pending`-je a kliens „feldolgozás alatt"
///   állapota; a leképezés a huzal-literálon áll, nem sorrenden.
/// * A3 — ISMERETLEN állapot ⇒ `rejected`. Egy jövőbeli állapotot
///   `ready`-nek olvasni azt jelentené, hogy a régi kliens olyan
///   bájtokat próbál megjeleníteni, amelyeket a szerver visszatartott.
/// * A4 — ISMERETLEN fajta ⇒ `unknown`, NEM `image`.
/// * A5 — hiányzó KÖTELEZŐ mező (`public_id`, `created_at`) hiba; a
///   hiányzó opcionális mező alapértékre esik.
/// * A6 — a poszt `media` kulcsának hiánya ÜRES lista, nem hiba: egy
///   média előtti gyorsítótár-bejegyzést eldobni több kárt okozna,
///   mint amennyi hasznot a szigor hoz.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/community/data/repositories/post_wire.dart';
import 'package:strumsight/features/community/domain/entities/community_media.dart';

Map<String, Object?> _mediaJson({
  String state = 'ready',
  String kind = 'image',
  Object? rejectionCode,
}) {
  return <String, Object?>{
    'public_id': '55555555-5555-4555-8555-555555555555',
    'kind': kind,
    'state': state,
    'rejection_code': rejectionCode,
    'content_type': 'image/jpeg',
    'size_bytes': 4321,
    'width': 800,
    'height': 600,
    'duration_ms': null,
    'created_at': '2026-09-08T10:00:00Z',
  };
}

Map<String, Object?> _postJson({Object? media}) {
  return <String, Object?>{
    'public_id': '11111111-1111-4111-8111-111111111111',
    'author_public_id': '22222222-2222-4222-8222-222222222222',
    'audience': 'public',
    'body': 'törzs',
    'moderation_state': 'visible',
    'created_at': '2026-09-08T10:00:00Z',
    'resource_version': '2026-09-08T10:00:00Z',
    if (media != null) 'media': media,
  };
}

void main() {
  group('A1 — a teljes leíró', () {
    test('minden mező megérkezik', () {
      final media = decodeCommunityMedia(_mediaJson());

      expect(media.publicId, '55555555-5555-4555-8555-555555555555');
      expect(media.kind, CommunityMediaKind.image);
      expect(media.state, CommunityMediaState.ready);
      expect(media.rejectionCode, isNull);
      expect(media.contentType, 'image/jpeg');
      expect(media.sizeBytes, 4321);
      expect(media.width, 800);
      expect(media.height, 600);
      expect(media.durationMs, isNull);
      expect(media.createdAt, DateTime.utc(2026, 9, 8, 10));
      expect(media.isReady, isTrue);
      expect(media.isProcessing, isFalse);
      expect(
        media.downloadPath,
        '/community/media/55555555-5555-4555-8555-555555555555',
      );
    });

    test('az elutasítás kódja átjön, és a leíró nem kész', () {
      final media = decodeCommunityMedia(
        _mediaJson(state: 'rejected', rejectionCode: 'malware_detected'),
      );

      expect(media.state, CommunityMediaState.rejected);
      expect(media.rejectionCode, 'malware_detected');
      expect(media.isReady, isFalse);
      expect(media.isProcessing, isFalse);
    });
  });

  group('A2/A3 — állapot-leképezés', () {
    for (final entry in <String, CommunityMediaState>{
      'pending': CommunityMediaState.pending,
      'scanning': CommunityMediaState.scanning,
      'transcoding': CommunityMediaState.transcoding,
      'review': CommunityMediaState.review,
      'ready': CommunityMediaState.ready,
      'rejected': CommunityMediaState.rejected,
      'deleted': CommunityMediaState.deleted,
    }.entries) {
      test('"${entry.key}" ⇒ ${entry.value}', () {
        expect(communityMediaStateFromWire(entry.key), entry.value);
      });
    }

    test('a négy nem-terminális állapot „feldolgozás alatt"', () {
      for (final state in <String>[
        'pending',
        'scanning',
        'transcoding',
        'review',
      ]) {
        final media = decodeCommunityMedia(_mediaJson(state: state));
        expect(media.isProcessing, isTrue, reason: state);
        expect(media.isReady, isFalse, reason: state);
      }
    });

    test('ISMERETLEN állapot ⇒ rejected, NEM ready', () {
      // A szűkebb irány: egy jövőbeli állapotot `ready`-nek olvasni azt
      // jelentené, hogy a régi kliens visszatartott bájtokat próbál
      // megjeleníteni.
      final media = decodeCommunityMedia(_mediaJson(state: 'quarantined'));
      expect(media.state, CommunityMediaState.rejected);
      expect(media.isReady, isFalse);
    });

    test('hiányzó állapot ⇒ rejected', () {
      final json = _mediaJson()..remove('state');
      expect(decodeCommunityMedia(json).state, CommunityMediaState.rejected);
    });
  });

  group('A4 — fajta', () {
    test('image / audio átjön', () {
      expect(
        decodeCommunityMedia(_mediaJson(kind: 'image')).kind,
        CommunityMediaKind.image,
      );
      expect(
        decodeCommunityMedia(_mediaJson(kind: 'audio')).kind,
        CommunityMediaKind.audio,
      );
    });

    test('ISMERETLEN fajta ⇒ unknown, NEM image', () {
      final media = decodeCommunityMedia(_mediaJson(kind: 'video'));
      expect(media.kind, CommunityMediaKind.unknown);
      expect(media.kind, isNot(CommunityMediaKind.image));
    });
  });

  group('A5 — kötelező és opcionális mezők', () {
    test('hiányzó public_id hiba', () {
      final json = _mediaJson()..remove('public_id');
      expect(() => decodeCommunityMedia(json), throwsFormatException);
    });

    test('üres public_id hiba', () {
      final json = _mediaJson()..['public_id'] = '';
      expect(() => decodeCommunityMedia(json), throwsFormatException);
    });

    test('hiányzó created_at hiba', () {
      final json = _mediaJson()..remove('created_at');
      expect(() => decodeCommunityMedia(json), throwsFormatException);
    });

    test('hiányzó content_type semleges alapértékre esik', () {
      final json = _mediaJson()..remove('content_type');
      expect(
        decodeCommunityMedia(json).contentType,
        'application/octet-stream',
      );
    });

    test('hiányzó méret/dimenzió nem hiba', () {
      final json = _mediaJson()
        ..remove('size_bytes')
        ..remove('width')
        ..remove('height');
      final media = decodeCommunityMedia(json);
      expect(media.sizeBytes, 0);
      expect(media.width, isNull);
      expect(media.height, isNull);
    });

    test('negatív méret nullára esik', () {
      final json = _mediaJson()..['size_bytes'] = -1;
      expect(decodeCommunityMedia(json).sizeBytes, 0);
    });
  });

  group('A6 — a poszt media tömbje', () {
    test('a csatolmányok sorrendben, a poszt entitásán jelennek meg', () {
      final post = decodeCommunityPost(
        _postJson(
          media: <Map<String, Object?>>[
            _mediaJson(),
            _mediaJson()
              ..['public_id'] = '66666666-6666-4666-8666-666666666666',
          ],
        ),
      );

      expect(post.media, hasLength(2));
      expect(
        post.media.map((m) => m.publicId).toList(),
        <String>[
          '55555555-5555-4555-8555-555555555555',
          '66666666-6666-4666-8666-666666666666',
        ],
      );
    });

    test('hiányzó kulcs ÜRES lista, nem hiba', () {
      // Egy média előtti gyorsítótár-bejegyzés is olvasható marad.
      expect(decodeCommunityPost(_postJson()).media, isEmpty);
    });

    test('nem-lista érték ÜRES lista', () {
      expect(decodeCommunityPost(_postJson(media: 'x')).media, isEmpty);
    });

    test('a lista nem-objektum elemei kimaradnak', () {
      final post = decodeCommunityPost(
        _postJson(media: <Object?>[_mediaJson(), 'szemét', 42]),
      );
      expect(post.media, hasLength(1));
    });

    test('két azonos tartalmú poszt EGYENLŐ a csatolmányaival együtt', () {
      // A `List` `==`-e referencia-alapú: elem-egyenlőség nélkül minden
      // újradekódolás után minden feed-kártya újraépülne.
      final json = _postJson(media: <Map<String, Object?>>[_mediaJson()]);
      expect(decodeCommunityPost(json), decodeCommunityPost(json));
    });

    test('eltérő csatolmány KÜLÖNBÖZŐ posztot ad', () {
      final withMedia = decodeCommunityPost(
        _postJson(media: <Map<String, Object?>>[_mediaJson()]),
      );
      final without = decodeCommunityPost(_postJson());
      expect(withMedia, isNot(without));
    });
  });
}
