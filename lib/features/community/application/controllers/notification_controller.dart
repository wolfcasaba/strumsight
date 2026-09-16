/// Community notification inbox + preference state machine
/// (E09-R20, ADR 0414, brief §1 / §3 / §5 / §6).
///
/// The controller is the only place where the caller's inbox and
/// per-category notification preferences are mutated. It is a
/// Riverpod ``AsyncNotifier`` so the screen can reactively re-
/// render on every state transition — the Kör 14
/// ``FeedController`` and Kör 16 ``CommentController`` precedent.
///
/// **Inbox is the source of truth (§5.3).** The push gateway
/// only refreshes the inbox; the controller's ``load`` call
/// reads the server's authoritative state. A lost push (offline
/// device) is at worst a delayed refresh, not information loss
/// (the Kör 5 inbox contract, ADR 0399 §1).
///
/// **Per-category push preference (A6, §3).** The controller
/// calls the repository's ``updatePreference`` for each
/// category, mirroring the Kör 8 ``RelationshipController``
/// pattern. The preference levels are ``inApp`` / ``push`` /
/// ``disabled`` — the wire shape the Kör 5
/// ``CommunityNotificationRepository`` contract carries
/// (§0.0 D5 proactive expansion, brief §6 A6).
///
/// **Idempotency key (§5.2).** Each mutation gets a fresh
/// client-side key. The repository accepts the key on the
/// wire; the server uses the natural key identity (the
/// ``(recipient, notification_id)`` pair for mark-read, the
/// ``(recipient, dedup_key)`` UNIQUE for the create path) as
/// the canonical idempotency surface.
///
/// **No silent no-op (L309).** Every repository call has a
/// try/catch; the controller never swallows a
/// ``StorageException`` or a ``NetworkFailure`` — each one
/// flips the state to a label the UI can show.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/logging/logger_provider.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';

import '../../data/repositories/notification_repository_impl.dart'
    show communityNotificationRepositoryProvider;
export '../../data/repositories/notification_repository_impl.dart'
    show communityNotificationRepositoryProvider;

/// The three preference levels the Kör 5
/// ``CommunityNotificationRepository`` contract exposes
/// (brief §3, A6 cell). ``disabled`` is the highest restriction
/// (no in-app inbox, no push); ``push`` allows both; ``inApp``
/// allows only the in-app inbox (the safe default — a user
/// with no explicit preference gets the in-app inbox but no
/// push).
enum NotificationPreferenceLevel { inApp, push, disabled }

/// Wire-string form of [NotificationPreferenceLevel]. The
/// controller speaks the wire string; the model layer
/// round-trips through it.
String notificationPreferenceLevelToWire(NotificationPreferenceLevel level) {
  switch (level) {
    case NotificationPreferenceLevel.inApp:
      return 'inApp';
    case NotificationPreferenceLevel.push:
      return 'push';
    case NotificationPreferenceLevel.disabled:
      return 'disabled';
  }
}

NotificationPreferenceLevel notificationPreferenceLevelFromWire(String wire) {
  switch (wire) {
    case 'inApp':
      return NotificationPreferenceLevel.inApp;
    case 'push':
      return NotificationPreferenceLevel.push;
    case 'disabled':
      return NotificationPreferenceLevel.disabled;
    default:
      return NotificationPreferenceLevel.inApp;
  }
}

/// The full inbox + preference state the screen renders.
///
/// The state is intentionally a single immutable record so
/// the screen's ``ref.watch`` re-renders on EVERY meaningful
/// change (new item, mark-read, preference change). The
/// preference map is a snapshot — a ``Map<Category, Level>``
/// keyed by the wire-kind string.
class NotificationInboxState {
  const NotificationInboxState({
    required this.items,
    required this.cursor,
    required this.isLoading,
    required this.isLoadingMore,
    required this.isMutating,
    required this.preferences,
    required this.lastError,
  });

  const NotificationInboxState.initial()
    : items = const <CommunityNotificationItem>[],
      cursor = const CursorPage.initial(),
      isLoading = false,
      isLoadingMore = false,
      isMutating = false,
      preferences = const <String, NotificationPreferenceLevel>{},
      lastError = null;

  /// The items visible on screen, in server order (newest
  /// first — the Kör 5 ``CommunityPage`` contract).
  final List<CommunityNotificationItem> items;

  /// The opaque cursor the next ``loadMore`` would consume.
  final CursorPage cursor;

  /// True while the first-page fetch is in flight.
  final bool isLoading;

  /// True while a load-more call is in flight.
  final bool isLoadingMore;

  /// True while a mark-read / mark-all-read /
  /// update-preference mutation is in flight. The screen
  /// disables the row-tap and the "Mark all as read" button
  /// while this is true.
  final bool isMutating;

  /// The per-category preference snapshot, keyed by wire-kind
  /// (the 10 values of ``CommunityNotificationKind.wireValue``).
  /// A missing key means "default" (inApp — the safe
  /// default; a user with no explicit preference gets the
  /// in-app inbox but no push).
  final Map<String, NotificationPreferenceLevel> preferences;

  /// The most recent failure (a list, mark-read, or
  /// preference mutation). Cleared on the next successful
  /// mutation.
  final AppFailure? lastError;

  /// The unread count — derived from the items list. The
  /// Kör 5 wire contract doesn't expose an unread-count
  /// endpoint, so the controller computes it locally from
  /// the inbox page; the server-side count is the source of
  /// truth and a future round can wire a dedicated endpoint.
  int get unreadCount => items.where((item) => !item.isRead).length;

  NotificationInboxState copyWith({
    List<CommunityNotificationItem>? items,
    Object? cursor = _sentinel,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isMutating,
    Map<String, NotificationPreferenceLevel>? preferences,
    Object? lastError = _sentinel,
  }) {
    return NotificationInboxState(
      items: items ?? this.items,
      cursor: identical(cursor, _sentinel) ? this.cursor : cursor as CursorPage,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isMutating: isMutating ?? this.isMutating,
      preferences: preferences ?? this.preferences,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as AppFailure?,
    );
  }
}

const Object _sentinel = Object();

// A `communityNotificationRepositoryProvider` EGYETLEN definíciója a
// `data/repositories/notification_repository_impl.dart`-ban él.
// Ugyanaz az egy-definíció szabály, mint a feed- és a
// kihívás-repositorynál — l. az ottani indoklást.

/// The community notification inbox + preference state machine.
class NotificationController extends AsyncNotifier<NotificationInboxState> {
  CommunityNotificationRepository get _repo =>
      ref.read(communityNotificationRepositoryProvider);

  AppLogger get _logger => ref.read(appLoggerProvider);

  @override
  Future<NotificationInboxState> build() async {
    return const NotificationInboxState.initial();
  }

  /// Open the inbox for the current account. Reads the first
  /// page from the repository and merges the preference
  /// snapshot. A repository failure leaves the items list
  /// empty and surfaces the failure via ``lastError``.
  Future<void> load({int pageSize = 25}) async {
    final current = state.value ?? const NotificationInboxState.initial();
    state = AsyncData(current.copyWith(isLoading: true, lastError: null));
    try {
      final page = await _repo.inboxPage(
        cursor: const CursorPage.initial(),
        limit: pageSize,
      );
      final prefsRaw = await _repo.preferences();
      final prefs = _decodePreferences(prefsRaw);
      state = AsyncData(
        current.copyWith(
          items: page.items,
          cursor: page.cursor,
          isLoading: false,
          preferences: prefs,
        ),
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.notifications.load.failure',
        fields: {'pageSize': pageSize},
      );
      state = AsyncData(current.copyWith(isLoading: false, lastError: failure));
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.notifications.load.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'pageSize': pageSize},
      );
      state = AsyncData(
        current.copyWith(
          isLoading: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Load the next page of inbox items, if any.
  Future<void> loadMore({int pageSize = 25}) async {
    final current = state.value;
    if (current == null) return;
    if (current.isLoading || current.isLoadingMore) return;
    if (current.cursor.isInitial || current.cursor.cursor == null) {
      // No next page to ask for.
      return;
    }
    state = AsyncData(current.copyWith(isLoadingMore: true, lastError: null));
    try {
      final page = await _repo.inboxPage(
        cursor: current.cursor,
        limit: pageSize,
      );
      state = AsyncData(
        current.copyWith(
          items: <CommunityNotificationItem>[...current.items, ...page.items],
          cursor: page.cursor,
          isLoadingMore: false,
        ),
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.notifications.loadMore.failure',
        fields: {'pageSize': pageSize},
      );
      state = AsyncData(
        current.copyWith(isLoadingMore: false, lastError: failure),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.notifications.loadMore.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'pageSize': pageSize},
      );
      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Mark a single notification as read. Optimistic — the
  /// item's ``isRead`` flips in state immediately, then the
  /// repository call lands; a failure rolls the flip back
  /// and surfaces the error.
  Future<void> markRead(ContentId notificationId) async {
    final current = state.value;
    if (current == null) return;
    if (current.isMutating) return;
    final previous = current.items;
    final optimistic = <CommunityNotificationItem>[
      for (final item in current.items)
        if (item.id == notificationId) item.copyWith(isRead: true) else item,
    ];
    state = AsyncData(
      current.copyWith(items: optimistic, isMutating: true, lastError: null),
    );
    try {
      await _repo.markRead(
        notificationId: notificationId,
        idempotencyKey: _newIdempotencyKey(),
      );
      state = AsyncData((state.value ?? current).copyWith(isMutating: false));
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.notifications.markRead.failure',
        fields: {'notificationId': notificationId.value},
      );
      state = AsyncData(
        current.copyWith(
          items: previous,
          isMutating: false,
          lastError: failure,
        ),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.notifications.markRead.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'notificationId': notificationId.value},
      );
      state = AsyncData(
        current.copyWith(
          items: previous,
          isMutating: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Mark every unread notification as read. The repository
  /// contract uses ``markAllReadUpTo(upToId)`` — the
  /// ``upToId`` is the LAST item the user has seen (the
  /// newest, in server order). The controller passes the
  /// first item's id (the most-recent push, at the top of
  /// the inbox) as the cutoff.
  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;
    if (current.isMutating) return;
    if (current.items.isEmpty) return;
    final cutoff = current.items.first.id;
    final previous = current.items;
    final optimistic = <CommunityNotificationItem>[
      for (final item in current.items) item.copyWith(isRead: true),
    ];
    state = AsyncData(
      current.copyWith(items: optimistic, isMutating: true, lastError: null),
    );
    try {
      await _repo.markAllReadUpTo(
        upToId: cutoff,
        idempotencyKey: _newIdempotencyKey(),
      );
      state = AsyncData((state.value ?? current).copyWith(isMutating: false));
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.notifications.markAllRead.failure',
        fields: {'upToId': cutoff.value},
      );
      state = AsyncData(
        current.copyWith(
          items: previous,
          isMutating: false,
          lastError: failure,
        ),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.notifications.markAllRead.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'upToId': cutoff.value},
      );
      state = AsyncData(
        current.copyWith(
          items: previous,
          isMutating: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Update the per-category notification preference (A6,
  /// §3). The repository's ``updatePreference`` accepts a
  /// ``(category, level, idempotencyKey)`` triple; the
  /// controller optimistically updates the local snapshot,
  /// then awaits the server confirmation. A failure rolls
  /// the snapshot back.
  Future<void> updatePreference({
    required String category,
    required NotificationPreferenceLevel level,
  }) async {
    final current = state.value;
    if (current == null) return;
    if (current.isMutating) return;
    final previous = current.preferences;
    final optimistic = <String, NotificationPreferenceLevel>{
      ...current.preferences,
      category: level,
    };
    state = AsyncData(
      current.copyWith(
        preferences: optimistic,
        isMutating: true,
        lastError: null,
      ),
    );
    try {
      await _repo.updatePreference(
        category: category,
        level: notificationPreferenceLevelToWire(level),
        idempotencyKey: _newIdempotencyKey(),
      );
      state = AsyncData((state.value ?? current).copyWith(isMutating: false));
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.notifications.updatePreference.failure',
        fields: {'category': category, 'level': level.name},
      );
      state = AsyncData(
        current.copyWith(
          preferences: previous,
          isMutating: false,
          lastError: failure,
        ),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.notifications.updatePreference.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'category': category, 'level': level.name},
      );
      state = AsyncData(
        current.copyWith(
          preferences: previous,
          isMutating: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Drop the last error (the user dismissed the banner).
  void clearError() {
    final current = state.value;
    if (current == null || current.lastError == null) return;
    state = AsyncData(current.copyWith(lastError: null));
  }

  // ---- internal ----------------------------------------------------------

  /// Decode the aggregate preference map the repository
  /// hands back. The Kör 5 contract types the return as
  /// ``Object`` (the wire shape is opaque to the
  /// repository); the controller knows the server returns
  /// a ``Map<String, String>`` (category → wire level).
  Map<String, NotificationPreferenceLevel> _decodePreferences(Object raw) {
    if (raw is! Map) return const <String, NotificationPreferenceLevel>{};
    final result = <String, NotificationPreferenceLevel>{};
    raw.forEach((key, value) {
      if (key is String && value is String) {
        result[key] = notificationPreferenceLevelFromWire(value);
      }
    });
    return result;
  }

  int _idempotencyCounter = 0;

  String _newIdempotencyKey() {
    _idempotencyCounter += 1;
    return 'e09-r20-$_idempotencyCounter-${DateTime.now().microsecondsSinceEpoch}';
  }
}

/// Provider for the [NotificationController]. The screen
/// reads this directly; the repository dependency is pulled
/// from [communityNotificationRepositoryProvider], which
/// production wires to the future Kör 21 ``HttpCommunity
/// NotificationRepository`` and tests override with a
/// recording fake.
final notificationControllerProvider =
    AsyncNotifierProvider.autoDispose<
      NotificationController,
      NotificationInboxState
    >(NotificationController.new);
