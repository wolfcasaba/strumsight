/// Dio-backed implementation of [CommunityNotificationRepository]
/// (E09-R20 contract, ADR 0414 §D3 — the inbox is the source of
/// truth; production wiring round 2026-09-15).
///
/// The repository rides the **shared** ``accountApiClientProvider``
/// (the ``communityApiClientProvider`` precedent in
/// ``profile_repository_impl.dart``): JWT + base URL live in one
/// place, and a ``null`` client (account layer off) selects the
/// [DisabledCommunityNotificationRepository] stand-in whose every
/// call throws ``ConfigurationFailure`` — the shape the
/// ``NotificationController`` already reports through ``lastError``.
///
/// **Backend route status (measured 2026-09-15).** The backend
/// carries the inbox SERVICE
/// (``backend/app/community/notifications/notification_service.py``:
/// ``list_inbox`` / ``mark_read`` / ``mark_all_read_up_to`` /
/// ``get_preferences`` / ``set_preference``) but NO HTTP router
/// mounts it — ``backend/app/community/routers/`` has no
/// notifications module and ``community/__init__.py`` includes none.
/// The five methods below are coded against the route shape those
/// service functions imply (documented per method), so the client
/// side is complete once the router lands. Until then every call
/// reaches a 404 and surfaces as the typed
/// ``NetworkFailure(code: networkBadResponse, retryable: false)``
/// from ``mapNetworkFailure`` — never a silent no-op (L309).
///
/// | Method               | Route (expected)                                |
/// |----------------------|-------------------------------------------------|
/// | ``inboxPage``        | ``GET /community/notifications?limit=&cursor=`` |
/// | ``markRead``         | ``POST /community/notifications/{id}/read``     |
/// | ``markAllReadUpTo``  | ``POST /community/notifications/read-all``      |
/// | ``preferences``      | ``GET /community/notifications/preferences``    |
/// | ``updatePreference`` | ``PUT …/notifications/preferences/{category}``  |
///
/// Wire row shape (mirrors ``models/notification.py`` column names):
/// ``public_id`` / ``type`` / ``title_key`` / ``body_key`` /
/// ``entity_id`` (``related_content_id`` accepted as an alias — the
/// service's A5 deleted-entity path suppresses it to ``null``) /
/// ``is_read`` / ``created_at``. Envelope: ``{"items": [...],
/// "next_cursor": "..."|null}`` (the ``ClubPage`` / ``ChallengePage``
/// precedent).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../features/auth/public.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import 'community_repository_support.dart';

/// The shared account client, read lazily (the
/// ``communityApiClientProvider`` precedent).
final communityNotificationApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// Pick the implementation for the given client: the HTTP one when
/// the account layer is on, the disabled stand-in otherwise.
CommunityNotificationRepository createCommunityNotificationRepository(
  ApiClient? client, {
  AppLogger? logger,
}) {
  if (client == null) return const DisabledCommunityNotificationRepository();
  return HttpCommunityNotificationRepository(client, logger: logger);
}

/// Disabled-mode fallback: every call throws ``ConfigurationFailure``.
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

/// Live HTTP-backed notification inbox repository.
class HttpCommunityNotificationRepository
    implements CommunityNotificationRepository {
  HttpCommunityNotificationRepository(this._client, {AppLogger? logger})
    : _logger = logger ?? const NoopAppLogger();

  final ApiClient _client;
  final AppLogger _logger;

  /// ``GET /community/notifications?limit=&cursor=`` — the
  /// ``notification_service.list_inbox(cursor, limit)`` surface.
  /// The query string is inlined because ``ApiClient.getJson``
  /// takes no query map (the Kör 9 profile-search precedent).
  @override
  Future<CommunityPage<CommunityNotificationItem>> inboxPage({
    required Object cursor,
    required int limit,
  }) async {
    final cursorValue = communityCursorQueryValue(cursor);
    final querySegments = <String>[
      'limit=${Uri.encodeQueryComponent('$limit')}',
      if (cursorValue != null)
        'cursor=${Uri.encodeQueryComponent(cursorValue)}',
    ];
    final path = '/community/notifications?${querySegments.join('&')}';
    final result = await _client.getJson<dynamic>(
      path,
      decode: decodeInboxPage,
    );
    return switch (result) {
      Success(:final value) =>
        value as CommunityPage<CommunityNotificationItem>,
      Failure(:final error) => throw error,
    };
  }

  /// ``POST /community/notifications/{id}/read`` — the
  /// ``notification_service.mark_read`` surface. Idempotent on the
  /// server by the ``(recipient, notification_id)`` natural key;
  /// the client key travels in the body like every Kör 7+ mutation.
  @override
  Future<void> markRead({
    required ContentId notificationId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/notifications/${notificationId.value}/read',
      data: <String, Object?>{'idempotency_key': idempotencyKey},
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  /// ``POST /community/notifications/read-all`` with the cutoff id —
  /// the ``notification_service.mark_all_read_up_to`` surface.
  @override
  Future<void> markAllReadUpTo({
    required ContentId upToId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/notifications/read-all',
      data: <String, Object?>{
        'up_to_public_id': upToId.value,
        'idempotency_key': idempotencyKey,
      },
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  /// ``GET /community/notifications/preferences`` — the
  /// ``notification_service.get_preferences`` map (``category →
  /// "inApp" | "push" | "disabled"``). The controller's
  /// ``_decodePreferences`` reads a ``Map<String, String>``; the
  /// decoder accepts either a bare map or a ``{"preferences": {...}}``
  /// envelope so a router that wraps the map still round-trips.
  @override
  Future<Object> preferences() async {
    final result = await _client.getJson<Map<String, String>>(
      '/community/notifications/preferences',
      decode: decodePreferences,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  /// ``PUT /community/notifications/preferences/{category}`` — the
  /// ``notification_service.set_preference(category, level)``
  /// surface. The level is validated server-side (``ValueError`` →
  /// 422 → ``ValidationFailure``); the client forwards the wire
  /// string the controller already produced.
  @override
  Future<void> updatePreference({
    required String category,
    required String level,
    required String idempotencyKey,
  }) async {
    final result = await _client.putJson<dynamic>(
      '/community/notifications/preferences/'
      '${Uri.encodeComponent(category)}',
      data: <String, Object?>{
        'level': level,
        'idempotency_key': idempotencyKey,
      },
      decode: (json) => json,
    );
    if (result is Failure) {
      throw result.error;
    }
  }

  // ---- internal ----------------------------------------------------------

  /// Decode the ``{"items": [...], "next_cursor": ...}`` envelope.
  ///
  /// The cursor mapping mirrors ``decodeChallengeListPage``: a
  /// missing ``next_cursor`` with empty ``items`` halts the pager, a
  /// missing ``next_cursor`` with rows resets to ``initial()``, a
  /// string produces ``continued()``.
  CommunityPage<CommunityNotificationItem> decodeInboxPage(
    Map<String, Object?> json,
  ) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'community notification wire: items must be a list',
      );
    }
    final items = <CommunityNotificationItem>[];
    for (final row in rawItems.whereType<Map>()) {
      final typed = <String, Object?>{};
      row.forEach((key, value) {
        if (key is String) typed[key] = value;
      });
      final item = decodeNotificationOrNull(typed);
      if (item != null) items.add(item);
    }
    final nextCursor = json['next_cursor'];
    final cursorPage = nextCursor == null
        ? (items.isEmpty
              ? const CursorPage.haltedAfterRequest()
              : const CursorPage.initial())
        : CursorPage.continued(nextCursor as String);
    return CommunityPage<CommunityNotificationItem>(
      items: List<CommunityNotificationItem>.unmodifiable(items),
      cursor: cursorPage,
    );
  }

  /// Decode one inbox row. An UNKNOWN ``type`` returns ``null`` and
  /// is logged — the A3 forward-compatibility rule of
  /// ``communityNotificationKindFromWire``: a newer server kind must
  /// not take the whole page down. Every other malformed field is a
  /// ``FormatException`` (→ ``networkBadResponse``).
  CommunityNotificationItem? decodeNotificationOrNull(
    Map<String, Object?> json,
  ) {
    final publicId = json['public_id'];
    if (publicId is! String) {
      throw const FormatException(
        'community notification wire: public_id must be a string',
      );
    }
    final kindWire = json['type'] ?? json['kind'];
    if (kindWire is! String) {
      throw const FormatException(
        'community notification wire: type must be a string',
      );
    }
    final kind = communityNotificationKindFromWire(kindWire);
    if (kind == null) {
      _logger.warning(
        'community.notifications.decode.unknownKind',
        fields: <String, Object?>{'kind': kindWire},
      );
      return null;
    }
    final titleKey = json['title_key'];
    if (titleKey is! String || titleKey.isEmpty) {
      throw const FormatException(
        'community notification wire: title_key must be a non-empty string',
      );
    }
    final bodyKey = json['body_key'];
    if (bodyKey != null && bodyKey is! String) {
      throw const FormatException(
        'community notification wire: body_key must be a string',
      );
    }
    final createdAt = json['created_at'];
    if (createdAt is! String) {
      throw const FormatException(
        'community notification wire: created_at must be a string',
      );
    }
    final parsedCreatedAt = DateTime.tryParse(createdAt);
    if (parsedCreatedAt == null) {
      throw FormatException(
        'community notification wire: unparseable created_at "$createdAt"',
      );
    }
    final isRead = json['is_read'];
    if (isRead is! bool) {
      throw const FormatException(
        'community notification wire: is_read must be a bool',
      );
    }
    final related = json['related_content_id'] ?? json['entity_id'];
    if (related != null && related is! String) {
      throw const FormatException(
        'community notification wire: related_content_id must be a string',
      );
    }
    return CommunityNotificationItem(
      id: ContentId(publicId),
      kind: kind,
      titleKey: titleKey,
      bodyKey: bodyKey as String?,
      createdAt: parsedCreatedAt,
      isRead: isRead,
      relatedContentId: related is String && related.isNotEmpty
          ? ContentId(related)
          : null,
    );
  }

  /// Decode the preference map — bare or under a ``preferences``
  /// key. Non-string entries are dropped (the controller falls back
  /// to ``inApp`` for a missing category).
  Map<String, String> decodePreferences(Map<String, Object?> json) {
    final nested = json['preferences'];
    final source = nested is Map ? nested : json;
    final result = <String, String>{};
    source.forEach((key, value) {
      if (key is String && value is String) result[key] = value;
    });
    return result;
  }
}
