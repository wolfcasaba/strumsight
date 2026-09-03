/// Public surface of the Practice feature (SDD Ch2 §8.1, E02-R12).
///
/// Exposes the practice entry points another feature (or the app shell) is
/// allowed to know about — the Hub and Setup screens, the `PreparePractice`
/// sink, and the route argument parser. The Hub and Setup are flag-gated
/// routes: in a build with `practiceEngineV2Enabled == false` the routes are
/// not registered, so importing them here does NOT make them reachable.
library;

export 'presentation/practice_route_args.dart';
export 'presentation/screens/practice_history_screen.dart';
export 'presentation/screens/practice_hub_screen.dart';
export 'presentation/screens/practice_result_screen.dart';
export 'presentation/screens/practice_session_screen.dart';
export 'presentation/screens/speed_builder_screen.dart';
export 'presentation/widgets/practice_mode_card.dart';
export 'application/practice_catalog_controller.dart'
    show practiceCatalogProvider;
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
export 'data/local_practice_history_repository.dart'
    show practiceHistoryRepositoryProvider;
export 'data/practice_history_recorder.dart' show PracticeHistoryRecorder;
export 'data/practice_session_result_history_mapper.dart'
    show PracticeSessionResultHistoryMapper;
export 'data/vision/practice_vision_adapter.dart';
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
export 'domain/model/practice_difficulty.dart' show PracticeDifficulty;
export 'domain/model/practice_event.dart' show PracticeEvent;
export 'domain/model/practice_event.dart' show isCanonicalPracticeChordLabel;
export 'domain/model/practice_history_entry.dart' show PracticeHistoryEntry;
export 'domain/model/practice_metric_snapshot.dart'
    show
        PracticeMetricDimension,
        PracticeMetricDimensionAvailable,
        PracticeMetricDimensionInsufficientData,
        PracticeMetricDimensionNotApplicable,
        PracticeMetricSnapshot;
export 'domain/model/practice_mode.dart' show PracticeMode;
export 'domain/model/practice_observation.dart' show StrumObservation;
export 'domain/model/practice_session_config.dart' show PracticeSessionConfig;
export 'domain/model/practice_session_result.dart'
    show PracticeFinishReason, PracticeSessionResult;
export 'presentation/widgets/practice_vision_dimension.dart';
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
    show NoopPracticeSessionRecorder, PracticeSessionRecorder;
export 'domain/service/practice_direction_scorer.dart'
    show PracticeDirectionScorer;
export 'domain/service/practice_event_matcher.dart' show PracticeEventMatcher;
export 'domain/service/practice_target_compiler.dart'
    show compilePracticeTarget;
// E03-R21 — Speed Builder is the Song Trainer's only public contract for
// step-up tempo policy. The trainer imports these types through this public
// barrel; a trainer-owned copy is forbidden by the §3 architectural rule.
export 'domain/model/speed_builder_policy.dart' show SpeedBuilderPolicy;
export 'domain/model/speed_builder_state.dart'
    show
        AdaptiveSuggestion,
        AdaptiveSuggestionKind,
        AdaptiveSuggestionReason,
        SpeedBuilderState,
        SpeedBuilderStatus;
export 'domain/service/speed_builder_engine.dart' show SpeedBuilderEngine;
