/// Public surface of the Practice feature (SDD Ch2 §8.1, E02-R12).
///
/// Exposes the practice entry points another feature (or the app shell) is
/// allowed to know about — the Hub and Setup screens, the `PreparePractice`
/// sink, and the route argument parser. The Hub and Setup are flag-gated
/// routes: in a build with `practiceEngineV2Enabled == false` the routes are
/// not registered, so importing them here does NOT make them reachable.
library;

export 'presentation/practice_route_args.dart';
export 'presentation/screens/practice_hub_screen.dart';
export 'presentation/screens/practice_result_screen.dart';
export 'presentation/screens/practice_session_screen.dart';
export 'presentation/widgets/practice_mode_card.dart';
export 'application/practice_setup_controller.dart';
// E02-R19 — the cross-feature recording + progress providers + pure aggregator
// surface. Exporting these here is what lets the Learn/Progress/Streak
// features wire their flag branches and rollups through this public boundary
// without an allowlist deviation.
export 'application/practice_session_recording.dart';
export 'application/practice_progress_providers.dart';
export 'domain/service/practice_progress_aggregator.dart'
    show AggregatedPracticeEntry, PracticeProgressAggregator;
export 'domain/service/practice_session_eligibility.dart'
    show PracticeSessionEligibility, PracticeSessionEligibilityInput;
export 'domain/model/practice_metrics.dart'
    show MetricAvailable, MetricNotApplicable, MetricValue, PracticeMetrics;
