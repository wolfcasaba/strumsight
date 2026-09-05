// Az értesítés-repository bekötésének mérése a TÉNYLEGES kimenő kérésen és
// a TÉNYLEGES wire-alakon.
//
// A szerződés a Kör 5 óta állt implementáció nélkül, a szerver-oldali router
// pedig sosem született meg a Kör 20-as service fölé. A bekötés két ponton
// dönthetett rosszul, és mindkettőt cella méri: az olvasatlan-szám
// kitalálása, és az ismeretlen értesítés-fajta „általános tételként" való
// megjelenítése.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/notification_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/notification_item.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Map<String, Object?> body = const {
    'items': <Object?>[],
    'next_cursor': null,
    'unread_count': 0,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _notificationJson({
  String type = 'comment',
  String publicId = '11111111-1111-4111-8111-111111111111',
  String titleKey = 'community_notification_comment_title',
  String? entityId,
  bool isRead = false,
}) => <String, Object?>{
  'public_id': publicId,
  'actor_public_id': '22222222-2222-4222-8222-222222222222',
  'type': type,
  'title_key': titleKey,
  'body_key': null,
  'entity_type': 'post',
  'entity_id': entityId,
  'aggregate_count': 1,
  'is_read': isRead,
  'read_at': null,
  'created_at': '2026-09-05T10:00:00Z',
};

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityNotificationRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityNotificationRepository(ApiClient(dio));
  });

  group('inbox', () {
    test('C1 — az oldal a saját inbox útvonalára megy, lapozással', () async {
      await repository.inboxPage(
        cursor: const CursorPage.continued('token'),
        limit: 30,
      );

      expect(adapter.lastRequest!.path, '/community/notifications');
      expect(adapter.lastRequest!.queryParameters['cursor'], 'token');
      expect(adapter.lastRequest!.queryParameters['page_size'], 30);
      // A címzett a JWT-ből jön: nincs olyan paraméter, amivel MÁS
      // inboxát lehetne kérni.
      expect(
        adapter.lastRequest!.queryParameters.keys,
        unorderedEquals(<String>['cursor', 'page_size']),
      );
    });

    test('C2 — az olvasatlan-szám a VÁLASZBÓL jön, nem az oldalból', () async {
      // A jelvény a TELJES inboxra vonatkozik. Az oldal olvasatlan
      // tételeit megszámolva a jelvény a lapmérettel csökkenne — a
      // felhasználó azt látná, hogy „elfogytak" az értesítései.
      adapter.body = {
        'items': [_notificationJson(), _notificationJson(isRead: true)],
        'next_cursor': null,
        'unread_count': 47,
      };

      final result = await repository.inboxPageWithUnreadCount(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(result.unreadCount, 47);
      expect(result.page.items.length, 2);
    });

    test('C3 — a hiányzó olvasatlan-szám HIBA, nem néma nulla', () async {
      // Egy nulla jelvény azt ÁLLÍTANÁ, hogy minden el van olvasva.
      adapter.body = {'items': <Object?>[], 'next_cursor': null};

      await expectLater(
        repository.inboxPage(cursor: const CursorPage.initial(), limit: 25),
        throwsA(isA<Object>()),
      );
    });

    test('C4 — az ismeretlen fajta HIBA, nem általános tétel', () async {
      // A UI fajtánként rajzol ikont és koppintás-műveletet; egy
      // „általános" tétel azt állítaná, hogy értjük, mi történt. A
      // kontroll a C2, ahol az ismert fajta simán átmegy.
      adapter.body = {
        'items': [_notificationJson(type: 'valami_jovobeli_esemeny')],
        'next_cursor': null,
        'unread_count': 1,
      };

      await expectLater(
        repository.inboxPage(cursor: const CursorPage.initial(), limit: 25),
        throwsA(isA<Object>()),
      );
    });

    test('C5 — a mélylink azonosítója átjön, hiányában null', () async {
      adapter.body = {
        'items': [
          _notificationJson(entityId: 'post-abc'),
          _notificationJson(
            publicId: '33333333-3333-4333-8333-333333333333',
            type: 'security_alert',
            titleKey: 'community_notification_security_title',
          ),
        ],
        'next_cursor': null,
        'unread_count': 2,
      };

      final page = await repository.inboxPage(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(page.items.first.relatedContentId, ContentId('post-abc'));
      expect(page.items.first.kind, CommunityNotificationKind.comment);
      // A tisztán tájékoztató értesítésnek nincs hova mutatnia.
      expect(page.items.last.relatedContentId, isNull);
    });
  });

  group('mutációk', () {
    test('C6 — az olvasottra jelölés az adott értesítésre megy', () async {
      adapter.body = {'changed': true};

      await repository.markRead(
        notificationId: ContentId('n-1'),
        idempotencyKey: 'key-1',
      );

      expect(adapter.lastRequest!.path, '/community/notifications/n-1/read');
      expect(adapter.lastRequest!.method, 'POST');
      expect(
        (adapter.lastRequest!.data as Map)['idempotency_key'],
        'key-1',
      );
    });

    test('C7 — a tömeges jelölés KÜLÖN útvonal', () async {
      // Ha a kettő egy útvonalra menne, egy „mindet olvasottra" koppintás
      // véletlenül egyetlen tételt jelölne — vagy fordítva.
      adapter.body = {'marked': 12};

      await repository.markAllReadUpTo(
        upToId: ContentId('n-9'),
        idempotencyKey: 'key-2',
      );

      expect(
        adapter.lastRequest!.path,
        '/community/notifications/n-9/read-up-to',
      );
    });

    test('C8 — a beállítások térképe jön vissza', () async {
      adapter.body = {
        'preferences': {'comment': 'inApp', 'mention': 'push'},
      };

      final prefs = await repository.preferences();

      expect(adapter.lastRequest!.path, '/community/notifications/preferences');
      expect(prefs, {'comment': 'inApp', 'mention': 'push'});
    });

    test('C9 — a beállítás írása PUT, kategóriával és szinttel', () async {
      adapter.body = {
        'preferences': {'comment': 'disabled'},
      };

      await repository.updatePreference(
        category: 'comment',
        level: 'disabled',
        idempotencyKey: 'key-3',
      );

      expect(adapter.lastRequest!.method, 'PUT');
      final sent = adapter.lastRequest!.data as Map;
      expect(sent['category'], 'comment');
      expect(sent['level'], 'disabled');
    });
  });
}
