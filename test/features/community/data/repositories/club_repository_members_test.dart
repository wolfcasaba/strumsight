// A klub-taglista bekötésének mérése (javító sáv R5, 2026-09-06) — a
// TÉNYLEGES kimenő kérésen és a TÉNYLEGES szerver-válasz alakján.
//
// MÉRT hiány: a `clubMemberListProvider` MINDIG üres listát adott („a Kör
// 24 wire egy jövőbeli felület"), pedig a `GET /community/clubs/{id}/members`
// végpont a szerveren megvolt — a tagkezelő képernyő és a Members fül
// minden klubra a „nincs tag" állapotot rajzolta.
//
// A bekötés három ponton dönthetett rosszul, mindegyiket cella méri:
//
//   1. az útvonal és a lapméret neve (`page_size`),
//   2. a két azonosító (tagsági sor vs. profil) összekeverése,
//   3. az ismeretlen szerep `member`-re kerekítése — ez a szivárgás iránya,
//      a sor helyette kimarad.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/club_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_club.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
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
const String _ownerProfile = '77777777-7777-4777-8777-777777777777';
const String _memberProfile = '88888888-8888-4888-8888-888888888888';

Map<String, Object?> _memberJson({
  required String publicId,
  required String profilePublicId,
  required String role,
}) => <String, Object?>{
  'public_id': publicId,
  'club_public_id': _clubId,
  'profile_public_id': profilePublicId,
  'role': role,
  'joined_at': '2026-08-01T00:00:00Z',
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

  group('members', () {
    test('M1 — a lista a klub members-útvonalára megy, lapmérettel', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      final members = await repository.members(
        clubId: ContentId(_clubId),
        pageSize: 200,
      );

      expect(adapter.last.path, '/community/clubs/$_clubId/members');
      expect(adapter.last.method, 'GET');
      expect(adapter.last.queryParameters['page_size'], 200);
      expect(members, isEmpty);
    });

    test('M2 — a tagsági sor és a profil azonosítója külön marad', () async {
      adapter.body = <String, Object?>{
        'items': <Object?>[
          _memberJson(
            publicId: 'row-owner',
            profilePublicId: _ownerProfile,
            role: 'owner',
          ),
          _memberJson(
            publicId: 'row-member',
            profilePublicId: _memberProfile,
            role: 'member',
          ),
        ],
        'next_cursor': null,
      };

      final members = await repository.members(
        clubId: ContentId(_clubId),
        pageSize: 50,
      );

      expect(members, hasLength(2));
      expect(members.first.memberPublicId, 'row-owner');
      expect(members.first.profilePublicId, PublicUserId(_ownerProfile));
      expect(members.first.role, ClubRole.owner);
      expect(members.first.clubId, ContentId(_clubId));
      expect(members.first.joinedAt, DateTime.utc(2026, 8, 1));
      expect(members.last.role, ClubRole.member);
    });

    test('M3 — az ismeretlen szerep kimarad, nem member-re kerekül', () async {
      adapter.body = <String, Object?>{
        'items': <Object?>[
          _memberJson(
            publicId: 'row-future',
            profilePublicId: _memberProfile,
            role: 'auditor',
          ),
          _memberJson(
            publicId: 'row-mod',
            profilePublicId: _ownerProfile,
            role: 'moderator',
          ),
        ],
        'next_cursor': null,
      };

      final members = await repository.members(
        clubId: ContentId(_clubId),
        pageSize: 50,
      );

      expect(members.map((m) => m.memberPublicId), <String>['row-mod']);
      expect(members.single.role, ClubRole.moderator);
    });
  });
}
