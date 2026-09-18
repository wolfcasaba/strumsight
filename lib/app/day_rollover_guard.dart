import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/app_lifecycle.dart';
import '../core/platform/platform_providers.dart';
import '../features/gamification/providers/gamification_providers.dart';
import '../features/progress_v2/application/progress_providers.dart';

/// Recomputes the app's cached "today" when it returns to the foreground
/// (ADR 0583).
///
/// `todayEpochDayProvider` and `progressNowProvider` are plain `Provider`s:
/// each reads the clock once and then caches that value for the container's
/// lifetime. An app that sits in the background across midnight therefore
/// keeps evaluating the streak, the day totals and the progress dashboard
/// against YESTERDAY until a cold restart — the user practises, and the app
/// still says the streak is at risk.
///
/// Resume is the hook because it is the first moment the stale answer can be
/// seen; recomputing while the app is not shown would burn work for nobody.
final class DayRolloverGuard {
  DayRolloverGuard({required this._events, required this._onResume}) {
    _events.addListener(_onState);
  }

  final AppLifecycleEvents _events;
  final void Function() _onResume;

  void _onState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _onResume();
  }

  void dispose() => _events.removeListener(_onState);
}

/// Instantiated for the app's lifetime by the app shell. Invalidation is a
/// no-op for a listener when the recomputed value is unchanged (Riverpod only
/// notifies on `!=`), so an in-day resume costs nothing.
final dayRolloverGuardProvider = Provider<DayRolloverGuard>((ref) {
  final guard = DayRolloverGuard(
    events: ref.watch(appLifecycleEventsProvider),
    onResume: () {
      ref.invalidate(todayEpochDayProvider);
      ref.invalidate(progressNowProvider);
    },
  );
  ref.onDispose(guard.dispose);
  return guard;
});
