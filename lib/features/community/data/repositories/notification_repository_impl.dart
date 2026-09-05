/// Dio-backed implementation of [CommunityNotificationRepository]
/// (2026-09-05).
///
/// A szerződés a Kör 5 óta állt implementáció nélkül, a szerver-oldali
/// router pedig sosem született meg a Kör 20-as service fölé — a
/// `CommunityNotificationsScreen` így elérhetetlen maradt. Mindkettő
/// ebben a sávban zárult.
///
/// **A `titleKey` a szerveré, a SZÖVEG a kliensé.** A wire csak
/// lokalizációs kulcsot hoz: a szerver nem tudja, milyen nyelven fut az
/// app. Egy kész, szerver-oldalon fordított szöveg a felhasználó nyelvi
/// beállítását hagyná figyelmen kívül.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../features/auth/public.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/value_objects/content_id.dart';
import 'post_wire.dart';

final communityNotificationApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

final communityNotificationRepositoryProvider =
    Provider<CommunityNotificationRepository>((ref) {
      final client = ref.watch(communityNotificationApiClientProvider);
      if (client == null) return const DisabledCommunityNotificationRepository();
      return HttpCommunityNotificationRepository(client);
    });

/// Egy inbox-oldal + a TELJES inbox olvasatlan-száma.
///
/// A `CommunityPage` maga nem tud extra mezőt vinni, az olvasatlan-szám
/// viszont nem az oldalé, hanem az egész inboxé — a jelvényt ebből
/// rajzolja a UI, anélkül hogy végiglapozná a listát. Ezért külön típus.
final class CommunityInboxPage {
  const CommunityInboxPage({required this.page, required this.unreadCount});

  final CommunityPage<CommunityNotificationItem> page;

  /// Az olvasatlanok száma a TELJES inboxban, nem csak ezen az oldalon.
  final int unreadCount;
}

final class DisabledCommunityNotificationRepository
    implements CommunityNotificationRepository {
  const DisabledCommunityNotificationRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityPage<CommunityNotificationItem>> inboxPage({
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;

  @override
  Future<void> markRead({
    required ContentId notificationId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> markAllReadUpTo({
    required ContentId upToId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<Object> preferences() async => throw _disabled.error;

  @override
  Future<void> updatePreference({
    required String category,
    required String level,
    required String idempotencyKey,
  }) async => throw _disabled.error;
}

final class HttpCommunityNotificationRepository
    implements CommunityNotificationRepository {
  const HttpCommunityNotificationRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommunityPage<CommunityNotificationItem>> inboxPage({
    required Object cursor,
    required int limit,
  }) async => (await inboxPageWithUnreadCount(
    cursor: cursor,
    limit: limit,
  )).page;

  /// Ugyanaz a hívás, de az olvasatlan-számot is visszaadja.
  ///
  /// A szerződés-metódus csak az oldalt adja (a Kör 5 még nem ismerte a
  /// jelvényt); ez a bővebb változat EGY kéréssel hozza mindkettőt, hogy
  /// a jelvényhez ne kelljen második kör.
  Future<CommunityInboxPage> inboxPageWithUnreadCount({
    required Object cursor,
    required int limit,
  }) async {
    final result = await _client.getJson<CommunityInboxPage>(
      '/community/notifications',
      queryParameters: <String, Object?>{
        'page_size': limit,
        'cursor': communityCursorQueryValue(cursor),
      },
      decode: _decodeInboxPage,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<void> markRead({
    required ContentId notificationId,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<void>(
      '/community/notifications/${notificationId.value}/read',
      data: <String, Object?>{'idempotency_key': idempotencyKey},
      decode: (_) {},
    );
    if (result case Failure(:final error)) throw error;
  }

  @override
  Future<void> markAllReadUpTo({
    required ContentId upToId,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<void>(
      '/community/notifications/${upToId.value}/read-up-to',
      data: <String, Object?>{'idempotency_key': idempotencyKey},
      decode: (_) {},
    );
    if (result case Failure(:final error)) throw error;
  }

  @override
  Future<Map<String, String>> preferences() async {
    final result = await _client.getJson<Map<String, String>>(
      '/community/notifications/preferences',
      decode: _decodePreferences,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<void> updatePreference({
    required String category,
    required String level,
    required String idempotencyKey,
  }) async {
    final result = await _client.putJson<void>(
      '/community/notifications/preferences',
      data: <String, Object?>{
        'category': category,
        'level': level,
        'idempotency_key': idempotencyKey,
      },
      decode: (_) {},
    );
    if (result case Failure(:final error)) throw error;
  }
}

CommunityInboxPage _decodeInboxPage(Map<String, Object?> json) {
  final rawItems = json['items'];
  if (rawItems is! List) {
    throw const FormatException('notification inbox wire: items must be a list');
  }
  final unreadCount = json['unread_count'];
  if (unreadCount is! int) {
    throw const FormatException(
      'notification inbox wire: unread_count is required — a badge without '
      'it would be a guess',
    );
  }
  return CommunityInboxPage(
    page: CommunityPage<CommunityNotificationItem>(
      items: [
        for (final raw in rawItems)
          if (raw is Map<String, Object?>)
            _decodeNotification(raw)
          else
            throw const FormatException(
              'notification inbox wire: every item must be a JSON object',
            ),
      ],
      cursor: communityCursorFromWire(json['next_cursor']),
    ),
    unreadCount: unreadCount < 0 ? 0 : unreadCount,
  );
}

CommunityNotificationItem _decodeNotification(Map<String, Object?> json) {
  final publicId = json['public_id'];
  final type = json['type'];
  final titleKey = json['title_key'];
  final createdAt = json['created_at'];
  if (publicId is! String ||
      type is! String ||
      titleKey is! String ||
      createdAt is! String) {
    throw const FormatException(
      'notification wire: public_id, type, title_key and created_at are '
      'required',
    );
  }
  final kind = communityNotificationKindFromWire(type);
  if (kind == null) {
    // Egy ISMERETLEN fajtát nem lehet becsületesen megjeleníteni: a UI
    // fajtánként rajzol ikont és cselekvést. Egy „általános" tétel azt
    // állítaná, hogy értjük, mi történt. A kivétel a kulcsot is megnevezi,
    // hogy a szerződés-eltérés látható legyen, ne néma.
    throw FormatException('notification wire: unknown type "$type"');
  }
  return CommunityNotificationItem(
    id: ContentId(publicId),
    kind: kind,
    titleKey: titleKey,
    bodyKey: json['body_key'] as String?,
    createdAt: DateTime.parse(createdAt).toUtc(),
    isRead: json['is_read'] == true,
    // A mélylink azonosítója — a `entity_type` a UI-nak mondja meg, MIRE
    // mutat; az entitás csak az azonosítót viszi.
    relatedContentId: switch (json['entity_id']) {
      final String value when value.isNotEmpty => ContentId(value),
      _ => null,
    },
  );
}

Map<String, String> _decodePreferences(Map<String, Object?> json) {
  final raw = json['preferences'];
  if (raw is! Map) {
    throw const FormatException(
      'notification preferences wire: preferences must be an object',
    );
  }
  return <String, String>{
    for (final entry in raw.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}
