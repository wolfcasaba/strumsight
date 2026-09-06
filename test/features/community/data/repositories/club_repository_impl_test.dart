// A klub-repository bekötésének mérése — a TÉNYLEGES kimenő kérésen és a
// TÉNYLEGES szerver-válasz alakján, nem fake repository-n.
//
// MÉRT hiány (2026-09-06): a `CommunityClubRepository` szerződés a Kör 5 óta
// állt implementáció nélkül, a provider-definíciója pedig egy
// `UnimplementedError`-t dobó seam volt a `club_list_screen.dart`-ban. A
// szállított kompozícióban senki nem írta felül, tehát mind a három
// klub-képernyő az első olvasásnál elszállt volna.
//
// A bekötés öt ponton dönthetett rosszul, és mindegyiket cella méri:
//
//   1. a `tags` néma eldobása (a szervernek NINCS tags oszlopa),
//   2. a `cursor` kiküldése egy olyan felületre, ami nem olvassa,
//   3. a lista végének összemosása az első kéréssel (`halted` vs
//      `initial`),
//   4. az ismeretlen `visibility` / `my_role` NYITOTTABB értelmezése — ez
//      a szivárgás iránya,
//   5. a szerkesztés (`PATCH`): az `UpdateClubRequest` (`extra="forbid"`)
//      HÁROM mezőt deklarál — sem `tags`, sem `resource_version` nincs
//      köztük —, és a 409 a `community.conflict` kódot kapja.
library;

import 'dart:convert';
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

const String _clubId = '66666666-6666-4666-8666-666666666666';
const String _ownerId = '77777777-7777-4777-8777-777777777777';
const String _targetId = '88888888-8888-4888-8888-888888888888';

Map<String, Object?> _clubJson({
  String publicId = _clubId,
  String visibility = 'public',
  String? myRole = 'owner',
  int memberCount = 3,
}) => <String, Object?>{
  'public_id': publicId,
  'name': 'Klub',
  'description': 'leírás',
  'visibility': visibility,
  'owner_public_id': _ownerId,
  'member_count': memberCount,
  'my_role': myRole,
  'created_at': '2026-09-06T10:00:00Z',
  'resource_version': '2026-09-06T10:00:00Z',
};

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityClubRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityClubRepository(ApiClient(dio));
  });

  Map<String, Object?> sentBody() => adapter.last.data! as Map<String, Object?>;

  group('listClubs', () {
    test('D1 — a lista a /community/clubs-ra megy, lapmérettel', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      await repository.listClubs(cursor: const CursorPage.initial(), limit: 25);

      expect(adapter.last.path, '/community/clubs');
      expect(adapter.last.method, 'GET');
      expect(adapter.last.queryParameters['page_size'], 25);
    });

    test('D2 — a kurzor NEM megy ki: a felület nem olvassa', () async {
      // A `GET /community/clubs` csak `page_size`-t fogad; a `list_clubs`
      // service `limit`-alapú. Egy elfogadottnak látszó, de figyelmen kívül
      // hagyott paraméter ugyanaz a néma hibaosztály, amit a feed lapozása
      // már megmért.
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      await repository.listClubs(
        cursor: const CursorPage.continued('opaque'),
        limit: 25,
      );

      expect(adapter.last.queryParameters.containsKey('cursor'), isFalse);
    });

    test('D3 — a lista vége HALTED, nem INITIAL', () async {
      adapter.body = <String, Object?>{
        'items': <Object?>[_clubJson()],
        'next_cursor': null,
      };

      final page = await repository.listClubs(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(page.cursor, const CursorPage.haltedAfterRequest());
      expect(page.cursor.isInitial, isFalse);
      expect(page.items.single.id, ContentId(_clubId));
    });

    test('D4 — a jövőbeli kurzoros felület alakja már átjön', () async {
      // A `ClubPage.next_cursor` mező ma mindig `null`, de a séma
      // docstringje szerint a service kurzorosra vált; a kliens lapozó-kódja
      // már most helyesen olvassa.
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': 'next-token',
      };

      final page = await repository.listClubs(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(page.cursor, const CursorPage.continued('next-token'));
    });
  });

  group('a wire-alak értelmezése', () {
    test(
      'D5 — az ismeretlen láthatóság a LEGSZŰKEBB értelmezést kapja',
      () async {
        // Egy jövőbeli érték `public`-ra kerekítése azt jelentené, hogy a régi
        // kliens nyilvánosnak MUTAT egy nem nyilvános klubot.
        adapter.body = _clubJson(visibility: 'future_value');

        final club = await repository.fetchClub(clubId: ContentId(_clubId));

        expect(club.visibility, ClubVisibility.private);
      },
    );

    test('D6 — az ismeretlen szerep NEM-TAG-ot jelent', () async {
      // A `myRole == null` az a bemenet, amire a képernyők a tartalmat
      // ELREJTIK. Egy ismeretlen értéket `member`-re kerekítve egy jövőbeli,
      // szűkebb jogú szerep teljes klub-tartalmat látna.
      adapter.body = _clubJson(myRole: 'future_role');

      final club = await repository.fetchClub(clubId: ContentId(_clubId));

      expect(club.myRole, isNull);
    });

    test('D7 — a nem-tag null szerepe átjön, a tagé nem vész el', () async {
      adapter.body = _clubJson(myRole: null);
      expect(
        (await repository.fetchClub(clubId: ContentId(_clubId))).myRole,
        isNull,
      );

      adapter.body = _clubJson(myRole: 'moderator');
      expect(
        (await repository.fetchClub(clubId: ContentId(_clubId))).myRole,
        ClubRole.moderator,
      );
    });

    test('D8 — a tags MINDIG üres: a szervernek nincs ilyen mezője', () async {
      adapter.body = _clubJson();

      final club = await repository.fetchClub(clubId: ContentId(_clubId));

      expect(club.tags, isEmpty);
    });

    test('D9 — a tagszám az entitás korlátai közé vágódik', () async {
      // A klub-sor eldobása (kivétel dekódolás közben) az EGÉSZ listát
      // megölné egyetlen elavult konstans miatt.
      adapter.body = _clubJson(memberCount: 0);
      expect(
        (await repository.fetchClub(clubId: ContentId(_clubId))).memberCount,
        1,
      );

      adapter.body = _clubJson(memberCount: kCommunityClubMaxMembers + 5);
      expect(
        (await repository.fetchClub(clubId: ContentId(_clubId))).memberCount,
        kCommunityClubMaxMembers,
      );
    });

    test('D10 — a hiányzó kötelező mező hiba, nem néma üres klub', () async {
      adapter.body = const <String, Object?>{'name': 'azonosító nélkül'};

      await expectLater(
        repository.fetchClub(clubId: ContentId(_clubId)),
        throwsA(isA<Object>()),
      );
    });
  });

  group('createClub / updateClub', () {
    test('D11 — a létrehozás a szerver által ISMERT mezőket küldi', () async {
      adapter.status = 201;
      adapter.body = _clubJson(visibility: 'discoverable');

      final club = await repository.createClub(
        name: 'Klub',
        description: 'leírás',
        visibility: ClubVisibility.discoverable,
        tags: const <String>[],
        idempotencyKey: 'key-1',
      );

      expect(adapter.last.method, 'POST');
      expect(adapter.last.path, '/community/clubs');
      expect(sentBody()['name'], 'Klub');
      expect(sentBody()['description'], 'leírás');
      expect(sentBody()['visibility'], 'discoverable');
      expect(sentBody()['idempotency_key'], 'key-1');
      // A `tags` kulcs kimarad: a séma `extra="forbid"`, elküldve 422 lenne.
      expect(sentBody().containsKey('tags'), isFalse);
      expect(club.visibility, ClubVisibility.discoverable);
    });

    test('D12 — a nem üres címke-lista HIBA, nem néma eldobás', () async {
      // A címkék csendes elhagyása a felhasználó bevitelének néma
      // elvesztése lenne.
      await expectLater(
        repository.createClub(
          name: 'Klub',
          description: '',
          visibility: ClubVisibility.private,
          tags: const <String>['rock'],
          idempotencyKey: 'key-2',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('D13 — a klub szerkesztése PATCH-et küld a klub útvonalára', () async {
      adapter.body = _clubJson(visibility: 'public');

      final club = await repository.updateClub(
        clubId: ContentId(_clubId),
        description: 'új',
        visibility: ClubVisibility.public,
        tags: const <String>[],
        resourceVersion: '2026-09-06T10:00:00Z',
        idempotencyKey: 'key-3',
      );

      expect(adapter.last.method, 'PATCH');
      expect(adapter.last.path, '/community/clubs/$_clubId');
      // Az `UpdateClubRequest` (`extra="forbid"`) HÁROM mezőt deklarál. A
      // `resource_version` NINCS köztük — a szerver a klub-szerkesztést vak
      // írásként végzi, tehát a token kiküldése 422 lenne. A `tags`-nek
      // szintén nincs oszlopa.
      expect(sentBody(), <String, Object?>{
        'description': 'új',
        'visibility': 'public',
        'idempotency_key': 'key-3',
      });
      expect(club.id.value, _clubId);
    });

    test('D13b — a nem üres címke-lista a PATCH-en is HIBA', () async {
      await expectLater(
        repository.updateClub(
          clubId: ContentId(_clubId),
          description: 'új',
          visibility: ClubVisibility.public,
          tags: const <String>['rock'],
          resourceVersion: '2026-09-06T10:00:00Z',
          idempotencyKey: 'key-3b',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test(
      'D13c — a klub-PATCH 409-e community.conflict, nem néma siker',
      () async {
        // A `clubs.py` `_raise_for_service_error` 409-et ad az érvénytelen
        // állapot-átmenetre és az idempotencia-ütközésre is.
        adapter.status = 409;
        adapter.body = const <String, Object?>{'detail': 'invalid transition'};

        await expectLater(
          repository.updateClub(
            clubId: ContentId(_clubId),
            description: 'új',
            visibility: ClubVisibility.private,
            tags: const <String>[],
            resourceVersion: '2026-09-06T10:00:00Z',
            idempotencyKey: 'key-3c',
          ),
          throwsA(
            isA<ValidationFailure>().having(
              (failure) => failure.code,
              'code',
              FailureCode.communityConflict,
            ),
          ),
        );
        expect(adapter.last.method, 'PATCH');
      },
    );
  });

  group('tagsági műveletek', () {
    test('D14 — a csatlakozás és a kilépés külön útvonal', () async {
      adapter.body = const <String, Object?>{'outcome': 'joined'};
      await repository.requestJoin(
        clubId: ContentId(_clubId),
        idempotencyKey: 'key-4',
      );
      expect(adapter.last.method, 'POST');
      expect(adapter.last.path, '/community/clubs/$_clubId/join');
      expect(sentBody()['idempotency_key'], 'key-4');

      adapter.body = const <String, Object?>{'left': true};
      await repository.leave(
        clubId: ContentId(_clubId),
        idempotencyKey: 'key-5',
      );
      expect(adapter.last.path, '/community/clubs/$_clubId/leave');
      expect(sentBody()['idempotency_key'], 'key-5');
    });

    test('D15 — a meghívás a célszemélyt a törzsben viszi', () async {
      adapter.status = 201;
      adapter.body = const <String, Object?>{'invite_public_id': _targetId};

      await repository.invite(
        clubId: ContentId(_clubId),
        target: PublicUserId(_targetId),
        idempotencyKey: 'key-6',
      );

      expect(adapter.last.method, 'POST');
      expect(adapter.last.path, '/community/clubs/$_clubId/invites');
      expect(sentBody()['target_public_id'], _targetId);
      expect(sentBody()['idempotency_key'], 'key-6');
    });

    test('D16 — a tag eltávolítása DELETE, az ÚTVONALON azonosítva', () async {
      adapter.body = const <String, Object?>{'removed': true};

      await repository.removeMember(
        clubId: ContentId(_clubId),
        memberId: PublicUserId(_targetId),
        idempotencyKey: 'key-7',
      );

      expect(adapter.last.method, 'DELETE');
      expect(adapter.last.path, '/community/clubs/$_clubId/members/$_targetId');
      // A végpont nem olvas idempotencia-kulcsot; nem toldjuk oda némán.
      expect(adapter.last.path.contains('idempotency_key'), isFalse);
    });

    test('D17 — a tulajdonos-átadás a friss klubot adja vissza', () async {
      adapter.body = _clubJson(myRole: 'member');

      await repository.transferOwnership(
        clubId: ContentId(_clubId),
        newOwnerId: PublicUserId(_targetId),
        idempotencyKey: 'key-8',
      );

      expect(adapter.last.method, 'POST');
      expect(adapter.last.path, '/community/clubs/$_clubId/owner');
      expect(sentBody()['target_public_id'], _targetId);
      expect(sentBody()['idempotency_key'], 'key-8');
    });
  });
}
