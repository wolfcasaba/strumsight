// Javító sáv 2026-09-06 (R6): the `practiceResult` route used to build
// `PracticeResultFallback` unconditionally — every finished practice landed
// on "result unavailable" even though the entry had just been written.
// The route now resolves the entry the session hand-off names
// (`practice_result_target.dart`) and falls back only when there is truly
// nothing to show.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/practice_progress_providers.dart';
import '../application/practice_result_target.dart';
import '../domain/model/practice_history_entry.dart';
import 'screens/practice_result_screen.dart';

/// What the route renders — the pure outcome of [resolvePracticeResultView].
sealed class PracticeResultView {
  const PracticeResultView();
}

/// The entry is on its way (record in flight, or the list is re-loading).
final class PracticeResultViewLoading extends PracticeResultView {
  const PracticeResultViewLoading();
}

/// Nothing to show — the documented "result unavailable" state.
final class PracticeResultViewFallback extends PracticeResultView {
  const PracticeResultViewFallback();
}

/// The entry to render.
final class PracticeResultViewEntry extends PracticeResultView {
  const PracticeResultViewEntry(this.entry);

  final PracticeHistoryEntry entry;
}

/// Picks the entry for [target] out of [history].
///
/// * a named session whose entry is not in the list yet is `loading` while
///   the record is in flight or the list is refreshing, and `fallback` once
///   the list settled without it;
/// * no hand-off (cold route) shows the newest entry, if any.
PracticeResultView resolvePracticeResultView({
  required PracticeResultTarget target,
  required AsyncValue<List<PracticeHistoryEntry>> history,
}) {
  switch (target) {
    case PracticeResultTargetPending():
      return const PracticeResultViewLoading();
    case PracticeResultTargetFailed():
      return const PracticeResultViewFallback();
    case PracticeResultTargetSession(:final sessionId, :final recorded):
      final entries = history.value ?? const <PracticeHistoryEntry>[];
      for (final entry in entries) {
        if (entry.id == sessionId) return PracticeResultViewEntry(entry);
      }
      if (!recorded || history.isLoading) {
        return const PracticeResultViewLoading();
      }
      return const PracticeResultViewFallback();
    case PracticeResultTargetNone():
      final entries = history.value;
      if (entries == null) {
        return history.isLoading
            ? const PracticeResultViewLoading()
            : const PracticeResultViewFallback();
      }
      PracticeHistoryEntry? newest;
      for (final entry in entries) {
        if (newest == null || entry.createdAt.isAfter(newest.createdAt)) {
          newest = entry;
        }
      }
      if (newest == null) return const PracticeResultViewFallback();
      return PracticeResultViewEntry(newest);
  }
}

/// The `practiceResult` route body.
class PracticeResultRoute extends ConsumerWidget {
  const PracticeResultRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = resolvePracticeResultView(
      target: ref.watch(practiceResultTargetProvider),
      history: ref.watch(practiceHistoryV2ListProvider),
    );
    return switch (view) {
      PracticeResultViewLoading() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      PracticeResultViewFallback() => const PracticeResultFallback(),
      PracticeResultViewEntry(:final entry) => PracticeResultScreen(
        entry: entry,
      ),
    };
  }
}
