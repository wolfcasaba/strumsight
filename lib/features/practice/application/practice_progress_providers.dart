import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progress/public.dart';
import '../data/local_practice_history_repository.dart';
import '../domain/model/practice_history_entry.dart';
import '../domain/service/practice_progress_aggregator.dart';
import '../../../core/foundation/app_result.dart';

/// Async view of the loaded V2 practice-history list. Backed by
/// [LocalPracticeHistoryRepository] (keyed through the same store as the V2
/// data layer). Loading state is reported through [AsyncValue] (Riverpod 3
/// semantics — `.value` is nullable).
final practiceHistoryV2ListProvider =
    FutureProvider<List<PracticeHistoryEntry>>((ref) async {
      final repository = ref.watch(practiceHistoryRepositoryProvider);
      final result = await repository.load();
      return switch (result) {
        Success(:final value) => value,
        Failure() => const <PracticeHistoryEntry>[],
      };
    });

/// The V1+V2 unified feed, surface as plain entries (the same shape the
/// progress dashboard and the daily-goal provider consume).
final practiceProgressAggregatorProvider = Provider<PracticeProgressAggregator>(
  (_) {
    return const PracticeProgressAggregator();
  },
);

/// The synchronous aggregator result for the currently-loaded V1 log +
/// the **latest successfully loaded** V2 list. When V2 is still loading
/// (or has failed to load), the aggregator falls back to the V1-only data
/// — a failed V2 load NEVER blocks the dashboard.
final practiceProgressFeedProvider =
    Provider<AsyncValue<(List<PracticeEntry>, List<PracticeHistoryEntry>)>>((
      ref,
    ) {
      final v1 = ref.watch(practiceLogProvider);
      final v2Async = ref.watch(practiceHistoryV2ListProvider);
      // AsyncValue.value is nullable (Riverpod 3.3.2) — when V2 is still
      // loading or has errored, fall back to an empty list (the V1 entries are
      // always safe to show).
      final v2 = v2Async.value ?? const <PracticeHistoryEntry>[];
      return AsyncValue.data((v1, v2));
    });

/// The aggregated [AggregatedPracticeEntry] feed, synchronous from the
/// dashboard's perspective: V1 is always available, V2 is the latest
/// successfully loaded value (empty on a still-loading V2).
final aggregatedPracticeFeedProvider = Provider<List<AggregatedPracticeEntry>>((
  ref,
) {
  final aggregator = ref.watch(practiceProgressAggregatorProvider);
  final feed = ref.watch(practiceProgressFeedProvider);
  // Use .value (nullable) — never `.valueOrNull` (Riverpod 3.3.2).
  final tuple = feed.value;
  if (tuple == null) {
    // Strictly V1-only if the tuple is in a non-data state.
    final v1 = ref.watch(practiceLogProvider);
    return aggregator.aggregate(v1: v1, v2: const <PracticeHistoryEntry>[]);
  }
  final (v1, v2) = tuple;
  return aggregator.aggregate(v1: v1, v2: v2);
});

/// Provider-side helper that exposes the same rollup the dashboard needs.
/// Lives next to the aggregator so future widgets can read these numbers
/// without re-implementing them.
int aggregatedSecondsForDay(Ref ref, int day) {
  final aggregator = ref.watch(practiceProgressAggregatorProvider);
  final entries = ref.watch(aggregatedPracticeFeedProvider);
  return aggregator.secondsForDay(entries, day);
}
