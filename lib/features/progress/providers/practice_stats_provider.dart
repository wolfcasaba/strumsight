import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../practice/public.dart';
import '../model/practice_stats.dart';

/// The ONE session/seconds/strokes rollup every hub reads (learner-loop
/// round 4, "one progress model"): built from the V1 + V2 aggregated feed
/// (`aggregatedPracticeFeedProvider`), so a Practice V2 session counts on the
/// Today hub, the Profile hub, the streak screen and the progress screen the
/// same way a Learn or Live moment does. Reading the raw V1 log through
/// `PracticeStats(ref.watch(practiceLogProvider))` is the pre-round pattern
/// that made V2 sessions invisible to those screens (E16-R05 finding L4).
final practiceStatsProvider = Provider<PracticeStats>((ref) {
  return PracticeStats.fromAggregated(
    ref.watch(aggregatedPracticeFeedProvider),
  );
});
