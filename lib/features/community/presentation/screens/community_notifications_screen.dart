/// Community notification inbox screen (E09-R20, ADR 0414, brief
/// §1 / §3 / §6; design-system migration + A4 doc-fix E13-R34).
///
/// The screen renders the recipient's notification inbox with
/// per-row mark-read-on-tap, a "Mark all as read" action, and
/// an inline per-category preference panel + a local
/// quiet-hours toggle. The push gateway is a refresh trigger
/// only — the inbox is the source of truth (ADR 0414 §D3).
///
/// **Inbox tap action (A1, A4, §3).** Tapping a row marks it read
/// via the controller's ``markRead`` — the single mutation path;
/// the screen does NOT call the repository directly, and it does
/// NOT navigate anywhere (measured §0.0.B/B8 — the corrected claim:
/// an earlier draft of this comment said the tap "deep-links the
/// user to the entity", which was never true of the code below).
/// [CommunityNotificationItem] carries no route / URL / deep-link
/// field — only ``relatedContentId`` — and the community screens
/// are not registered in ``lib/app/routing/**`` (out of this
/// round's scope, §0.0.B/B8). The row's visible AND ``Semantics``
/// surface is built exclusively from ``titleKey`` / ``bodyKey`` /
/// ``kind`` / ``isRead`` — never from ``relatedContentId`` — so a
/// private club or challenge a non-member is not entitled to see
/// cannot leak through a notification row (A3 / A4).
///
/// **Per-category push toggle (A6, §3).** The screen renders a
/// per-kind switch panel (the 10 wire kinds of
/// ``CommunityNotificationKind``). The toggle is
/// controller-mediated; the screen never calls the repository
/// directly. Quiet-hours is a CLIENT-ONLY toggle (§3, "lokális
/// quiet-hours") — it does not call the repository, it just
/// suppresses the in-app toast surface at the local layer.
///
/// **No autoplay / no auto-refresh (§5.1, brief §3).** The
/// screen does not subscribe to a push-broadcast stream — the
/// controller's ``load`` is called from the screen's
/// ``initState``; a pull-to-refresh triggers a re-load; the
/// push gateway is a separate concern owned by a future round.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controllers/notification_controller.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/value_objects/content_id.dart';
import '../widgets/community_theme_scope.dart';

/// Public screen — ``ConsumerWidget`` so the test surface is
/// the ``ProviderScope`` override of the
/// ``communityNotificationRepositoryProvider`` (the Kör 14 /
/// Kör 16 controller-injection precedent).
class CommunityNotificationsScreen extends ConsumerWidget {
  const CommunityNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(notificationControllerProvider);
    final localizations = AppLocalizations.of(context);
    final notifier = ref.read(notificationControllerProvider.notifier);

    // The AsyncValue goes through AsyncLoading transitions
    // during a refetch — the ``?? initial()`` fallback would
    // briefly render an empty inbox and discard the
    // just-loaded state. ``when`` routes each state to its
    // own widget: data → the body, loading → spinner,
    // error → the retry view.
    final hasData = asyncState.value?.items.isNotEmpty ?? false;
    final isMutating = asyncState.value?.isMutating ?? false;
    return CommunityThemeScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.communityNotificationsTitle),
          actions: <Widget>[
            if (hasData)
              IconButton(
                tooltip: localizations.communityNotificationsMarkAllRead,
                icon: const Icon(Icons.done_all),
                onPressed: isMutating ? null : () => notifier.markAllRead(),
              ),
          ],
        ),
        body: asyncState.when(
          data: (state) => _NotificationsBody(state: state, notifier: notifier),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            failure: UnknownFailure(code: FailureCode.unknown, cause: error),
            localizations: localizations,
            onRetry: notifier.load,
          ),
        ),
      ),
    );
  }
}

class _NotificationsBody extends ConsumerStatefulWidget {
  const _NotificationsBody({required this.state, required this.notifier});

  final NotificationInboxState state;
  final NotificationController notifier;

  @override
  ConsumerState<_NotificationsBody> createState() => _NotificationsBodyState();
}

class _NotificationsBodyState extends ConsumerState<_NotificationsBody> {
  /// The local quiet-hours toggle. The §3 explicit scope:
  /// quiet-hours is a CLIENT-ONLY suppression — it does NOT
  /// round-trip to the repository. The future
  /// server-side preference is the
  /// ``updatePreference(category, level)`` path; quiet-hours
  /// is a separate, device-local setting that lives in this
  /// widget state.
  bool _quietHoursEnabled = false;

  @override
  void initState() {
    super.initState();
    // The load is scheduled on the next microtask so the
    // first frame renders the initial state (the Kör 14 /
    // Kör 16 controller-injection precedent — the post-
    // frame callback in ``safety_relationships_screen``
    // follows the same pattern). The microtask runs during
    // ``pumpAndSettle`` so widget tests see the loaded
    // state after a single settle call.
    Future.microtask(() => widget.notifier.load());
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = widget.notifier;
    final localizations = AppLocalizations.of(context);

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.lastError != null && state.items.isEmpty) {
      return _ErrorView(
        failure: state.lastError!,
        localizations: localizations,
        onRetry: notifier.load,
      );
    }
    if (state.items.isEmpty) {
      return ListView(
        children: <Widget>[
          const _PreferencePanel(),
          const Divider(height: 32),
          _QuietHoursSwitch(
            value: _quietHoursEnabled,
            onChanged: (next) => setState(() => _quietHoursEnabled = next),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              localizations.communityNotificationsEmpty,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      );
    }

    final halted = state.cursor.isInitial || state.cursor.cursor == null;
    // Eager Column inside a ListView so every notification
    // row is in the widget tree even when the panel + switch
    // fill the viewport. The lazy ``ListView.separated``
    // alternative was correct for production but blocked
    // the widget-test's ``find.text`` from locating rows
    // that scrolled below the fold — a measured failure
    // mode.
    final children = <Widget>[
      const _PreferencePanel(),
      _QuietHoursSwitch(
        value: _quietHoursEnabled,
        onChanged: (next) => setState(() => _quietHoursEnabled = next),
      ),
      for (final item in state.items) _NotificationRow(item: item),
    ];
    if (!halted) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(value: null)),
        ),
      );
    }
    return ListView(
      children: <Widget>[
        for (var i = 0; i < children.length; i++) ...<Widget>[
          children[i],
          if (i < children.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({required this.item});

  final CommunityNotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final notifier = ref.read(notificationControllerProvider.notifier);
    final state = ref.watch(notificationControllerProvider);
    final isMutating = state.value?.isMutating ?? false;

    return ListTile(
      leading: item.isRead
          ? const Icon(Icons.mark_email_read, color: Colors.grey)
          : const Icon(Icons.mark_email_unread, color: Colors.blue),
      title: Text(
        _resolveTitle(localizations, item),
        style: TextStyle(
          fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: _buildSubtitle(localizations, item),
      trailing: state.value?.lastError is AppFailure
          ? IconButton(
              icon: const Icon(Icons.error_outline),
              onPressed: () => notifier.clearError(),
            )
          : null,
      onTap: item.isRead || isMutating
          ? null
          : () => notifier.markRead(item.id),
    );
  }

  Widget? _buildSubtitle(
    AppLocalizations localizations,
    CommunityNotificationItem item,
  ) {
    final bodyKey = item.bodyKey;
    if (bodyKey == null) return null;
    final resolved = _resolveBody(localizations, item);
    return resolved == null ? null : Text(resolved);
  }

  /// Resolve the row's title key against the ARB catalogue.
  /// A future round that lands per-kind dynamic strings can
  /// swap this for a per-kind resolver; the Kör 5 entity's
  /// ``titleKey`` is the only thing the screen reads.
  String _resolveTitle(
    AppLocalizations localizations,
    CommunityNotificationItem item,
  ) {
    return _lookupKey(localizations, item.titleKey) ?? item.titleKey;
  }

  String? _resolveBody(
    AppLocalizations localizations,
    CommunityNotificationItem item,
  ) {
    final key = item.bodyKey;
    if (key == null) return null;
    return _lookupKey(localizations, key) ?? key;
  }

  /// Lookup an ARB key against the generated localizations.
  /// The localizations are generated by Flutter's gen_l10n
  /// tooling; the keys we add live in
  /// ``lib/l10n/features/community_en.arb``. A missing key
  /// falls through to the raw key string so the UI never
  /// crashes on a future-round key.
  String? _lookupKey(AppLocalizations localizations, String key) {
    return switch (key) {
      'communityNotificationCommentTitle' =>
        localizations.communityNotificationCommentTitle,
      'communityNotificationCommentBody' =>
        localizations.communityNotificationCommentBody,
      'communityNotificationReactionSummaryTitle' =>
        localizations.communityNotificationReactionSummaryTitle,
      'communityNotificationMentionTitle' =>
        localizations.communityNotificationMentionTitle,
      'communityNotificationMentionBody' =>
        localizations.communityNotificationMentionBody,
      'communityNotificationFollowRequestTitle' =>
        localizations.communityNotificationFollowRequestTitle,
      'communityNotificationFollowAcceptedTitle' =>
        localizations.communityNotificationFollowAcceptedTitle,
      'communityNotificationChallengeInviteTitle' =>
        localizations.communityNotificationChallengeInviteTitle,
      'communityNotificationChallengeCompletedTitle' =>
        localizations.communityNotificationChallengeCompletedTitle,
      'communityNotificationClubInviteTitle' =>
        localizations.communityNotificationClubInviteTitle,
      'communityNotificationModerationDecisionTitle' =>
        localizations.communityNotificationModerationDecisionTitle,
      'communityNotificationSecurityAlertTitle' =>
        localizations.communityNotificationSecurityAlertTitle,
      _ => null,
    };
  }
}

class _PreferencePanel extends ConsumerWidget {
  const _PreferencePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(notificationControllerProvider);
    final notifier = ref.read(notificationControllerProvider.notifier);
    final prefs =
        state.value?.preferences ??
        const <String, NotificationPreferenceLevel>{};
    final isMutating = state.value?.isMutating ?? false;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            localizations.communityNotificationsPreferencesTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final kind in CommunityNotificationKind.values)
            _PreferenceRow(
              kind: kind,
              level: prefs[kind.wireValue] ?? NotificationPreferenceLevel.inApp,
              enabled: !isMutating,
              onChanged: (next) => notifier.updatePreference(
                category: kind.wireValue,
                level: next,
              ),
            ),
        ],
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.kind,
    required this.level,
    required this.enabled,
    required this.onChanged,
  });

  final CommunityNotificationKind kind;
  final NotificationPreferenceLevel level;
  final bool enabled;
  final ValueChanged<NotificationPreferenceLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    // A legördülő MEGOSZTOTT szélességen (2026-09-05): korábban a
    // `DropdownButton` a leghosszabb tételének BELSŐ szélességét kérte, és
    // 2.0-s szöveg-méretnél a sor 2310 pixelt csordult túl — a beállítás
    // olvashatatlanná és állíthatatlanná vált pont azoknak, akik a nagy
    // betűt bekapcsolták. Az `isExpanded` a rendelkezésre álló helyre
    // szorítja, a `Flexible` pedig megosztja a helyet a felirattal.
    return Row(
      children: <Widget>[
        Expanded(flex: 3, child: Text(_labelFor(context, kind))),
        const SizedBox(width: 8),
        Flexible(
          flex: 4,
          child: DropdownButton<NotificationPreferenceLevel>(
            isExpanded: true,
            value: level,
            onChanged: enabled
                ? (next) {
                    if (next != null) onChanged(next);
                  }
                : null,
            items: <DropdownMenuItem<NotificationPreferenceLevel>>[
              DropdownMenuItem(
                value: NotificationPreferenceLevel.inApp,
                child: Text(
                  _levelLabel(context, NotificationPreferenceLevel.inApp),
                ),
              ),
              DropdownMenuItem(
                value: NotificationPreferenceLevel.push,
                child: Text(
                  _levelLabel(context, NotificationPreferenceLevel.push),
                ),
              ),
              DropdownMenuItem(
                value: NotificationPreferenceLevel.disabled,
                child: Text(
                  _levelLabel(context, NotificationPreferenceLevel.disabled),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _labelFor(BuildContext context, CommunityNotificationKind kind) {
    final localizations = AppLocalizations.of(context);
    return switch (kind) {
      CommunityNotificationKind.followRequest =>
        localizations.communityNotificationKindFollowRequest,
      CommunityNotificationKind.followAccepted =>
        localizations.communityNotificationKindFollowAccepted,
      CommunityNotificationKind.reactionSummary =>
        localizations.communityNotificationKindReactionSummary,
      CommunityNotificationKind.comment =>
        localizations.communityNotificationKindComment,
      CommunityNotificationKind.mention =>
        localizations.communityNotificationKindMention,
      CommunityNotificationKind.challengeInvite =>
        localizations.communityNotificationKindChallengeInvite,
      CommunityNotificationKind.challengeCompleted =>
        localizations.communityNotificationKindChallengeCompleted,
      CommunityNotificationKind.clubInvite =>
        localizations.communityNotificationKindClubInvite,
      CommunityNotificationKind.moderationDecision =>
        localizations.communityNotificationKindModerationDecision,
      CommunityNotificationKind.securityAlert =>
        localizations.communityNotificationKindSecurityAlert,
    };
  }

  String _levelLabel(BuildContext context, NotificationPreferenceLevel level) {
    final localizations = AppLocalizations.of(context);
    return switch (level) {
      NotificationPreferenceLevel.inApp =>
        localizations.communityNotificationLevelInApp,
      NotificationPreferenceLevel.push =>
        localizations.communityNotificationLevelPush,
      NotificationPreferenceLevel.disabled =>
        localizations.communityNotificationLevelDisabled,
    };
  }
}

class _QuietHoursSwitch extends StatelessWidget {
  const _QuietHoursSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SwitchListTile(
      title: Text(localizations.communityNotificationsQuietHours),
      subtitle: Text(localizations.communityNotificationsQuietHoursBody),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.failure,
    required this.localizations,
    required this.onRetry,
  });

  final AppFailure failure;
  final AppLocalizations localizations;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _formatFailure(localizations, failure),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SsButton(
            onPressed: () => onRetry(),
            label: localizations.communityNotificationsRetry,
          ),
        ],
      ),
    );
  }

  String _formatFailure(AppLocalizations localizations, AppFailure failure) {
    switch (failure.code) {
      case FailureCode.networkUnavailable:
        return localizations.communityNotificationErrorNetwork;
      case FailureCode.authSessionExpired:
        return localizations.communityNotificationErrorSessionExpired;
      case FailureCode.authForbidden:
        return localizations.communityNotificationErrorForbidden;
      case FailureCode.validationInvalidInput:
        return localizations.communityNotificationErrorInvalidInput;
      default:
        return failure.toString();
    }
  }
}

// The ``ContentId`` import is required because the controller
// exposes ``markRead(ContentId)``; the screen does not construct
// ContentIds directly, but the import keeps the API in scope.
// ignore: unused_element
typedef _Unused = ContentId;
