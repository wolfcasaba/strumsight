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
export 'application/practice_observation_gateway.dart'
    show PracticeObservationConfig, PracticeObservationGateway;
export 'application/practice_session_command.dart';
export 'application/practice_session_controller.dart'
    show PracticeSessionController;
export 'application/practice_session_effect.dart';
export 'application/practice_session_providers.dart'
    show
        PracticeSessionInputs,
        practiceMicrophonePermissionProvider,
        practiceSessionControllerProvider;
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
    show
        MetricAvailable,
        MetricInsufficientData,
        MetricNotApplicable,
        MetricValue,
        PracticeMetrics;
export 'domain/model/beat_position.dart' show BeatPosition;
export 'domain/model/compiled_practice_target.dart' show CompiledPracticeTarget;
export 'domain/model/meter.dart' show Meter;
export 'domain/model/practice_definition.dart' show PracticeDefinition;
export 'domain/model/practice_event.dart' show PracticeEvent;
export 'domain/model/practice_event.dart' show isCanonicalPracticeChordLabel;
export 'domain/model/practice_mode.dart' show PracticeMode;
export 'domain/model/practice_observation.dart' show StrumObservation;
export 'domain/model/practice_session_config.dart' show PracticeSessionConfig;
export 'domain/model/practice_session_result.dart'
    show PracticeFinishReason, PracticeSessionResult;
export 'domain/model/practice_session_state.dart'
    show
        PauseCause,
        PracticeCountInKind,
        PracticeSessionState,
        PracticeSessionStatus;
export 'domain/model/practice_attempt_result.dart'
    show PracticeAttemptOutcome, PracticeAttemptResult;
export 'domain/model/practice_source.dart' show PracticeSource;
export 'domain/model/practice_verdict.dart'
    show ChordOutcome, DirectionOutcome, PracticeVerdict, TimingGrade;
export 'domain/model/scoring_profile.dart'
    show ExtraStrumPolicy, PracticeScoreDimension, ScoringProfile;
export 'domain/model/tempo.dart' show Tempo;
export 'domain/model/beat_time_converter.dart' show BeatTimeConverter;
export 'domain/repository/practice_session_recorder.dart'
    show PracticeSessionRecorder;
export 'domain/service/practice_direction_scorer.dart'
    show PracticeDirectionScorer;
export 'domain/service/practice_event_matcher.dart' show PracticeEventMatcher;
export 'domain/service/practice_target_compiler.dart'
    show compilePracticeTarget;
