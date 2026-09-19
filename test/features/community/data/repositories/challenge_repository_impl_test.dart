// A kihívás-repository OLVASÓ ágának mérése — a TÉNYLEGES kimenő kérésen és
// a TÉNYLEGES szerver-válasz alakján, nem fake repository-n.
//
// MÉRT hiány (2026-09-06, WP-H4): a `HttpCommunityChallengeRepository` három
// olyan GET-et hívott, aminek NEM VOLT szerver-oldali útvonala
// (`/community/challenges`, `.../{id}`, `.../{id}/me`) — a
// `docs/contracts/client-backend-endpoints.json` ezt három `known_gap`
// sorként vezette. A végpontok megépültek; ez a fájl azt méri, hogy a
// kliens tényleg AZOKAT hívja, és a válaszukat helyesen olvassa.
//
// A bekötés öt ponton dönthetett rosszul, és mindegyiket cella méri:
//
//   1. az ÚTVONAL elcsúszása (`/me` vs `/participation`) — a szerver a
//      `/me`-t viszi, mert az SDD §21 végpont-táblája és a MÁR élő
//      kliens-hívás is az,
//   2. a kurzor kiküldése az ELSŐ oldalon (a `CursorPage.initial()` nem
//      küldhet `cursor=` paramétert — a szerver azt sérült kurzornak
//      olvasná),
//   3. a lista végének összemosása a folytatással (`halted` vs
//      `continued`),
//   4. az ISMERETLEN enum-érték NYITOTTABB értelmezése — ez a szivárgás
//      iránya; a dekóder inkább HIBÁZIK, mint hogy találgasson,
//   5. a `null` részvétel összemosása a hibával: a `{"participant": null}`
//      ÁLLÍTÁS („nem veszel részt"), nem hiba.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/challenge_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_challenge.dart';
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

const String _challengeId = '11111111-1111-4111-8111-111111111111';
const String _authorId = '22222222-2222-4222-8222-222222222222';
const String _clubId = '33333333-3333-4333-8333-333333333333';
const String _participantId = '44444444-4444-4444-8444-444444444444';

Map<String, Object?> _challengeJson({
  String publicId = _challengeId,
  String type = 'periodicGlobal',
  String metric = 'score',
  String? clubId,
}) => <String, Object?>{
  'public_id': publicId,
  'author_public_id': _authorId,
  'type': type,
  'metric': metric,
  'difficulty': 3,
  'starts_at': '2026-09-01T10:00:00Z',
  'ends_at': '2026-09-30T10:00:00Z',
  'version': 1,
  'club_id': clubId,
};

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityChallengeRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityChallengeRepository(ApiClient(dio));
  });

  group('listChallenges', () {
    test('D1 — a lista a /community/challenges-ra megy, lapmérettel', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      await repository.listChallenges(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      expect(adapter.last.path, '/community/challenges');
      expect(adapter.last.method, 'GET');
      expect(adapter.last.queryParameters['limit'], 20);
    });

    test('D2 — az ELSŐ oldalon NEM megy ki kurzor', () async {
      // A szerver a `cursor` paramétert kurzorként olvassa; egy üres vagy
      // szintetikus kezdőérték ott „sérült kurzor" lenne. A `initial()`
      // állapot ezért a paraméter HIÁNYA, nem egy üres sztring.
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      await repository.listChallenges(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      expect(adapter.last.queryParameters.containsKey('cursor'), isFalse);
    });

    test('D2 — a FOLYTATÓ oldal viszont kiküldi a szerver kurzorát', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      await repository.listChallenges(
        cursor: const CursorPage.continued('kurzor-42'),
        limit: 20,
      );

      expect(adapter.last.queryParameters['cursor'], 'kurzor-42');
    });

    test('D3 — üres lista + nincs kurzor = MEGÁLLT (halted), nem kezdő '
        'állapot', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      final page = await repository.listChallenges(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      expect(page.items, isEmpty);
      expect(page.isHaltedAfterRequest, isTrue);
    });

    test('D3 — a szerver kurzora FOLYTATÓ oldalt ad', () async {
      adapter.body = <String, Object?>{
        'items': <Object?>[_challengeJson()],
        'next_cursor': 'kovetkezo-oldal',
      };

      final page = await repository.listChallenges(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      expect(page.cursor.cursor, 'kovetkezo-oldal');
      expect(page.cursor.isInitial, isFalse);
      expect(page.items.single.id, ContentId(_challengeId));
    });

    test('a wire-mezők a domain-entitásra kerülnek, a klub-hatókört is '
        'beleértve', () async {
      adapter.body = <String, Object?>{
        'items': <Object?>[
          _challengeJson(type: 'club', metric: 'streak', clubId: _clubId),
        ],
        'next_cursor': null,
      };

      final page = await repository.listChallenges(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      final challenge = page.items.single;
      expect(challenge.type, ChallengeType.club);
      expect(challenge.metric, 'streak');
      expect(challenge.difficulty, 3);
      expect(challenge.clubId, _clubId);
      expect(challenge.startsAt.isUtc, isTrue);
    });

    test('D4 — ISMERETLEN típus HIBA, nem egy találgatott érték', () async {
      // A szivárgás iránya: egy ismeretlen wire-értéket a legszűkebb
      // ismertre „kerekíteni" azt állítaná, hogy tudjuk, mi az. A dekóder
      // inkább kimondja, hogy nem érti.
      adapter.body = <String, Object?>{
        'items': <Object?>[_challengeJson(type: 'holnapUtaniKihivas')],
        'next_cursor': null,
      };

      expect(
        () => repository.listChallenges(
          cursor: const CursorPage.initial(),
          limit: 20,
        ),
        throwsA(isA<Object>()),
      );
    });

    test('az ISMERETLEN EXTRA mező nem borítja fel a dekódolást', () async {
      // Előre-kompatibilitás: a szerver bővítheti a wire-alakot anélkül,
      // hogy a régi kliens elszállna.
      adapter.body = <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            ..._challengeJson(),
            'jovobeli_mezo': 'valami',
            'prize_pool': 42,
          },
        ],
        'next_cursor': null,
      };

      final page = await repository.listChallenges(
        cursor: const CursorPage.initial(),
        limit: 20,
      );

      expect(page.items.single.id, ContentId(_challengeId));
    });
  });

  group('fetchDefinition', () {
    test('D1 — a részlet a /community/challenges/{id}-ra megy', () async {
      adapter.body = _challengeJson();

      final challenge = await repository.fetchDefinition(
        challengeId: ContentId(_challengeId),
      );

      expect(adapter.last.path, '/community/challenges/$_challengeId');
      expect(adapter.last.method, 'GET');
      expect(challenge.id, ContentId(_challengeId));
      expect(challenge.version, 1);
    });
  });

  group('fetchMyParticipation', () {
    test(
      'D1 — a saját részvétel a /me végpontra megy (NEM /participation)',
      () async {
        adapter.body = const <String, Object?>{'participant': null};

        await repository.fetchMyParticipation(
          challengeId: ContentId(_challengeId),
        );

        expect(adapter.last.path, '/community/challenges/$_challengeId/me');
      },
    );

    test('D5 — a `participant: null` ÁLLÍTÁS: nincs részvétel', () async {
      adapter.body = const <String, Object?>{'participant': null};

      final participation = await repository.fetchMyParticipation(
        challengeId: ContentId(_challengeId),
      );

      expect(participation, isNull);
    });

    test('a részvétel-sor állapota és a személyes csúcs átjön', () async {
      adapter.body = const <String, Object?>{
        'participant': <String, Object?>{
          'participant_public_id': _participantId,
          'invite_state': 'accepted',
          'best_metric_value': 4200,
        },
      };

      final participation = await repository.fetchMyParticipation(
        challengeId: ContentId(_challengeId),
      );

      expect(participation, isNotNull);
      expect(participation!.inviteState, ChallengeInviteState.accepted);
      expect(participation.bestMetricValue, 4200);
      expect(participation.challengeId, ContentId(_challengeId));
    });

    test('a HIÁNYZÓ csúcs `null` marad — SOHA nem 0', () async {
      // A 0 eredményt ÁLLÍTANA („nulla pontot ért el"), holott az igazság
      // az, hogy még nincs hitelesített eredmény. A képernyő ebből
      // rajzolja az „ellenőrzés folyamatban" állapotot.
      adapter.body = const <String, Object?>{
        'participant': <String, Object?>{
          'participant_public_id': _participantId,
          'invite_state': 'sent',
          'best_metric_value': null,
        },
      };

      final participation = await repository.fetchMyParticipation(
        challengeId: ContentId(_challengeId),
      );

      expect(participation!.bestMetricValue, isNull);
      expect(participation.inviteState, ChallengeInviteState.sent);
    });
  });

  group('clubChallenges', () {
    test(
      'D1 — a klub kihívásai a klub-végpontra mennek, lapmérettel',
      () async {
        adapter.body = const <String, Object?>{
          'items': <Object?>[],
          'next_cursor': null,
        };

        await repository.clubChallenges(clubId: ContentId(_clubId), limit: 25);

        expect(adapter.last.path, '/community/clubs/$_clubId/challenges');
        expect(adapter.last.method, 'GET');
        expect(adapter.last.queryParameters['page_size'], 25);
      },
    );

    test('a `status` paramétert NEM küldjük ki: a szerver alapértelmezése '
        'az aktív ablak', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      await repository.clubChallenges(clubId: ContentId(_clubId), limit: 25);

      expect(adapter.last.queryParameters.containsKey('status'), isFalse);
    });

    test(
      'a klub sorai ugyanazon a dekóderen jönnek, mint a fő listáé',
      () async {
        adapter.body = <String, Object?>{
          'items': <Object?>[_challengeJson(type: 'club', clubId: _clubId)],
          'next_cursor': null,
        };

        final page = await repository.clubChallenges(
          clubId: ContentId(_clubId),
          limit: 25,
        );

        expect(page.items.single.clubId, _clubId);
        expect(page.items.single.type, ChallengeType.club);
      },
    );

    test('a 404 (nem látható klub) HIBA, nem üres oldal', () async {
      // A klub-kapu a szerveré: privát klub nem-tagnak 404. Ha a
      // repository ezt üres oldalra fordítaná, a fül azt ÁLLÍTANÁ, hogy
      // a klubnak nincs kihívása — pedig azt sem tudjuk, létezik-e.
      adapter.status = 404;
      adapter.body = const <String, Object?>{'detail': 'club not found'};

      expect(
        () => repository.clubChallenges(clubId: ContentId(_clubId), limit: 25),
        throwsA(isA<Object>()),
      );
    });
  });

  group('DisabledCommunityChallengeRepository', () {
    test('a klub-olvasás is konfigurációs hibát ad — ez a fül „nem tudjuk" '
        'ágának EGYETLEN forrása', () async {
      const disabled = DisabledCommunityChallengeRepository();

      expect(
        () => disabled.clubChallenges(clubId: ContentId(_clubId), limit: 25),
        throwsA(isA<Object>()),
      );
    });
  });
}
