/// Repository contract for the Community notification inbox
/// (E09-R05, ADR 0399 §1, SDD §17, §21.5-like inbox route, §24.1
/// polling).
///
/// The inbox is the single source of truth for notification content;
/// push is a delivery channel, not a primary record (SDD §17.2).
/// Push payload MUST NOT replace inbox contents on the client.
library;

import '../entities/notification_item.dart';
import '../value_objects/content_id.dart';
import 'community_page.dart';

abstract interface class CommunityNotificationRepository {
  /// Fetch the inbox page (cursor-paged). Items are server-ordered
  /// (newest first).
  Future<CommunityPage<CommunityNotificationItem>> inboxPage({
    required Object cursor,
    required int limit,
  });

  /// Mark a single notification as read. Idempotent (re-marking a
  /// read item is a no-op).
  Future<void> markRead({
    required ContentId notificationId,
    required String idempotencyKey,
  });

  /// Mark every unread notification up to [upToId] as read. The
  /// bulk endpoint is the §17.4 aggregation-friendly path used by
  /// the inbox "Mark all as read" action.
  Future<void> markAllReadUpTo({
    required ContentId upToId,
    required String idempotencyKey,
  });

  /// Fetch the notification preference for [category] — `inApp`,
  /// `push` or `disabled`. The aggregate map is returned so the
  /// settings UI can render a list without N+1 calls.
  Future<Object> preferences();

  /// Update the per-category notification preference.
  Future<void> updatePreference({
    required String category,
    required String level,
    required String idempotencyKey,
  });
}
