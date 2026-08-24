import 'package:flutter/material.dart';

/// Every screen-level async state Ch13 Kör 10 unifies (§1).
enum SsAsyncStatus {
  loading,
  content,
  empty,
  offline,
  syncPending,
  degraded,
  permission,
  failure,
  blocked,
}

/// The single switch every screen renders its async data through (§1, ADR
/// 0277).
///
/// [offline], [syncPending] and [degraded] never clear [content] — it stays
/// mounted under a banner (§5.2). Every other status replaces it outright.
/// All slots are required: a caller cannot wire up [SsAsyncState] without
/// deciding what every one of them looks like.
///
/// The [offline]/[syncPending]/[degraded] layout lays [content] out below
/// its banner with `Expanded`, so it requires a **bounded-height** ancestor
/// (a `Scaffold` body, an `Expanded`/`Flexible` slot in a `Column`, a sized
/// box). Placing [SsAsyncState] directly inside an unbounded-height ancestor
/// — e.g. as the direct child of a `SingleChildScrollView` — throws for
/// those three statuses. Give it a fixed height (or wrap it in `Expanded`
/// inside a bounded `Column`) when embedding it in a scrollable screen.
final class SsAsyncState extends StatelessWidget {
  const SsAsyncState({
    super.key,
    required this.status,
    required this.content,
    required this.skeleton,
    required this.loadingSemanticLabel,
    required this.emptyState,
    required this.failureState,
    required this.permissionState,
    required this.blockedState,
    required this.offlineBanner,
    required this.syncPendingBanner,
    required this.degradedBanner,
  });

  final SsAsyncStatus status;

  /// The loaded (or previously cached) content.
  final Widget content;

  final Widget skeleton;

  /// Announced once for the whole [skeleton] region while [status] is
  /// [SsAsyncStatus.loading] — the skeleton boxes themselves carry no
  /// semantics (§5.6).
  final String loadingSemanticLabel;

  final Widget emptyState;
  final Widget failureState;
  final Widget permissionState;
  final Widget blockedState;

  /// Shown above [content] while [status] is [SsAsyncStatus.offline].
  final Widget offlineBanner;

  /// Shown above [content] while [status] is [SsAsyncStatus.syncPending].
  final Widget syncPendingBanner;

  /// Shown above [content] while [status] is [SsAsyncStatus.degraded].
  final Widget degradedBanner;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      SsAsyncStatus.loading => Semantics(
        container: true,
        label: loadingSemanticLabel,
        child: skeleton,
      ),
      SsAsyncStatus.content => content,
      SsAsyncStatus.empty => emptyState,
      SsAsyncStatus.failure => failureState,
      SsAsyncStatus.permission => permissionState,
      SsAsyncStatus.blocked => blockedState,
      SsAsyncStatus.offline => _CachedContentBanner(
        key: const ValueKey('ss-async-state-offline-overlay'),
        banner: offlineBanner,
        content: content,
      ),
      SsAsyncStatus.syncPending => _CachedContentBanner(
        key: const ValueKey('ss-async-state-sync-pending-overlay'),
        banner: syncPendingBanner,
        content: content,
      ),
      SsAsyncStatus.degraded => _CachedContentBanner(
        key: const ValueKey('ss-async-state-degraded-overlay'),
        banner: degradedBanner,
        content: content,
      ),
    };
  }
}

/// Keeps [content] mounted and visible below a status [banner] (§5.2) —
/// offline and sync-pending are never a full-screen replacement.
class _CachedContentBanner extends StatelessWidget {
  const _CachedContentBanner({
    super.key,
    required this.banner,
    required this.content,
  });

  final Widget banner;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        banner,
        Expanded(child: content),
      ],
    );
  }
}
