import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../practice/public.dart';
import '../model/practice_stats.dart';

/// The rollup the Profile Hub / Today Hub "sessions" figures are computed
/// from — the V1 Learn log UNIONED with the Practice Engine V2 history
/// (javító sáv 2026-09-06, E16-R05 L4: the hubs read `practiceLogProvider`
/// alone, so a finished V2 quick-start session never moved their numbers).
/// V2 is the latest successfully loaded list; while it loads (or fails) the
/// V1 entries alone are shown, never a blocked dashboard.
final aggregatedPracticeStatsProvider = Provider<PracticeStats>((ref) {
  return PracticeStats.aggregated(ref.watch(aggregatedPracticeFeedProvider));
});
