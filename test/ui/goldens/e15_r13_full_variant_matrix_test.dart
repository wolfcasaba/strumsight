// The E15-R13 closing variant matrix (brief §0.0.A/R3, §3): a PNG-free pump
// of the MEASURED reachable-screen set (71, `dart run
// tool/check_screen_reachability.dart --format json`) ∪ {ProgressDashboardScreen,
// SkillDetailScreen} (§0.0.A/R5 — reachable only after the parallel E16-R02
// merges) × {light, dark} × {en, hu} × {compact portrait 412×915, landscape
// 915×412} × {textScale 1.0, 2.0}. Every cell asserts TWO things — no
// `RenderFlex` overflow and no exception during pumping — via
// `FlutterError.onError` (never a text heuristic on rendered output), plus a
// completeness cell (A1) that reruns the reachability measurement at test
// time and asserts it is a subset of (matrix screens ∪ a dated, reasoned
// exclusion list).
//
// Two-commit implementation order (§0.0.A/R3, §8): this file was built in
// two passes — the 46 screens with an already-merged `test/ui/goldens/**`
// pump fixture, plus the two R5 screens (48 total, "A-level"), committed
// first with the remaining 25 reachable screens on the exclusion list
// (reasoned + a named follow-up round); then the remaining 24 screens with a
// `test/features/**` fixture ("B-level") were added and removed from the
// exclusion list, which shrank to its final single entry —
// `WrappedPreviewScreen`, the one reachable screen with NO merged fixture
// anywhere in the tree (measured, §0.0.A/R3) — reasoned with a named,
// unscheduled follow-up round. The exclusion list may only shrink (never
// silently grow, L180); each remaining entry is machine-checked below to
// carry both a real reason and a named follow-up round.
//
// Fixture pattern: mirrors `test/ui/goldens/e13_r36_variant_matrix_test.dart`
// — `preferenceOverrides()` for every cell's baseline `keyValueStoreProvider`
// plus a screen-specific `List<Override>`. UNLIKE `e13_r36`, the theme is
// `SsLightTheme.data()`/`SsDarkTheme.data()` (measured: `AppTheme.light()/
// .dark()` alone carries only `AppPalette` — a design-system-migrated screen
// that reads `Theme.of(context).extension<SsColorScheme>()!` null-checks
// under it; `SsLightTheme`/`SsDarkTheme` are a strict superset, built ON TOP
// of `AppTheme`, that also register `SsColorScheme`/`SsTypography`/
// `SsStateOverlays`, so both migrated and legacy screens render under it).
// Each fixture's OWN `overridesBuilder()` includes exactly one
// `keyValueStoreProvider` override (almost always `...preferenceOverrides()`
// — `PracticeHistoryScreen` is the one exception, seeding its own store via
// `preferenceStoreOverride(...)` instead) — `ProviderScope` throws if the
// SAME provider is overridden twice in one `overrides` list, so `_pumpCell`
// itself adds nothing and just forwards `overridesBuilder()` verbatim.
// Individual fixtures were adapted from the merged golden/feature tests
// named in each block's comment.
//
// Pump strategy deviates from `e13_r36` in ONE respect: this file uses a
// bounded three-frame pump (`tester.pump()` + two `Duration(milliseconds:
// 16)` pumps) instead of `pumpAndSettle()`. `StrumReelScreen` starts an
// unconditional, never-stopping `Ticker` on `initState` (measured,
// `lib/features/share/screens/strum_reel_screen.dart:83`) — `pumpAndSettle`
// would hang against it for every one of its 16 cells. A bounded pump still
// renders the full first frame (where a `RenderFlex` overflow or a build
// exception would already have been reported) and gives any `FutureProvider`
// override two extra frames to resolve, without waiting for an animation
// that is designed to never settle.
//
// L558 (mandatory per cell): the `flutter_test` default 800×600 viewport is
// wider AND taller than every phone size below — every cell sets its own
// `tester.view.physicalSize` + `devicePixelRatio` and resets it via
// `addTearDown`, never relying on a shared default.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_chat_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_home_screen.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_hotspot.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_insight.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_timeline.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_repository.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/comparison/analysis_comparison.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_compare_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_metric_detail_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_overview_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_timeline_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/overview_view_model.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_club.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/club_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/community_profile_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_list_screen.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_member_management_screen.dart';
import 'package:strumsight/features/community/presentation/screens/edit_profile_screen.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/features/library_v2/domain/library_item.dart';
import 'package:strumsight/features/library_v2/domain/library_item_source.dart';
import 'package:strumsight/features/library_v2/providers/library_v2_providers.dart';
import 'package:strumsight/features/library_v2/screens/library_item_detail_screen.dart';
import 'package:strumsight/features/library_v2/screens/unified_library_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/features/offline_ai/data/offline_model_source.dart';
import 'package:strumsight/features/offline_ai/model/offline_model.dart';
import 'package:strumsight/features/offline_ai/providers/offline_model_controller.dart';
import 'package:strumsight/features/offline_ai/screens/model_manager_screen.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/onboarding/screens/permission_primer_screen.dart';
import 'package:strumsight/core/audio/audio_providers.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/practice/data/practice_history_serializer.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart'
    hide PracticeFinishReason;
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_policy.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_state.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart'
    as practice_tempo;
import 'package:strumsight/features/practice/domain/service/speed_builder_engine.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/practice_route_args.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_history_screen.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/speed_builder_screen.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';
import 'package:strumsight/features/settings/screens/privacy_center_screen.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/share/screens/share_preview_screen.dart';
import 'package:strumsight/features/share/share_service.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/song_trainer/application/import/import_preview.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_controller.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_state.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_editor_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_preview_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_overview_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_result_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/trainer_setup_screen.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/core/camera/camera_permission.dart';
import 'package:strumsight/core/camera/camera_providers.dart';
import 'package:strumsight/core/camera/camera_session_coordinator.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/application/vision_session_controller.dart';
import 'package:strumsight/features/vision/application/vision_session_state.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';
import 'package:strumsight/features/vision/domain/quality/vision_quality_summary.dart';
import 'package:strumsight/features/vision/domain/vision_session.dart';
import 'package:strumsight/features/vision/domain/vision_session_result.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_result_screen.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_session_screen.dart';
import 'package:strumsight/features/vision/presentation/screens/vision_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../tool/check_screen_reachability.dart';
import '../../fixtures/practice/session/practice_session_test_fixtures.dart';
import '../../support/fake_audio.dart';
import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/fake_settings.dart';
import '../../support/preference_store.dart';

// ---------------------------------------------------------------------------
// Size profiles (§0.0.A/R3 — two, not e13_r36's four: compact portrait +
// landscape).
// ---------------------------------------------------------------------------

enum _ViewportProfile { compactPortrait, landscape }

const _viewportSizes = <_ViewportProfile, Size>{
  _ViewportProfile.compactPortrait: Size(412, 915),
  _ViewportProfile.landscape: Size(915, 412),
};

const _viewportNames = <_ViewportProfile, String>{
  _ViewportProfile.compactPortrait: 'compact_portrait',
  _ViewportProfile.landscape: 'landscape',
};

// ---------------------------------------------------------------------------
// Fixture registry
// ---------------------------------------------------------------------------

/// One matrix entry: the measured `lib/` path (for the A1 completeness
/// cross-check against `ScreenReachability`), a zero-arg widget builder and a
/// zero-arg Riverpod overrides builder (mirrors `e13_r36`'s tuple shape).
final class _ScreenFixture {
  const _ScreenFixture({
    required this.screenPath,
    required this.build,
    required this.overridesBuilder,
  });

  final String screenPath;
  final Widget Function() build;
  final List<Override> Function() overridesBuilder;
}

// ── ai_tutor (test/ui/goldens/e13_r29_screens_golden_test.dart) ────────────

class _GoldenChatController extends ChangeNotifier
    implements TutorChatController {
  _GoldenChatController({
    List<TutorMessage> messages = const <TutorMessage>[],
  }) {
    _messages.addAll(messages);
  }

  final List<TutorMessage> _messages = <TutorMessage>[];
  final StreamController<TutorChatState> _statesController =
      StreamController<TutorChatState>.broadcast();

  @override
  List<TutorMessage> get messages => List<TutorMessage>.unmodifiable(_messages);
  @override
  TutorTurnStatus status = TutorTurnStatus.idle;
  @override
  String responseText = '';
  @override
  String draft = '';
  @override
  bool isOnline = true;
  @override
  List<TutorBannerKind> banners = const <TutorBannerKind>[];
  @override
  Stream<TutorChatState> get states => _statesController.stream;

  @override
  void setDraft(String value) {}
  @override
  void send() {}
  @override
  void cancel() {}
  @override
  void retry() {}
  @override
  void setOnline(bool value) {}
  @override
  void setBanners(List<TutorBannerKind> value) {}
}

TutorMessage _tutorUserMessage(String text) => TutorMessage(
  id: TutorMessageId('golden-u'),
  role: TutorMessageRole.user,
  createdAt: DateTime.utc(2026, 8, 5),
  sequence: 0,
  deliveryState: TutorMessageDeliveryState.complete,
  blocks: <TutorContentBlock>[TutorTextBlock(text: text)],
);

TutorMessage _tutorReplyMessage(String text) => TutorMessage(
  id: TutorMessageId('golden-t'),
  role: TutorMessageRole.tutor,
  createdAt: DateTime.utc(2026, 8, 5, 0, 1),
  sequence: 1,
  deliveryState: TutorMessageDeliveryState.complete,
  blocks: <TutorContentBlock>[TutorTextBlock(text: text)],
);

Widget _tutorChatScreen() => const TutorChatScreen();
List<Override> _tutorChatOverrides() => [
  ...preferenceOverrides(),
  tutorChatControllerProvider.overrideWithValue(
    _GoldenChatController(
      messages: <TutorMessage>[
        _tutorUserMessage('How do I fix my strumming timing?'),
        _tutorReplyMessage(
          'Try slowing the tempo by 20% and counting out loud on every '
          'downbeat before speeding back up.',
        ),
      ],
    ),
  ),
];

Widget _tutorHomeScreen() => const TutorHomeScreen();
List<Override> _tutorHomeOverrides() => [
  ...preferenceOverrides(),
  tutorChatControllerProvider.overrideWithValue(_GoldenChatController()),
];

// ── audio_analysis (test/ui/goldens/e13_r27_screens_golden_test.dart) ──────

AnalysisComparison _analysisComparisonFixture() => AnalysisComparison(
  beforeAnalysisId: 'before',
  afterAnalysisId: 'after',
  metrics: <MetricComparison>[
    MetricComparison(
      metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
      direction: MetricComparisonDirection.improved,
      confidence: 0.8,
      sampleCount: 12,
      beforeValue: 40,
      afterValue: 30,
      absoluteDelta: -10,
      relativeDelta: -0.25,
    ),
    MetricComparison(
      metricId: AnalysisMetricId.dynamicsDrift,
      direction: MetricComparisonDirection.inconclusive,
      confidence: 0.5,
      sampleCount: 6,
      inconclusiveReason: ComparisonInconclusiveReason.inputQualityDiverged,
    ),
  ],
);

Widget _analysisCompareScreen() =>
    AnalysisCompareScreen(comparison: _analysisComparisonFixture());
List<Override> _analysisCompareOverrides() => [...preferenceOverrides()];

OverviewMetricCard _analysisDetailCard() => const OverviewMetricCard(
  metricId: 'metric.golden.v1',
  metricLabel: 'Timing accuracy',
  unit: 'ms',
  state: OverviewMetricCardState.available,
  valueText: '45 ms',
  confidence: 0.9,
  statusLabel: 'High confidence',
  reasonText: '',
  tipText: '',
  isUsable: true,
);

Widget _analysisMetricDetailScreen() => AnalysisMetricDetailScreen(
  metrics: <OverviewMetricCard>[_analysisDetailCard()],
);
List<Override> _analysisMetricDetailOverrides() => [...preferenceOverrides()];

AnalysisMetricResult _analysisOverviewMetric(
  String id,
  CapabilityStatus status, {
  AnalysisMetricValue? value,
  CapabilityUnavailableReason? unavailableReason,
  String unit = 's',
}) => AnalysisMetricResult(
  id: id,
  version: 1,
  status: status,
  confidence: status == CapabilityStatus.available ? 0.9 : 0.4,
  unit: unit,
  sampleCount: 10,
  evidence: const <String>[],
  value: value,
  unavailableReason: unavailableReason,
);

AnalysisDocument _analysisOverviewDocument() => AnalysisDocument(
  id: 'e15-r13-golden-fixture',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 20),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(minutes: 2, seconds: 5),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'golden',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1.0.0',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'cfg',
    modelManifestIds: const <String>[],
    inputFingerprint: 'golden',
    platform: 'android',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: 0.82,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(duration: const Duration(minutes: 2, seconds: 5)),
  metrics: <AnalysisMetricResult>[
    _analysisOverviewMetric(
      AnalysisMetricId.timingMeanAbsoluteError,
      CapabilityStatus.available,
      value: ScalarMetricValue(0.05),
    ),
    _analysisOverviewMetric(
      AnalysisMetricId.rhythmRushDragBias,
      CapabilityStatus.degraded,
      value: ScalarMetricValue(0.01),
    ),
    _analysisOverviewMetric(
      AnalysisMetricId.dynamicsStrokeStrengthCv,
      CapabilityStatus.unavailable,
      unavailableReason: CapabilityUnavailableReason.clipTooShort,
    ),
    _analysisOverviewMetric(
      AnalysisMetricId.harmonyChordCoverage,
      CapabilityStatus.notApplicable,
    ),
  ],
  hotspots: <AnalysisHotspot>[
    AnalysisHotspot(
      id: 'h1',
      kind: AnalysisHotspotKind.timing,
      start: const Duration(seconds: 20),
      end: const Duration(seconds: 21),
      severity: AnalysisHotspotSeverity.medium,
      confidence: .8,
      metricIds: const <String>[],
      evidenceIds: const <String>[],
    ),
  ],
  insights: <AnalysisInsight>[
    AnalysisInsight(
      id: 'i-rec',
      ruleId: 'r',
      ruleVersion: '1',
      priority: AnalysisInsightPriority.high,
      kind: AnalysisInsightKind.recommendation,
      factIds: const <String>[],
      messageKey: 'analysisInsightRushBias',
      messageArgs: const <String, String>{'milliseconds': '12'},
      recommendedAction: AnalysisRecommendedAction.slowDown,
    ),
  ],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);

Widget _analysisOverviewScreen() =>
    AnalysisOverviewScreen(document: _analysisOverviewDocument());
List<Override> _analysisOverviewOverrides() => [...preferenceOverrides()];

Widget _analysisTimelineScreen() =>
    AnalysisTimelineScreen(document: _analysisOverviewDocument());
List<Override> _analysisTimelineOverrides() => [...preferenceOverrides()];

// ── auth (test/ui/goldens/e13_r36_variant_matrix_test.dart) ────────────────

Widget _loginScreen() => const LoginScreen();
List<Override> _loginOverrides() => [
  ...preferenceOverrides(),
  tokenStoreProvider.overrideWithValue(FakeTokenStore()),
  authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
];

// ── chords / learn (test/ui/goldens/e13_r20_screens_golden_test.dart) ──────

Widget _chordLibraryScreen() => const ChordLibraryScreen();
List<Override> _chordLibraryOverrides() => [...preferenceOverrides()];

Widget _lessonListScreen() => LessonListScreen(now: DateTime(2026, 8, 26));
List<Override> _lessonListOverrides() => [...preferenceOverrides()];

// ── community (test/ui/goldens/e13_r34/e13_r33_screens_golden_test.dart) ───

final class _FakeClubsRepository implements CommunityClubRepository {
  final CommunityClub seedClub = CommunityClub(
    id: ContentId('golden-club-1'),
    name: 'Blues Lovers',
    description: 'Weekly blues jam sessions and setlist sharing.',
    visibility: ClubVisibility.discoverable,
    tags: const <String>['blues', 'jam'],
    ownerId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5e01'),
    memberCount: 24,
    myRole: ClubRole.owner,
    createdAt: DateTime.utc(2026, 6, 1),
  );

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async => CommunityPage<CommunityClub>(
    items: <CommunityClub>[
      seedClub,
      CommunityClub(
        id: ContentId('golden-club-2'),
        name: 'Jazz Standards Circle',
        description: 'Practicing jazz standards together.',
        visibility: ClubVisibility.private,
        tags: const <String>[],
        ownerId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5e02'),
        memberCount: 8,
        myRole: ClubRole.member,
        createdAt: DateTime.utc(2026, 5, 12),
      ),
    ],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async =>
      seedClub;

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async {}
}

Widget _clubMemberManagementScreen() =>
    ClubMemberManagementScreen(clubId: ContentId('golden-club-1'));
List<Override> _clubMemberManagementOverrides() => [
  ...preferenceOverrides(),
  communityClubRepositoryProvider.overrideWithValue(_FakeClubsRepository()),
  clubMemberListProvider.overrideWith(
    (ref, clubId) async => <ClubMemberRow>[
      ClubMemberRow(
        memberPublicId: 'row-1',
        profilePublicId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f01'),
        role: ClubRole.owner,
        joinedAt: DateTime.utc(2026, 6, 1),
      ),
      ClubMemberRow(
        memberPublicId: 'row-2',
        profilePublicId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f02'),
        role: ClubRole.member,
        joinedAt: DateTime.utc(2026, 7, 3),
      ),
    ],
  ),
];

final class _FakeCommunityProfileRepository
    implements CommunityProfileRepository {
  _FakeCommunityProfileRepository({this.profile});
  CommunityProfile? profile;

  @override
  Future<CommunityProfile?> fetchMyProfile() async => profile;
  @override
  Future<CommunityProfile> fetchById(PublicUserId userId) =>
      throw UnsupportedError('golden fixture');
  @override
  Future<CommunityProfile?> fetchByHandle(CommunityHandle handle) =>
      throw UnsupportedError('golden fixture');
  @override
  Future<CommunityPage<CommunityProfile>> searchProfiles({
    required String query,
    required Object cursor,
  }) async => const CommunityPage<CommunityProfile>(
    items: <CommunityProfile>[],
    cursor: CursorPage.haltedAfterRequest(),
  );
  @override
  Future<AppResult<CommunityProfile>> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) => throw UnsupportedError('golden fixture');
}

Widget _editProfileScreen() =>
    const EditProfileScreen(mode: EditProfileMode.create, initialProfile: null);
List<Override> _editProfileOverrides() => [
  ...preferenceOverrides(),
  appConfigProvider.overrideWith(
    (ref) => AppConfig.resolve(
      environment: AppEnvironment.development,
      apiBaseUrl: AppConfig.devApiBaseUrl,
      flags: FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: true,
      ),
      diagnosticsToken: AppConfig.devDiagnosticsToken,
      buildMode: 'test',
      appVersion: 'test',
    ),
  ),
  tokenStoreProvider.overrideWithValue(FakeTokenStore('golden-token')),
  authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
  communityProfileRepositoryProvider.overrideWithValue(
    _FakeCommunityProfileRepository(profile: null),
  ),
];

// ── gamification (test/ui/goldens/e13_r32_screens_golden_test.dart) ────────

Widget _achievementsScreen() {
  final definitions = <AchievementDefinition>[
    AchievementDefinition(
      id: 'first_valid_session',
      category: AchievementCategory.practice,
      titleKey: 'achievementFirstValidSessionTitle',
      descriptionKey: 'achievementFirstValidSessionDescription',
      accessibilityDescriptionKey: 'achievementFirstValidSessionSemantics',
      objectives: <AchievementObjective>[
        CountAchievementObjective(
          eventKind: AchievementEventKind.practice,
          target: 1,
        ),
      ],
      tierPrerequisiteIds: const [],
      hidden: false,
      version: 1,
      deprecated: false,
    ),
    AchievementDefinition(
      id: 'practice_starter',
      category: AchievementCategory.practice,
      titleKey: 'achievementPracticeStarterTitle',
      descriptionKey: 'achievementPracticeStarterDescription',
      accessibilityDescriptionKey: 'achievementPracticeStarterSemantics',
      objectives: <AchievementObjective>[
        CountAchievementObjective(
          eventKind: AchievementEventKind.practice,
          target: 5,
        ),
      ],
      tierPrerequisiteIds: const [],
      hidden: false,
      version: 1,
      deprecated: false,
    ),
  ];
  return AchievementsScreen(
    definitions: definitions,
    progressByAchievement: <String, AchievementProgress>{
      'first_valid_session': AchievementProgress(
        achievementId: 'first_valid_session',
        catalogVersion: 1,
        value: 0.6,
      ),
      'practice_starter': AchievementProgress(
        achievementId: 'practice_starter',
        catalogVersion: 1,
        value: 1,
        completedAt: DateTime.utc(2026, 8, 21),
        rewardLedgerEntryId: 'achievement:practice_starter:1',
      ),
    },
    onAchievementSelected: (_) {},
  );
}

List<Override> _achievementsOverrides() => [...preferenceOverrides()];

GamificationProfile _gamificationHubProfile() {
  final curve = LevelCurve(<LevelDefinition>[
    LevelDefinition(
      number: 1,
      levelThreshold: 0,
      titleKey: 'gamification.level.beginner',
    ),
    LevelDefinition(
      number: 2,
      levelThreshold: 100,
      titleKey: 'gamification.level.explorer',
    ),
    LevelDefinition(
      number: 3,
      levelThreshold: 250,
      titleKey: 'gamification.level.consistent',
    ),
  ]);
  return GamificationProfile(
    schemaVersion: gamificationProfileSchemaVersion,
    totalXp: 60,
    progress: curve.progressForTotalXp(60),
  );
}

Widget _gamificationHubScreen() => GamificationHubScreen(
  profile: _gamificationHubProfile(),
  activeQuestCount: 2,
  streakCurrentDays: 4,
  masteryUnlockedCount: 1,
  inboxUnseenCount: 2,
  latestResult: const LatestHubResult(
    title: 'A measured session',
    body: 'Five XP components credited.',
    earnedXp: 30,
  ),
  onOpenLevelDetail: () {},
  onOpenInbox: () {},
  onOpenAchievements: () {},
  onOpenStreak: () {},
  onOpenQuests: () {},
  onOpenMastery: () {},
);
List<Override> _gamificationHubOverrides() => [...preferenceOverrides()];

QuestDefinition _questsDefinitionFixture() => QuestDefinition(
  id: 'daily_open_chord_progression',
  schemaVersion: questDefinitionSchemaVersion,
  cadence: QuestCadence.daily,
  objective: SkillTagQuestObjective('barre_chords'),
  schedule: QuestSchedule(
    schemaVersion: questScheduleSchemaVersion,
    generationEpochDay: 20000,
    timezoneOffsetMinutes: 0,
    catalogVersion: 1,
    expiresAt: DateTime.utc(2026, 12, 31, 23, 59, 59),
  ),
  reward: QuestReward(baseXp: 50, bonusXp: 0, policyVersion: 1),
);

Widget _questsScreen() {
  final definition = _questsDefinitionFixture();
  final progress = QuestProgress.active(
    definition: definition,
    completedUnits: 2,
    practiceResultIds: const <String>[],
  );
  return QuestsScreen(
    dailyChallengeTitle: "Today's challenge",
    dailyChallenge: DailyChallengeInstance(
      schemaVersion: dailyChallengeInstanceSchemaVersion,
      epochDay: 20000,
      catalogVersion: 1,
      generatedAt: DateTime.utc(2026, 8, 21),
      definition: const StrumPatternChallenge(
        pattern: <StrumDirection>[StrumDirection.down, StrumDirection.down],
        name: 'Steady downstrokes',
      ),
      contentCatalog: DailyChallengeContentCatalogSnapshot(
        schemaVersion: dailyChallengeContentCatalogSchemaVersion,
        catalogVersion: 1,
        chordIds: const <String>[],
        rhythmIds: const <String>[],
        songIds: const <String>[],
        timingContentIds: const <String>[],
      ),
      completion: null,
    ),
    dailyChallengeAvailable: true,
    dailyQuests: [
      QuestViewProjection(
        definition: definition,
        progress: progress,
        targetUnits: 4,
        completedUnits: 2,
        contentAvailable: true,
        sourcePlanLabel: 'Plan block: open chord progression',
      ),
    ],
    weeklyQuests: const [],
    onAction: (_) {},
    now: DateTime.utc(2026, 8, 21, 14),
  );
}

List<Override> _questsOverrides() => [...preferenceOverrides()];

Widget _rewardInboxScreen() {
  final event = RewardEvent(
    id: 'evt-1',
    kind: RewardKind.dailyReward,
    titleKey: 'Daily reward',
    bodyKey: 'You practiced today.',
    earnedXp: 15,
    earnedAt: DateTime.utc(2026, 8, 22, 9),
    sourceLedgerId: 'ledger-evt-1',
  );
  return RewardInboxScreen(
    items: [
      RewardInboxItem(
        id: 'evt-1',
        event: event,
        addedAt: DateTime.utc(2026, 8, 22, 9),
      ),
    ],
    onItemSelected: (_) {},
    onMarkSeen: (_) {},
    pendingCount: 1,
    onRetryPending: () {},
  );
}

List<Override> _rewardInboxOverrides() => [...preferenceOverrides()];

Widget _streakDetailScreen() => StreakDetailScreen(
  state: StreakState(
    current: 3,
    longest: 8,
    lastQualifiedDay: 20400,
    totalQualifiedDays: 12,
    freezes: 2,
  ),
  reason: StreakEvaluationReason.grace,
  weeklyConsistencyDays: 4,
  onRecoveryPressed: () {},
);
List<Override> _streakDetailOverrides() => [...preferenceOverrides()];

// ── library_v2 (test/ui/goldens/e13_r28_screens_golden_test.dart) ──────────

final class _UnusedAnalysisRepository implements AnalysisRepository {
  const _UnusedAnalysisRepository();

  @override
  Future<AppResult<void>> delete(String id) => throw UnimplementedError();
  @override
  Future<AppResult<AnalysisDocument>> getById(String id) =>
      throw UnimplementedError();
  @override
  Future<AppResult<List<AnalysisSummary>>> list() => throw UnimplementedError();
  @override
  Future<AppResult<void>> rename({
    required String id,
    required String newTitle,
  }) => throw UnimplementedError();
  @override
  Future<AppResult<void>> replace(String id, AnalysisSaveRequest request) =>
      throw UnimplementedError();
  @override
  Future<AppResult<void>> save(AnalysisSaveRequest request) =>
      throw UnimplementedError();
}

Widget _libraryItemDetailScreen() {
  final item = AnalysisLibraryItem(
    id: 'golden-detail',
    title: 'Saturday warm-up',
    createdAt: DateTime.utc(2026, 8, 20, 9),
    syncStatus: LibrarySyncStatus.synced,
    hasRawAudio: false,
    hasResult: true,
  );
  return LibraryItemDetailScreen(item: item);
}

List<Override> _libraryItemDetailOverrides() => [
  ...preferenceOverrides(),
  analysisRepositoryProvider.overrideWithValue(
    const _UnusedAnalysisRepository(),
  ),
];

final class _GoldenLibrarySource implements LibraryItemSource {
  const _GoldenLibrarySource(this.type, this._items);

  @override
  final LibraryItemType type;
  final List<LibraryItem> _items;

  @override
  Future<LibrarySourceLoad> load() async => LibrarySourceLoad.success(_items);
}

Widget _unifiedLibraryScreen() => const UnifiedLibraryScreen();
List<Override> _unifiedLibraryOverrides() => [
  ...preferenceOverrides(),
  libraryV2SourcesProvider.overrideWithValue([
    _GoldenLibrarySource(LibraryItemType.analysis, [
      AnalysisLibraryItem(
        id: 'golden-analysis',
        title: 'Saturday warm-up',
        createdAt: DateTime.utc(2026, 8, 20, 9),
        syncStatus: LibrarySyncStatus.synced,
        hasRawAudio: false,
        hasResult: true,
      ),
    ]),
    _GoldenLibrarySource(LibraryItemType.practice, [
      PracticeLibraryItem(
        id: 'golden-practice',
        title: 'Chord switching drill',
        createdAt: DateTime.utc(2026, 8, 19),
        syncStatus: LibrarySyncStatus.pending,
      ),
    ]),
    _GoldenLibrarySource(LibraryItemType.song, [
      SongLibraryItem(
        id: 'golden-song',
        title: 'Wonderwall',
        artist: 'Oasis',
        updatedAt: DateTime.utc(2026, 8, 18),
        syncStatus: LibrarySyncStatus.synced,
      ),
    ]),
    _GoldenLibrarySource(LibraryItemType.setlist, [
      SetlistLibraryItem(
        id: 'golden-setlist',
        title: 'Saturday gig',
        songCount: 5,
        updatedAt: DateTime.utc(2026, 8, 17),
        syncStatus: LibrarySyncStatus.conflict,
      ),
    ]),
  ]),
];

// ── live / tuner / today (test/ui/goldens/e13_r36_variant_matrix_test.dart)─

Widget _liveScreen() => const LiveScreen();
List<Override> _liveOverrides() {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  return [
    ...preferenceOverrides(),
    strumEngineProvider.overrideWithValue(engine),
  ];
}

Widget _tunerScreen() => const TunerScreen();
List<Override> _tunerOverrides() {
  final engine = FakeTunerEngine();
  addTearDown(engine.dispose);
  return [
    ...preferenceOverrides(),
    tunerEngineProvider.overrideWithValue(engine),
  ];
}

Widget _todayHubScreen() => TodayHubScreen(now: DateTime(2026, 8, 27));
List<Override> _todayHubOverrides() => [...preferenceOverrides()];

// ── metronome (test/ui/goldens/e13_r19_screens_golden_test.dart) ───────────

Widget _metronomeScreen() => const MetronomeScreen();
List<Override> _metronomeOverrides() => [...preferenceOverrides()];

// ── offline_ai (test/ui/goldens/e13_r35_screens_golden_test.dart) ──────────

final class _GoldenOfflineModelSource implements OfflineModelSource {
  const _GoldenOfflineModelSource();

  @override
  Future<AppResult<OfflineModelAsset>> fetchCandidate(String modelId) async {
    const bytes = <int>[1, 2, 3, 4, 5];
    return Success(
      OfflineModelAsset(
        modelId: modelId,
        version: '1.4.0',
        expectedSha256: offlineModelChecksum(bytes),
        bytes: bytes,
      ),
    );
  }
}

Widget _modelManagerScreen() => const ModelManagerScreen();
List<Override> _modelManagerOverrides() => [
  ...preferenceOverrides(),
  offlineModelSourceProvider.overrideWithValue(
    const _GoldenOfflineModelSource(),
  ),
];

Widget _privacyCenterScreen() => const PrivacyCenterScreen();
List<Override> _privacyCenterOverrides() => [...preferenceOverrides()];

Widget _settingsScreen() => const Scaffold(body: SettingsScreen());
List<Override> _settingsOverrides() => [
  ...preferenceOverrides(),
  tokenStoreProvider.overrideWithValue(FakeTokenStore()),
  authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
  settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
];

Widget _sharePreviewScreen() => SharePreviewScreen(
  result: AnalyzeResult(
    durationSec: 12,
    bpm: 96,
    chords: const [
      TimelineChord(label: 'C', startSec: 0, endSec: 3),
      TimelineChord(label: 'G', startSec: 3, endSec: 6),
    ],
    strums: [
      for (var i = 0; i < 6; i++)
        TimelineStrum(
          direction: i.isEven ? StrumDirection.down : StrumDirection.up,
          timeSec: i.toDouble(),
          confidence: 0.9,
        ),
    ],
  ),
  title: 'Practice riff',
  shareService: const ShareService(),
);
List<Override> _sharePreviewOverrides() => [...preferenceOverrides()];

// ── onboarding (test/ui/goldens/e13_r16_screens_golden_test.dart) ──────────

Widget _onboardingScreen() => const OnboardingScreen();
List<Override> _onboardingOverrides() => [...preferenceOverrides()];

Widget _permissionPrimerScreen() => const PermissionPrimerScreen();
List<Override> _permissionPrimerOverrides() => [
  ...preferenceOverrides(),
  microphonePermissionGatewayProvider.overrideWithValue(
    FakeMicrophonePermissionGateway(state: MicrophonePermissionState.denied),
  ),
];

// ── practice (test/ui/goldens/e13_r21/e13_r22_screens_golden_test.dart) ────

Map<String, Object> _practiceHistorySeed() {
  final entries = [
    PracticeHistoryEntry(
      id: 'golden.history.1',
      modeCode: PracticeMode.strumPattern.code,
      sourceCode: PracticeSource.builtin.code,
      createdAt: DateTime(2026, 7, 30, 9, 0),
      definitionId: 'golden.history.1',
      displayTitle: 'Quarter downstrokes',
      finishReasonCode: 'completedAllTargets',
      activeDuration: const Duration(seconds: 45),
      pausedDuration: Duration.zero,
      attemptsCount: 1,
      finalMetricSnapshot: const PracticeMetricSnapshot(
        completion: PracticeMetricDimensionAvailable(0.95),
        rhythm: PracticeMetricDimensionAvailable(0.9),
        direction: PracticeMetricDimensionAvailable(0.88),
        chord: PracticeMetricDimensionNotApplicable(),
        overall: PracticeMetricDimensionAvailable(0.91),
      ),
      totalTargets: 16,
      resolvedTargets: 16,
      scorePoints: 850,
      maxCombo: 16,
      meanAbsoluteOffset: const Duration(milliseconds: 14),
      timingBias: Duration.zero,
      coachingSummary: const [],
      skillTags: const ['rhythm.quarter_notes'],
      highestStableTempoBpm: null,
    ),
    PracticeHistoryEntry(
      id: 'golden.history.2',
      modeCode: PracticeMode.chordChanges.code,
      sourceCode: PracticeSource.builtin.code,
      createdAt: DateTime(2026, 7, 29, 18, 30),
      definitionId: 'golden.history.2',
      displayTitle: 'G to D changes',
      finishReasonCode: 'interrupted',
      activeDuration: const Duration(seconds: 30),
      pausedDuration: Duration.zero,
      attemptsCount: 1,
      finalMetricSnapshot: const PracticeMetricSnapshot(
        completion: PracticeMetricDimensionAvailable(0.4),
        rhythm: PracticeMetricDimensionAvailable(0.5),
        direction: PracticeMetricDimensionNotApplicable(),
        chord: PracticeMetricDimensionAvailable(0.45),
        overall: PracticeMetricDimensionAvailable(0.45),
      ),
      totalTargets: 20,
      resolvedTargets: 8,
      scorePoints: 300,
      maxCombo: 4,
      meanAbsoluteOffset: const Duration(milliseconds: 30),
      timingBias: const Duration(milliseconds: 10),
      coachingSummary: const [],
      skillTags: const ['chord.change.g_to_d'],
      highestStableTempoBpm: null,
    ),
  ];
  return <String, Object>{
    StorageKeys.practiceHistoryV2: jsonLikeEncode(entries),
  };
}

/// `PracticeHistorySerializer.toJson` returns a `Map<String, Object?>` per
/// entry — encoded with `dart:convert`'s `jsonEncode`, matching how the
/// stored document is really persisted (`preference_store.dart`'s
/// `storedCollection` pattern), so the seeded store round-trips exactly like
/// production data would.
String jsonLikeEncode(List<PracticeHistoryEntry> entries) {
  const serializer = PracticeHistorySerializer();
  return storedCollectionLike(<Map<String, Object?>>[
    for (final entry in entries) serializer.toJson(entry),
  ]);
}

String storedCollectionLike(List<Map<String, Object?>> items) =>
    storedCollection(items);

Widget _practiceHistoryScreen() => const PracticeHistoryScreen();
List<Override> _practiceHistoryOverrides() => [
  preferenceStoreOverride(InMemoryKeyValueStore(_practiceHistorySeed())),
];

PracticeHistoryEntry _practiceResultFixture() => PracticeHistoryEntry(
  id: 'golden.result.v1',
  modeCode: PracticeMode.chordProgression.code,
  sourceCode: PracticeSource.builtin.code,
  createdAt: DateTime(2026, 8, 1, 12, 0),
  definitionId: 'golden.result',
  displayTitle: 'G to D changes',
  finishReasonCode: 'completedAllTargets',
  activeDuration: const Duration(minutes: 1, seconds: 20),
  pausedDuration: Duration.zero,
  attemptsCount: 3,
  finalMetricSnapshot: const PracticeMetricSnapshot(
    completion: PracticeMetricDimensionAvailable(0.92),
    rhythm: PracticeMetricDimensionAvailable(0.88),
    direction: PracticeMetricDimensionAvailable(0.9),
    chord: PracticeMetricDimensionAvailable(0.85),
    overall: PracticeMetricDimensionAvailable(0.9),
  ),
  totalTargets: 20,
  resolvedTargets: 19,
  scorePoints: 900,
  maxCombo: 18,
  meanAbsoluteOffset: const Duration(milliseconds: 15),
  timingBias: const Duration(milliseconds: -3),
  coachingSummary: const ['practice.coach.positive_reinforcement'],
  skillTags: const ['chord.change.g_to_d'],
  highestStableTempoBpm: 110.0,
);

Widget _practiceResultScreen() =>
    PracticeResultScreen(entry: _practiceResultFixture());
List<Override> _practiceResultOverrides() => [...preferenceOverrides()];

practice_tempo.Tempo _speedTempo(double bpm) => practice_tempo.Tempo(bpm);

SpeedBuilderState _speedBuilderActiveFixture() {
  final policy = SpeedBuilderPolicy(
    startBpm: _speedTempo(100),
    targetBpm: _speedTempo(160),
    stepBpm: 10,
  );
  const engine = SpeedBuilderEngine();
  var state = SpeedBuilderState.initial(policy);
  PracticeAttemptResult attempt(int index, double bpm) => PracticeAttemptResult(
    index: index,
    tempo: _speedTempo(bpm),
    metrics: const PracticeMetrics(
      completion: MetricAvailable(0.98),
      rhythm: MetricAvailable(0.9),
      direction: MetricNotApplicable(),
      chord: MetricNotApplicable(),
      overall: MetricAvailable(0.9),
      totalTargets: 8,
      resolvedTargets: 8,
      maxCombo: 8,
      scorePoints: 800,
      meanAbsoluteOffset: Duration(milliseconds: 20),
      timingBias: Duration.zero,
    ),
    verdicts: const <PracticeVerdict>[],
    outcome: PracticeAttemptOutcome.passed,
  );
  state = engine.record(state, attempt(0, 100));
  state = engine.record(state, attempt(1, 100));
  state = engine.record(state, attempt(2, 110));
  return state;
}

Widget _speedBuilderScreen() => SpeedBuilderScreen(
  policy: SpeedBuilderPolicy(
    startBpm: _speedTempo(100),
    targetBpm: _speedTempo(160),
    stepBpm: 10,
  ),
  initialState: _speedBuilderActiveFixture(),
);
List<Override> _speedBuilderOverrides() => [...preferenceOverrides()];

class _NoopPracticeFeedback implements PracticeFeedbackOutput {
  const _NoopPracticeFeedback();
  @override
  void haptic() {}
  @override
  void countInClick(int beatIndex) {}
  @override
  void announce(String message) {}
  @override
  void openPermissionSettings() {}
}

AppConfig _practiceSessionConfig() => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: const FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Widget _practiceSessionScreen() => const PracticeSessionScreen();
List<Override> _practiceSessionOverrides() {
  final host = FakeSessionHost()..liveScore = 640;
  host.emitState(
    practiceSessionStateFor(
      PracticeSessionStatus.running,
      definition: practiceSessionFixtureDefinition(
        id: 'fixture.golden.session',
      ),
      config: practiceSessionFixtureConfig(
        definitionId: 'fixture.golden.session',
      ),
      attemptIndex: 1,
      activeElapsed: const Duration(seconds: 37),
    ),
  );
  addTearDown(host.close);
  return [
    ...preferenceOverrides(),
    appConfigProvider.overrideWithValue(_practiceSessionConfig()),
    appLifecycleEventsProvider.overrideWithValue(FakeLifecycleEvents()),
    practiceSessionHostProvider.overrideWithValue(host),
    practiceFeedbackOutputProvider.overrideWithValue(
      const _NoopPracticeFeedback(),
    ),
  ];
}

final class _SingleDefRepository implements PracticeCatalogRepository {
  const _SingleDefRepository(this.definition);
  final PracticeDefinition definition;

  @override
  List<PracticeDefinition> all() =>
      List<PracticeDefinition>.unmodifiable([definition]);
  @override
  PracticeDefinition? byId(String id) =>
      id == definition.id ? definition : null;
  @override
  List<PracticeDefinition> byMode(PracticeMode mode) => definition.mode == mode
      ? List<PracticeDefinition>.unmodifiable([definition])
      : const <PracticeDefinition>[];
  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      const <PracticeDefinition>[];
}

final _practiceSetupDefinition = practiceSessionFixtureDefinition(
  id: 'fixture.golden.setup',
);

Widget _practiceSetupScreen() => PracticeSetupScreen(
  argsOverride: PracticeSetupArgs(
    request: PracticeSetupRequest.hasId,
    definitionId: _practiceSetupDefinition.id,
  ),
);
List<Override> _practiceSetupOverrides() => [
  ...preferenceOverrides(),
  appConfigProvider.overrideWithValue(_practiceSessionConfig()),
  appLifecycleEventsProvider.overrideWithValue(FakeLifecycleEvents()),
  practiceCatalogRepositoryProvider.overrideWithValue(
    _SingleDefRepository(_practiceSetupDefinition),
  ),
];

Widget _practiceAreaHubScreen() => const PracticeAreaHubScreen();
List<Override> _practiceAreaHubOverrides() => [...preferenceOverrides()];

Widget _profileHubScreen() => const ProfileHubScreen();
List<Override> _profileHubOverrides() => [...preferenceOverrides()];

// ── progress_v2 (test/ui/goldens/e13_r31_screens_golden_test.dart, §0.0.A/R5)

String _progressCamel(String snakeCase) {
  final parts = snakeCase.split('_');
  return parts.first +
      parts
          .skip(1)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join();
}

MasteryMilestone _progressMilestone(String id) => MasteryMilestone(
  id: id,
  catalogVersion: 2,
  skill: MasterySkill.chordTransition,
  metric: MasteryMetric.accuracy,
  minimumThreshold: 0.8,
  difficulty: MasteryDifficulty.beginner,
  tempoRange: MasteryTempoRange(minBpm: 60, maxBpm: 100),
  minEvidenceSessions: 5,
  titleKey: '${_progressCamel(id)}Title',
  descriptionKey: '${_progressCamel(id)}Description',
);

ProgressOverviewProjection _progressDashboardProjection() {
  final measured = _progressMilestone('chord_transition_beginner');
  final unmeasured = _progressMilestone('rhythm_accuracy_beginner');
  return ProgressOverviewProjection(
    isOffline: true,
    milestones: [
      MilestoneOverviewEntry(
        milestone: measured,
        progress: MasteryProgress(
          milestoneId: measured.id,
          catalogVersion: 2,
          evidenceSessionCount: 4,
        ),
        title: 'Chord transitions — beginner',
      ),
      MilestoneOverviewEntry(
        milestone: unmeasured,
        progress: MasteryProgress.fresh(
          milestoneId: unmeasured.id,
          catalogVersion: 1,
        ),
        title: 'Rhythm accuracy — beginner',
      ),
    ],
    trend: ProgressTrend(
      points: [
        for (var i = 0; i < 6; i++)
          ProgressTrendPoint(
            observedAt: DateTime.utc(2026, 8, 1 + i),
            value: 0.5 + i * 0.03,
          ),
      ],
    ),
    metricSegments: [
      MetricVersionSegment(
        catalogVersion: 1,
        points: [
          ProgressTrendPoint(observedAt: DateTime.utc(2026, 6, 1), value: 0.3),
        ],
      ),
      MetricVersionSegment(
        catalogVersion: 2,
        points: [
          ProgressTrendPoint(observedAt: DateTime.utc(2026, 8, 6), value: 0.68),
        ],
      ),
    ],
  );
}

SkillDetailProjection _skillDetailProjectionFixture() {
  final milestone = _progressMilestone('chord_transition_beginner');
  return SkillDetailProjection(
    milestone: milestone,
    progress: MasteryProgress(
      milestoneId: milestone.id,
      catalogVersion: 2,
      evidenceSessionCount: 4,
    ),
    title: 'Chord transitions — beginner',
    description:
        'Smoothly changing between open chords at a steady beginner tempo.',
    evidence: [
      SkillEvidenceReference(
        sessionId: 'session-101',
        origin: MasteryEvidenceOrigin.vision,
        observedAt: DateTime.utc(2026, 8, 20),
      ),
      SkillEvidenceReference(
        sessionId: 'session-102',
        origin: MasteryEvidenceOrigin.analysis,
        observedAt: DateTime.utc(2026, 8, 22),
      ),
    ],
    achievedMilestoneIds: const {},
    recommendation: const SkillRecommendation(
      milestoneId: 'strum_consistency_intermediate',
      title: 'Strum consistency — intermediate',
      message: 'Ready for a faster tempo drill.',
      prerequisiteMilestoneId: 'chord_transition_beginner',
      prerequisiteTitle: 'Chord transitions — beginner',
    ),
  );
}

Widget _progressDashboardScreen() => ProgressDashboardScreen(
  projection: _progressDashboardProjection(),
  onOpenSkillDetail: (_) {},
  onGetStarted: () {},
);
List<Override> _progressDashboardOverrides() => [...preferenceOverrides()];

Widget _skillDetailScreen() => SkillDetailScreen(
  projection: _skillDetailProjectionFixture(),
  onOpenEvidence: (_, _) {},
  onStartRecommendedPractice: () {},
);
List<Override> _skillDetailOverrides() => [...preferenceOverrides()];

// ── song_trainer (test/ui/goldens/e13_r23/24/25_screens_golden_test.dart) ──

final class _NoopAssetRepository implements SongAssetRepository {
  const _NoopAssetRepository();

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(SongAssetWriteRequest request) =>
      throw UnimplementedError();
  @override
  Future<AppResult<Uint8List?>> get(String sha256) async =>
      const AppResult<Uint8List?>.success(null);
  @override
  Future<AppResult<SongAssetSummary?>> summary(String sha256) async =>
      const AppResult<SongAssetSummary?>.success(null);
  @override
  Future<AppResult<void>> incrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);
  @override
  Future<AppResult<void>> decrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);
  @override
  Future<AppResult<void>> permanentlyDelete(String sha256) async =>
      const AppResult<void>.success(null);
}

SongDocument _songEditorDocument() {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('golden-editor'),
    revision: 0,
    metadata: SongMetadata(title: 'Golden Editor Song', artist: 'Fixtures'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'golden-editor.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('verse'),
        name: 'Verse',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
      SongSection(
        id: SongSectionId('chorus'),
        name: 'Chorus',
        startMeasure: 1,
        endMeasureExclusive: 2,
      ),
    ],
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
    tracks: <SongTrack>[
      ChordTrack(
        id: SongTrackId('chords'),
        name: 'Chords',
        instrument: SongInstrument(name: 'Guitar'),
        events: const <SongChordEvent>[],
      ),
    ],
  );
}

Widget _songEditorScreen() => const SongEditorScreen(songId: 'golden-editor');
List<Override> _songEditorOverrides() => [
  ...preferenceOverrides(),
  songRepositoryProvider.overrideWithValue(
    InMemorySongRepository()..create(_songEditorDocument()),
  ),
  songAssetRepositoryProvider.overrideWithValue(const _NoopAssetRepository()),
];

Widget _songImportPreviewScreen() => SongImportPreviewScreen(
  preview: ImportPreview(
    displayName: 'golden-song.musicxml',
    byteLength: 4096,
    format: 'MusicXML',
    warnings: const <String>['songImport.musicXml.timingQuantized'],
    parts: const <ImportPartPreview>[
      ImportPartPreview(
        id: 'part-1',
        name: 'Guitar',
        staffCount: 1,
        noteCount: 42,
        isPolyphonic: false,
        chordSymbolCount: 8,
        hasTablature: false,
      ),
    ],
  ),
);
List<Override> _songImportPreviewOverrides() => [...preferenceOverrides()];

final class _NoopFilePicker implements FilePickerAdapter {
  const _NoopFilePicker();

  @override
  Future<void> dispose() async {}
  @override
  Future<ImportSourceFile?> pickSongFile() async => null;
}

Widget _songImportScreen() => const SongImportScreen();
List<Override> _songImportOverrides() {
  final controller = SongImportController(
    registry: const ImporterRegistry(importers: <SongImporter>[]),
    repository: InMemorySongRepository(),
    workspaceRoot: () async => throw StateError('workspace is not used'),
  );
  addTearDown(controller.dispose);
  return [
    ...preferenceOverrides(),
    songImportControllerProvider.overrideWithValue(controller),
    songFilePickerAdapterProvider.overrideWithValue(const _NoopFilePicker()),
    songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
  ];
}

final class _LibrarySummaryRepository implements SongRepository {
  const _LibrarySummaryRepository();

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) async =>
      AppResult<List<SongSummary>>.success(<SongSummary>[
        SongSummary(
          documentId: SongId('golden-editable'),
          title: 'Editable Native Song',
          artist: 'StrumSight Fixtures',
          tags: const <String>[],
          updatedAt: DateTime.utc(2026, 8, 5),
          lastPracticedAt: DateTime.utc(2026, 8, 5),
          capability: SongCapabilitySummary(
            canPersist: true,
            canTrain: true,
            canExport: true,
            chordScoring: true,
            pitchScoring: false,
            lastValidatedAt: DateTime.utc(2026, 8, 5),
          ),
          sourceType: SongSourceType.strumSightJson,
          favorite: true,
          archived: false,
          revision: 1,
          documentHash: '1' * 64,
          trashed: false,
        ),
        SongSummary(
          documentId: SongId('golden-readonly'),
          title: 'Read-Only Legacy Song',
          artist: null,
          tags: const <String>[],
          updatedAt: DateTime.utc(2026, 8, 3),
          lastPracticedAt: DateTime.utc(2026, 8, 3),
          capability: SongCapabilitySummary(
            canPersist: false,
            canTrain: true,
            canExport: false,
            chordScoring: true,
            pitchScoring: false,
            lastValidatedAt: DateTime.utc(2026, 8, 3),
          ),
          sourceType: SongSourceType.legacyLocal,
          favorite: false,
          archived: false,
          revision: 0,
          documentHash: '2' * 64,
          trashed: false,
        ),
      ]);

  @override
  Future<AppResult<void>> create(SongDocument document) =>
      throw UnimplementedError();
  @override
  Future<AppResult<SongDocument?>> get(SongId id) => throw UnimplementedError();
  @override
  Future<AppResult<void>> moveToTrash(SongId id) => throw UnimplementedError();
  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      throw UnimplementedError();
  @override
  Future<AppResult<void>> restore(SongId id) => throw UnimplementedError();
  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => throw UnimplementedError();
}

Widget _songLibraryScreen() => const SongLibraryScreen();
List<Override> _songLibraryOverrides() => [
  ...preferenceOverrides(),
  songRepositoryProvider.overrideWithValue(const _LibrarySummaryRepository()),
];

SongDocument _songOverviewDocument() {
  final now = DateTime.utc(2026, 8, 4);
  final backingAssetId = SongAssetId('backing');
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('golden-overview'),
    revision: 0,
    metadata: SongMetadata(
      title: 'Golden Overview Song',
      copyright: '© 2026 StrumSight Test Fixtures',
    ),
    source: SongSource(
      type: SongSourceType.musicXml,
      originalFileName: 'golden.musicxml',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('verse'),
        name: 'Verse',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
    ],
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
    tracks: <SongTrack>[
      ChordTrack(
        id: SongTrackId('chords'),
        name: 'Chords',
        instrument: SongInstrument(name: 'Guitar'),
        events: const [],
      ),
      BackingAudioTrack(
        id: SongTrackId('backing'),
        name: 'Backing',
        instrument: SongInstrument(name: 'Backing track'),
        assetId: backingAssetId,
        gridOffset: Duration.zero,
      ),
    ],
  );
}

final class _OverviewDocumentRepository implements SongRepository {
  _OverviewDocumentRepository(this._document);
  final SongDocument _document;

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) =>
      throw UnimplementedError();
  @override
  Future<AppResult<void>> create(SongDocument document) =>
      throw UnimplementedError();
  @override
  Future<AppResult<SongDocument?>> get(SongId id) async =>
      AppResult<SongDocument?>.success(_document);
  @override
  Future<AppResult<void>> moveToTrash(SongId id) => throw UnimplementedError();
  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      throw UnimplementedError();
  @override
  Future<AppResult<void>> restore(SongId id) => throw UnimplementedError();
  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => throw UnimplementedError();
}

final _songOverviewDoc = _songOverviewDocument();

Widget _songOverviewScreen() =>
    SongOverviewScreen(songId: _songOverviewDoc.id.value);
List<Override> _songOverviewOverrides() => [
  ...preferenceOverrides(),
  songRepositoryProvider.overrideWithValue(
    _OverviewDocumentRepository(_songOverviewDoc),
  ),
];

SongTrainerResult _songResultFixture() {
  final measureResults = <SongMeasureTrainerResult>[
    for (var index = 0; index < 4; index++)
      SongMeasureTrainerResult(
        measureIndex: index,
        verdicts: const <SongTrainerVerdict>[],
        averageEventScore: 0.85 - (index * 0.1),
      ),
  ];
  return SongTrainerResult(
    sessionResult: PracticeSessionResult(
      id: 'golden-result',
      activeDuration: const Duration(seconds: 30),
      pausedDuration: Duration.zero,
      attempts: const <PracticeAttemptResult>[],
      finishReason: PracticeFinishReason.completedAllTargets,
      highestStableTempo: null,
      coachingSummary: const <String>[],
    ),
    verdicts: const <SongTrainerVerdict>[],
    measureResults: measureResults,
    sectionResults: const <SongSectionTrainerResult>[],
  );
}

Widget _songResultScreen() => SongResultScreen(result: _songResultFixture());
List<Override> _songResultOverrides() => [...preferenceOverrides()];

Widget _songTrainerScreen() => SongTrainerScreen(
  state: const SongTrainerState.initial().copyWith(
    status: SongTrainerStatus.running,
    backingRateSupported: true,
    loopIndex: 2,
    maxLoops: 5,
  ),
);
List<Override> _songTrainerOverrides() => [...preferenceOverrides()];

SongDocument _trainerSetupDocument() {
  final now = DateTime.utc(2026, 8, 26);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('golden-setup'),
    revision: 0,
    metadata: SongMetadata(title: 'Golden Setup Song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'golden-setup.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
    tracks: <SongTrack>[
      ChordTrack(
        id: SongTrackId('chords'),
        name: 'Chords',
        instrument: SongInstrument(name: 'Guitar'),
        events: const [],
      ),
    ],
  );
}

final _trainerSetupDoc = _trainerSetupDocument();

Widget _trainerSetupScreen() =>
    TrainerSetupScreen(songId: _trainerSetupDoc.id.value);
List<Override> _trainerSetupOverrides() {
  final repository = InMemorySongRepository();
  repository.create(_trainerSetupDoc);
  return [
    ...preferenceOverrides(),
    songRepositoryProvider.overrideWithValue(repository),
  ];
}

// ── vision (test/ui/goldens/e13_r30_screens_golden_test.dart) ──────────────

Widget _visionResultScreen() => VisionResultScreen(
  result: VisionSessionResult(
    session: VisionSession(
      id: VisionSessionId.create('variant-matrix-session'),
      startedAt: DateTime.utc(2026, 8, 27, 12),
    ),
    endedAt: DateTime.utc(2026, 8, 27, 12, 8),
    endReason: VisionSessionEndReason.explicitStop,
    qualitySummary: VisionQualitySummary.fromFrames(const []),
    calibrationState: CalibrationLossState.tracking,
    sessionSummary: <VisionInsight>[
      VisionInsight(
        code: InsightCode.frettingStable,
        policyVersion: 'e05-r23-v1',
        evidenceIds: const <String>['evidence-1'],
        confidence: 0.9,
      ),
      VisionInsight(
        code: InsightCode.postureFocus,
        policyVersion: 'e05-r23-v1',
        evidenceIds: const <String>['evidence-2'],
        confidence: 0.3,
      ),
    ],
    observedFrameCount: 480,
  ),
  onStartCorrectivePractice: () {},
);
List<Override> _visionResultOverrides() => [...preferenceOverrides()];

final class _SeededVisionSessionController extends VisionSessionController {
  @override
  VisionSessionState build() => VisionSessionState.idle().copyWith(
    status: VisionSessionStatus.running,
    qualitySummary: VisionQualitySummary.fromFrames(const []),
    overlayQuality: const VisionOverlayQuality(
      hand: VisionMetricState.good,
      pose: VisionMetricState.needsImprovement,
      guitar: CalibrationLossState.tracking,
    ),
    calibrationState: CalibrationLossState.tracking,
    realtimeCue: VisionInsight(
      code: InsightCode.pickingFocus,
      policyVersion: 'e05-r23-v1',
      evidenceIds: const <String>['evidence-1'],
      confidence: 0.9,
    ),
  );
}

Widget _visionSessionScreen() => const VisionSessionScreen();
List<Override> _visionSessionOverrides() => [
  ...preferenceOverrides(),
  visionSessionControllerProvider.overrideWith(
    _SeededVisionSessionController.new,
  ),
  cameraSessionCoordinatorProvider.overrideWithValue(
    CameraSessionCoordinator(),
  ),
];

final class _DeniedCameraPermissionGateway implements CameraPermissionGateway {
  @override
  Future<CameraPermissionState> currentState() async =>
      CameraPermissionState.denied;
  @override
  Future<CameraPermissionState> request() async => CameraPermissionState.denied;
}

Widget _visionSetupScreen() => const VisionSetupScreen();
List<Override> _visionSetupOverrides() => [
  ...preferenceOverrides(),
  cameraPermissionGatewayProvider.overrideWithValue(
    _DeniedCameraPermissionGateway(),
  ),
  cameraSessionCoordinatorProvider.overrideWithValue(
    CameraSessionCoordinator(),
  ),
];

// ---------------------------------------------------------------------------
// A-level registry (46 already-golden-fixtured screens + the two R5 screens,
// §0.0.A/R3). The B-level 25 are added in a later commit (§8 step 3).
// ---------------------------------------------------------------------------

final _screens = <String, _ScreenFixture>{
  'tutor_chat': _ScreenFixture(
    screenPath:
        'lib/features/ai_tutor/presentation/screens/tutor_chat_screen.dart',
    build: _tutorChatScreen,
    overridesBuilder: _tutorChatOverrides,
  ),
  'tutor_home': _ScreenFixture(
    screenPath:
        'lib/features/ai_tutor/presentation/screens/tutor_home_screen.dart',
    build: _tutorHomeScreen,
    overridesBuilder: _tutorHomeOverrides,
  ),
  'analysis_compare': _ScreenFixture(
    screenPath:
        'lib/features/audio_analysis/presentation/analysis_compare_screen.dart',
    build: _analysisCompareScreen,
    overridesBuilder: _analysisCompareOverrides,
  ),
  'analysis_metric_detail': _ScreenFixture(
    screenPath:
        'lib/features/audio_analysis/presentation/analysis_metric_detail_screen.dart',
    build: _analysisMetricDetailScreen,
    overridesBuilder: _analysisMetricDetailOverrides,
  ),
  'analysis_overview': _ScreenFixture(
    screenPath:
        'lib/features/audio_analysis/presentation/analysis_overview_screen.dart',
    build: _analysisOverviewScreen,
    overridesBuilder: _analysisOverviewOverrides,
  ),
  'analysis_timeline': _ScreenFixture(
    screenPath:
        'lib/features/audio_analysis/presentation/analysis_timeline_screen.dart',
    build: _analysisTimelineScreen,
    overridesBuilder: _analysisTimelineOverrides,
  ),
  'login': _ScreenFixture(
    screenPath: 'lib/features/auth/screens/login_screen.dart',
    build: _loginScreen,
    overridesBuilder: _loginOverrides,
  ),
  'chord_library': _ScreenFixture(
    screenPath: 'lib/features/chords/screens/chord_library_screen.dart',
    build: _chordLibraryScreen,
    overridesBuilder: _chordLibraryOverrides,
  ),
  'club_member_management': _ScreenFixture(
    screenPath:
        'lib/features/community/presentation/screens/clubs/club_member_management_screen.dart',
    build: _clubMemberManagementScreen,
    overridesBuilder: _clubMemberManagementOverrides,
  ),
  'edit_profile': _ScreenFixture(
    screenPath:
        'lib/features/community/presentation/screens/edit_profile_screen.dart',
    build: _editProfileScreen,
    overridesBuilder: _editProfileOverrides,
  ),
  'achievements': _ScreenFixture(
    screenPath:
        'lib/features/gamification/presentation/screens/achievements_screen.dart',
    build: _achievementsScreen,
    overridesBuilder: _achievementsOverrides,
  ),
  'gamification_hub': _ScreenFixture(
    screenPath:
        'lib/features/gamification/presentation/screens/gamification_hub_screen.dart',
    build: _gamificationHubScreen,
    overridesBuilder: _gamificationHubOverrides,
  ),
  'quests': _ScreenFixture(
    screenPath:
        'lib/features/gamification/presentation/screens/quests_screen.dart',
    build: _questsScreen,
    overridesBuilder: _questsOverrides,
  ),
  'reward_inbox': _ScreenFixture(
    screenPath:
        'lib/features/gamification/presentation/screens/reward_inbox_screen.dart',
    build: _rewardInboxScreen,
    overridesBuilder: _rewardInboxOverrides,
  ),
  'streak_detail': _ScreenFixture(
    screenPath:
        'lib/features/gamification/presentation/screens/streak_detail_screen.dart',
    build: _streakDetailScreen,
    overridesBuilder: _streakDetailOverrides,
  ),
  'lesson_list': _ScreenFixture(
    screenPath: 'lib/features/learn/screens/lesson_list_screen.dart',
    build: _lessonListScreen,
    overridesBuilder: _lessonListOverrides,
  ),
  'library_item_detail': _ScreenFixture(
    screenPath:
        'lib/features/library_v2/screens/library_item_detail_screen.dart',
    build: _libraryItemDetailScreen,
    overridesBuilder: _libraryItemDetailOverrides,
  ),
  'unified_library': _ScreenFixture(
    screenPath: 'lib/features/library_v2/screens/unified_library_screen.dart',
    build: _unifiedLibraryScreen,
    overridesBuilder: _unifiedLibraryOverrides,
  ),
  'live': _ScreenFixture(
    screenPath: 'lib/features/live/screens/live_screen.dart',
    build: _liveScreen,
    overridesBuilder: _liveOverrides,
  ),
  'metronome': _ScreenFixture(
    screenPath: 'lib/features/metronome/screens/metronome_screen.dart',
    build: _metronomeScreen,
    overridesBuilder: _metronomeOverrides,
  ),
  'model_manager': _ScreenFixture(
    screenPath: 'lib/features/offline_ai/screens/model_manager_screen.dart',
    build: _modelManagerScreen,
    overridesBuilder: _modelManagerOverrides,
  ),
  'onboarding': _ScreenFixture(
    screenPath: 'lib/features/onboarding/screens/onboarding_screen.dart',
    build: _onboardingScreen,
    overridesBuilder: _onboardingOverrides,
  ),
  'permission_primer': _ScreenFixture(
    screenPath: 'lib/features/onboarding/screens/permission_primer_screen.dart',
    build: _permissionPrimerScreen,
    overridesBuilder: _permissionPrimerOverrides,
  ),
  'practice_history': _ScreenFixture(
    screenPath:
        'lib/features/practice/presentation/screens/practice_history_screen.dart',
    build: _practiceHistoryScreen,
    overridesBuilder: _practiceHistoryOverrides,
  ),
  'practice_result': _ScreenFixture(
    screenPath:
        'lib/features/practice/presentation/screens/practice_result_screen.dart',
    build: _practiceResultScreen,
    overridesBuilder: _practiceResultOverrides,
  ),
  'practice_session': _ScreenFixture(
    screenPath:
        'lib/features/practice/presentation/screens/practice_session_screen.dart',
    build: _practiceSessionScreen,
    overridesBuilder: _practiceSessionOverrides,
  ),
  'practice_setup': _ScreenFixture(
    screenPath:
        'lib/features/practice/presentation/screens/practice_setup_screen.dart',
    build: _practiceSetupScreen,
    overridesBuilder: _practiceSetupOverrides,
  ),
  'speed_builder': _ScreenFixture(
    screenPath:
        'lib/features/practice/presentation/screens/speed_builder_screen.dart',
    build: _speedBuilderScreen,
    overridesBuilder: _speedBuilderOverrides,
  ),
  'practice_area_hub': _ScreenFixture(
    screenPath:
        'lib/features/practice_hub/screens/practice_area_hub_screen.dart',
    build: _practiceAreaHubScreen,
    overridesBuilder: _practiceAreaHubOverrides,
  ),
  'profile_hub': _ScreenFixture(
    screenPath: 'lib/features/profile_hub/screens/profile_hub_screen.dart',
    build: _profileHubScreen,
    overridesBuilder: _profileHubOverrides,
  ),
  'privacy_center': _ScreenFixture(
    screenPath: 'lib/features/settings/screens/privacy_center_screen.dart',
    build: _privacyCenterScreen,
    overridesBuilder: _privacyCenterOverrides,
  ),
  'settings': _ScreenFixture(
    screenPath: 'lib/features/settings/screens/settings_screen.dart',
    build: _settingsScreen,
    overridesBuilder: _settingsOverrides,
  ),
  'share_preview': _ScreenFixture(
    screenPath: 'lib/features/share/screens/share_preview_screen.dart',
    build: _sharePreviewScreen,
    overridesBuilder: _sharePreviewOverrides,
  ),
  'song_editor': _ScreenFixture(
    screenPath:
        'lib/features/song_trainer/presentation/screens/song_editor_screen.dart',
    build: _songEditorScreen,
    overridesBuilder: _songEditorOverrides,
  ),
  'song_import_preview': _ScreenFixture(
    screenPath:
        'lib/features/song_trainer/presentation/screens/song_import_preview_screen.dart',
    build: _songImportPreviewScreen,
    overridesBuilder: _songImportPreviewOverrides,
  ),
  'song_import': _ScreenFixture(
    screenPath:
        'lib/features/song_trainer/presentation/screens/song_import_screen.dart',
    build: _songImportScreen,
    overridesBuilder: _songImportOverrides,
  ),
  'song_library': _ScreenFixture(
    screenPath:
        'lib/features/song_trainer/presentation/screens/song_library_screen.dart',
    build: _songLibraryScreen,
    overridesBuilder: _songLibraryOverrides,
  ),
  'song_overview': _ScreenFixture(
    screenPath:
        'lib/features/song_trainer/presentation/screens/song_overview_screen.dart',
    build: _songOverviewScreen,
    overridesBuilder: _songOverviewOverrides,
  ),
  'song_result': _ScreenFixture(
    screenPath:
        'lib/features/song_trainer/presentation/screens/song_result_screen.dart',
    build: _songResultScreen,
    overridesBuilder: _songResultOverrides,
  ),
  'song_trainer': _ScreenFixture(
    screenPath:
        'lib/features/song_trainer/presentation/screens/song_trainer_screen.dart',
    build: _songTrainerScreen,
    overridesBuilder: _songTrainerOverrides,
  ),
  'trainer_setup': _ScreenFixture(
    screenPath:
        'lib/features/song_trainer/presentation/screens/trainer_setup_screen.dart',
    build: _trainerSetupScreen,
    overridesBuilder: _trainerSetupOverrides,
  ),
  'today_hub': _ScreenFixture(
    screenPath: 'lib/features/today/screens/today_hub_screen.dart',
    build: _todayHubScreen,
    overridesBuilder: _todayHubOverrides,
  ),
  'tuner': _ScreenFixture(
    screenPath: 'lib/features/tuner/screens/tuner_screen.dart',
    build: _tunerScreen,
    overridesBuilder: _tunerOverrides,
  ),
  'vision_result': _ScreenFixture(
    screenPath:
        'lib/features/vision/presentation/screens/vision_result_screen.dart',
    build: _visionResultScreen,
    overridesBuilder: _visionResultOverrides,
  ),
  'vision_session': _ScreenFixture(
    screenPath:
        'lib/features/vision/presentation/screens/vision_session_screen.dart',
    build: _visionSessionScreen,
    overridesBuilder: _visionSessionOverrides,
  ),
  'vision_setup': _ScreenFixture(
    screenPath:
        'lib/features/vision/presentation/screens/vision_setup_screen.dart',
    build: _visionSetupScreen,
    overridesBuilder: _visionSetupOverrides,
  ),
  'progress_dashboard': _ScreenFixture(
    screenPath:
        'lib/features/progress_v2/screens/progress_dashboard_screen.dart',
    build: _progressDashboardScreen,
    overridesBuilder: _progressDashboardOverrides,
  ),
  'skill_detail': _ScreenFixture(
    screenPath: 'lib/features/progress_v2/screens/skill_detail_screen.dart',
    build: _skillDetailScreen,
    overridesBuilder: _skillDetailOverrides,
  ),
};

// ---------------------------------------------------------------------------
// Exclusion list (§0.0.A/R3) — the A1 completeness cell requires every
// MEASURED reachable screen to be either in `_screens` above or here, and
// every entry here to carry a real reason and a named follow-up round. This
// list may only shrink (never silently grow, L180). At this (A-level) commit
// it holds the 25 screens scheduled for the B-level commit (§8 step 3,
// reason: fixture-in-progress-this-round) plus the one screen with NO merged
// fixture anywhere in the tree at all — `WrappedPreviewScreen` — which is the
// ONLY entry allowed to carry that specific reason (§0.0.A/R3).
// ---------------------------------------------------------------------------

final class _ExclusionEntry {
  const _ExclusionEntry({
    required this.screenPath,
    required this.reason,
    required this.followUpRound,
  });

  final String screenPath;
  final String reason;
  final String followUpRound;
}

const _bLevelReason =
    'B-level fixture (fixture found in test/features/**, not yet in this '
    'file) — scheduled for this same round\'s own B-level commit, §8 step 3.';

const _exclusions = <_ExclusionEntry>[
  _ExclusionEntry(
    screenPath:
        'lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath:
        'lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath:
        'lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/analyze/screens/analyze_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath:
        'lib/features/audio_analysis/presentation/analysis_export_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath:
        'lib/features/gamification/presentation/screens/achievement_detail_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath:
        'lib/features/gamification/presentation/screens/level_detail_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/learn/screens/latency_calibration_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/learn/screens/learn_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/learn/screens/lesson_score_preview_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/library/screens/library_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/library/screens/session_detail_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath:
        'lib/features/practice/presentation/screens/practice_hub_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath:
        'lib/features/practice_generator/presentation/screens/plan_setup_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath:
        'lib/features/practice_generator/presentation/screens/today_plan_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/progress/screens/progress_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/settings/screens/vision_privacy_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/share/screens/strum_reel_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/share/screens/wrapped_preview_screen.dart',
    reason:
        'No merged pump fixture anywhere in the tree (measured, §0.0.A/R3) — '
        'neither test/ui/goldens/** nor test/features/** constructs this '
        'screen. Building one is new test-authoring scope beyond this '
        'measurement-only round.',
    followUpRound:
        'a future round whose allowed_paths covers a '
        'WrappedPreviewScreen pump fixture (SDD, unscheduled)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/songs/screens/setlist_detail_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/songs/screens/setlist_list_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/songs/screens/song_builder_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/songs/screens/song_list_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath: 'lib/features/streak/screens/streak_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
  _ExclusionEntry(
    screenPath:
        'lib/features/vision/presentation/screens/guitar_calibration_screen.dart',
    reason: _bLevelReason,
    followUpRound: 'E15-R13 (this round, B-level commit)',
  ),
];

// ---------------------------------------------------------------------------
// Pump + capture (adapted from e13_r36_variant_matrix_test.dart; bounded pump
// instead of pumpAndSettle — see the file header comment).
// ---------------------------------------------------------------------------

final _overflowPattern = RegExp(r'overflowed by ([\d.]+) pixels');

class _CellResult {
  _CellResult({required this.overflowPx, required this.otherErrors});

  final double? overflowPx;
  final List<String> otherErrors;
}

Future<_CellResult> _pumpCell(
  WidgetTester tester, {
  required Widget Function() build,
  required List<Override> Function() overridesBuilder,
  required bool dark,
  required Locale locale,
  required _ViewportProfile viewport,
  required double textScale,
}) async {
  tester.view.physicalSize = _viewportSizes[viewport]!;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final captured = <FlutterErrorDetails>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = captured.add;

  try {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesBuilder(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? SsDarkTheme.data() : SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: build(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
  } finally {
    FlutterError.onError = previousOnError;
  }

  double? overflowPx;
  final otherErrors = <String>[];
  for (final details in captured) {
    final message = details.exception.toString();
    final match = _overflowPattern.firstMatch(message);
    if (match != null) {
      final px = double.parse(match.group(1)!);
      overflowPx = overflowPx == null ? px : (overflowPx + px);
    } else {
      otherErrors.add(message);
    }
  }
  return _CellResult(overflowPx: overflowPx, otherErrors: otherErrors);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group(
    'A1 — completeness: measured reachable set ⊆ matrix ∪ exclusion list',
    () {
      test('every reachable screen is either pumped here or excluded with a '
          'reason and a named follow-up round', () {
        final measured = ScreenReachability(Directory.current).render();
        final reachablePaths = measured.verdicts
            .where((v) => v.isReachable)
            .map((v) => v.screenPath)
            .toSet();
        final matrixPaths = _screens.values.map((f) => f.screenPath).toSet();
        final excludedPaths = _exclusions.map((e) => e.screenPath).toSet();
        final covered = matrixPaths.union(excludedPaths);
        final uncovered = reachablePaths.difference(covered);

        expect(
          uncovered,
          isEmpty,
          reason:
              'reachable screens missing from BOTH the matrix and the '
              'exclusion list (brief §0.0.A/R3): $uncovered',
        );
      });

      test('every exclusion entry carries a non-trivial reason and a named '
          'follow-up round', () {
        for (final entry in _exclusions) {
          expect(
            entry.reason.trim().length,
            greaterThan(10),
            reason: '${entry.screenPath} has a trivial/empty exclusion reason',
          );
          expect(
            entry.followUpRound.trim(),
            isNotEmpty,
            reason: '${entry.screenPath} has no named follow-up round',
          );
        }
      });

      test('the "no merged fixture" reason is used ONLY for '
          'WrappedPreviewScreen (measured, §0.0.A/R3)', () {
        final noFixtureEntries = _exclusions.where(
          (e) => e.reason.contains('No merged pump fixture'),
        );
        expect(noFixtureEntries.map((e) => e.screenPath), <String>[
          'lib/features/share/screens/wrapped_preview_screen.dart',
        ]);
      });

      test('the exclusion list has no duplicate screen paths', () {
        final paths = _exclusions.map((e) => e.screenPath).toList();
        expect(paths.toSet(), hasLength(paths.length));
      });

      test('no screen appears in both the matrix and the exclusion list', () {
        final matrixPaths = _screens.values.map((f) => f.screenPath).toSet();
        final excludedPaths = _exclusions.map((e) => e.screenPath).toSet();
        expect(matrixPaths.intersection(excludedPaths), isEmpty);
      });
    },
  );

  for (final screenEntry in _screens.entries) {
    final screenName = screenEntry.key;
    final fixture = screenEntry.value;

    for (final dark in [false, true]) {
      final themeName = dark ? 'dark' : 'light';

      for (final localeCode in ['en', 'hu']) {
        for (final viewport in _ViewportProfile.values) {
          for (final textScale in [1.0, 2.0]) {
            final cellKey =
                '$screenName|$themeName|$localeCode|'
                '${_viewportNames[viewport]}|$textScale';

            testWidgets(cellKey, (tester) async {
              final result = await _pumpCell(
                tester,
                build: fixture.build,
                overridesBuilder: fixture.overridesBuilder,
                dark: dark,
                locale: Locale(localeCode),
                viewport: viewport,
                textScale: textScale,
              );

              expect(
                result.otherErrors,
                isEmpty,
                reason:
                    'no exception may occur while pumping this cell (brief '
                    '§3); got: ${result.otherErrors}',
              );
              expect(
                result.overflowPx,
                isNull,
                reason:
                    'unexpected RenderFlex overflow of ${result.overflowPx}px '
                    '— a real lib/** regression this closing round measures '
                    'but does not fix (brief §5.2)',
              );
            });
          }
        }
      }
    }
  }
}
