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
import 'dart:convert';
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
import 'package:strumsight/l10n/app_localizations_en.dart';

// ── B-level-only imports (§8 step 3) ────────────────────────────────────

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_conversation.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_memory_fact.dart';
import 'package:strumsight/features/ai_tutor/domain/repositories/tutor_conversation_repository.dart';
import 'package:strumsight/features/ai_tutor/domain/repositories/tutor_memory_repository.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_data_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_profile_screen.dart';
import 'package:strumsight/features/analyze/providers/analyze_providers.dart';
import 'package:strumsight/features/analyze/screens/analyze_screen.dart';
import 'package:strumsight/features/audio_analysis/application/export_analysis_use_case.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_export_screen.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/screens/latency_calibration_screen.dart';
import 'package:strumsight/features/learn/screens/learn_screen.dart';
import 'package:strumsight/features/learn/screens/lesson_score_preview_screen.dart';
import 'package:strumsight/features/library/model/analyzed_session.dart';
import 'package:strumsight/features/library/screens/library_screen.dart';
import 'package:strumsight/features/library/screens/session_detail_screen.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart'
    as practice_beat_position;
import 'package:strumsight/features/practice/domain/model/meter.dart'
    as practice_meter;
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/practice_generator/data/local/generation_draft_repository.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart'
    as progress_entry;
import 'package:strumsight/features/progress/providers/practice_log_provider.dart';
import 'package:strumsight/features/progress/screens/progress_screen.dart';
import 'package:strumsight/features/settings/screens/vision_privacy_screen.dart';
import 'package:strumsight/features/share/screens/strum_reel_screen.dart';
import 'package:strumsight/features/songs/model/setlist.dart';
import 'package:strumsight/features/songs/model/song.dart';
import 'package:strumsight/features/songs/providers/setlists_provider.dart';
import 'package:strumsight/features/songs/providers/songs_provider.dart';
import 'package:strumsight/features/songs/screens/setlist_detail_screen.dart';
import 'package:strumsight/features/songs/screens/setlist_list_screen.dart';
import 'package:strumsight/features/songs/screens/song_builder_screen.dart';
import 'package:strumsight/features/songs/screens/song_list_screen.dart';
import 'package:strumsight/features/streak/daily_challenge.dart';
import 'package:strumsight/features/streak/screens/streak_screen.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_codec.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_repository.dart';
import 'package:strumsight/features/vision/data/persistence/vision_export.dart';
import 'package:strumsight/features/vision/data/persistence/vision_session_repository.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';
import 'package:strumsight/features/vision/presentation/providers/guitar_calibration_providers.dart';
import 'package:strumsight/features/vision/presentation/screens/guitar_calibration_screen.dart';

import '../../../tool/check_screen_reachability.dart';
import '../../fixtures/practice/session/practice_session_test_fixtures.dart';
import '../../fixtures/practice_generator/validation/validation_fixtures.dart';
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
// B-level fixtures (§8 step 3) — the remaining 24 reachable screens whose
// pump fixture lives in `test/features/**`, not `test/ui/goldens/**`.
// Adapted from the source test file named in each block's comment.
// ---------------------------------------------------------------------------

// ── ai_tutor (test/features/ai_tutor/presentation/tutor_*_screen_test.dart)─

AppConfig _tutorAiConfig({bool aiTutorEnabled = true}) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    aiTutorEnabled: aiTutorEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

class _FakeTutorMemoryRepository implements TutorMemoryRepository {
  _FakeTutorMemoryRepository({
    List<TutorMemoryFact> facts = const <TutorMemoryFact>[],
  }) {
    _facts.addAll(facts);
  }

  final List<TutorMemoryFact> _facts = <TutorMemoryFact>[];
  int deleteAllCalls = 0;
  int exportRedactedCalls = 0;
  String? lastExportPayload;
  final List<String> deletedFactIds = <String>[];

  @override
  Future<AppResult<List<TutorMemoryFact>>> list() async =>
      Success<List<TutorMemoryFact>>(
        List<TutorMemoryFact>.unmodifiable(_facts),
      );

  @override
  Future<AppResult<TutorMemoryFact>> saveCandidate(
    TutorMemoryCandidate candidate,
  ) async {
    final fact = TutorMemoryFact(
      id: candidate.id,
      content: candidate.content,
      conversationId: candidate.conversationId,
      messageId: candidate.messageId,
      createdAt: candidate.createdAt,
      updatedAt: candidate.createdAt,
      expiresAt: candidate.expiresAt,
    );
    _facts.add(fact);
    return Success<TutorMemoryFact>(fact);
  }

  @override
  Future<AppResult<void>> update(TutorMemoryFact fact) async {
    final index = _facts.indexWhere((item) => item.id == fact.id);
    if (index == -1) {
      return const Failure<void>(
        ValidationFailure(code: FailureCode.validationInvalidInput),
      );
    }
    _facts[index] = fact;
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> delete(String factId) async {
    _facts.removeWhere((item) => item.id == factId);
    deletedFactIds.add(factId);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> purgeExpired(DateTime now) async {
    _facts.removeWhere((fact) => fact.isExpiredAt(now));
    return const Success<void>(null);
  }

  @override
  Future<AppResult<String>> exportRedacted() async {
    exportRedactedCalls++;
    lastExportPayload =
        '{"schemaVersion":1,"facts":[{"id":"x","content":"[redacted]"}]}';
    return Success<String>(lastExportPayload!);
  }

  @override
  Future<AppResult<void>> deleteAllAiData() async {
    deleteAllCalls++;
    _facts.clear();
    return const Success<void>(null);
  }
}

class _FakeTutorConversationRepository implements TutorConversationRepository {
  final List<TutorConversation> _conversations = <TutorConversation>[];

  @override
  Future<AppResult<void>> save(TutorConversation conversation) async {
    _conversations.add(conversation);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<TutorConversation?>> get(TutorConversationId id) async =>
      Success<TutorConversation?>(
        _conversations.cast<TutorConversation?>().firstWhere(
          (item) => item?.id == id,
          orElse: () => null,
        ),
      );

  @override
  Future<AppResult<TutorConversationPage>> list({
    int offset = 0,
    int limit = 20,
  }) async {
    final end = (offset + limit).clamp(0, _conversations.length);
    final page = offset >= _conversations.length
        ? const <TutorConversation>[]
        : _conversations.sublist(offset, end);
    return Success<TutorConversationPage>(
      TutorConversationPage(
        items: page,
        offset: offset,
        total: _conversations.length,
      ),
    );
  }

  @override
  Future<AppResult<TutorConversationSummary?>> summary(
    TutorConversationId id,
  ) async {
    for (final c in _conversations) {
      if (c.id == id) {
        return Success<TutorConversationSummary?>(
          TutorConversationSummary(
            conversationId: c.id,
            messageCount: c.messages.length,
            messageProvenance: const <TutorMessageProvenance>[],
          ),
        );
      }
    }
    return const Success<TutorConversationSummary?>(null);
  }

  @override
  Future<AppResult<void>> delete(TutorConversationId id) async {
    _conversations.removeWhere((item) => item.id == id);
    return const Success<void>(null);
  }
}

Widget _tutorDataScreen() => const TutorDataScreen();
List<Override> _tutorDataOverrides() => [
  ...preferenceOverrides(),
  appConfigProvider.overrideWithValue(_tutorAiConfig()),
  tutorMemoryRepositoryProvider.overrideWithValue(_FakeTutorMemoryRepository()),
  tutorConversationRepositoryProvider.overrideWithValue(
    _FakeTutorConversationRepository(),
  ),
];

Widget _tutorPrivacyScreen() => const TutorPrivacyScreen();
List<Override> _tutorPrivacyOverrides() => [
  ...preferenceOverrides(),
  appConfigProvider.overrideWithValue(_tutorAiConfig()),
  tutorMemoryRepositoryProvider.overrideWithValue(_FakeTutorMemoryRepository()),
];

Widget _tutorProfileScreen() => const TutorProfileScreen();
List<Override> _tutorProfileOverrides() => [
  ...preferenceOverrides(),
  appConfigProvider.overrideWithValue(_tutorAiConfig()),
];

// ── analyze (test/features/analyze/mic_error_parity_test.dart) ────────────

class _AnalyzeMicErrorStub extends AnalyzeController {
  @override
  AnalyzeState build() => const AnalyzeState(phase: AnalyzePhase.micError);
}

Widget _analyzeScreen() => const Scaffold(body: AnalyzeScreen());
List<Override> _analyzeOverrides() => [
  ...preferenceOverrides(),
  analyzeControllerProvider.overrideWith(_AnalyzeMicErrorStub.new),
];

// ── audio_analysis export (test/features/audio_analysis/.../analysis_export_screen_test.dart)

class _ExportFakeShareService extends ShareService {
  _ExportFakeShareService();

  @override
  Future<void> shareExportFile({
    required File file,
    required String caption,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {}
}

AnalysisDocument _analysisExportDocument() => AnalysisDocument(
  id: 'doc-screen',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 13),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 20),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'fp',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1.0.0',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'cfg',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fp',
    platform: 'android',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: 0.8,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0.5,
  ),
  capabilities: <CapabilityReport>[
    CapabilityReport(
      capability: AnalysisCapability.onsetTimeline,
      status: CapabilityStatus.available,
      confidence: 0.9,
    ),
  ],
  timeline: AnalysisTimeline(duration: const Duration(seconds: 20)),
  metrics: <AnalysisMetricResult>[
    AnalysisMetricResult(
      id: AnalysisMetricId.timingMeanAbsoluteError,
      version: 1,
      status: CapabilityStatus.available,
      confidence: 0.7,
      unit: 's',
      sampleCount: 4,
      evidence: const <String>[],
      value: ScalarMetricValue(0.05),
    ),
  ],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);

Widget _analysisExportScreen() => AnalysisExportScreen(
  document: _analysisExportDocument(),
  exportUseCase: ExportAnalysisUseCase(
    shareService: _ExportFakeShareService(),
    tempDirectory: Directory.systemTemp,
  ),
);
List<Override> _analysisExportOverrides() => [...preferenceOverrides()];

// ── gamification (test/features/gamification/presentation/*_test.dart) ────

Widget _achievementDetailScreen() => AchievementDetailScreen(
  achievementId: 'practice_starter',
  definitions: <AchievementDefinition>[
    AchievementDefinition(
      id: 'practice_starter',
      category: AchievementCategory.practice,
      titleKey: 'achievementPracticeStarterTitle',
      descriptionKey: 'achievementPracticeStarterDescription',
      accessibilityDescriptionKey: 'achievementPracticeStarterSemantics',
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
  ],
  progressByAchievement: <String, AchievementProgress>{
    'practice_starter': AchievementProgress(
      achievementId: 'practice_starter',
      catalogVersion: 1,
      value: 0.6,
    ),
  },
  evidence: null,
);
List<Override> _achievementDetailOverrides() => [...preferenceOverrides()];

LevelCurve _levelDetailCurve() => LevelCurve(<LevelDefinition>[
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

GamificationProfile _levelDetailProfile({int totalXp = 60}) =>
    GamificationProfile(
      schemaVersion: gamificationProfileSchemaVersion,
      totalXp: totalXp,
      progress: _levelDetailCurve().progressForTotalXp(totalXp),
    );

ExperiencePoints _levelDetailXp() => ExperiencePoints(
  baseXp: 10,
  durationXp: 8,
  qualityXp: 6,
  improvementXp: 4,
  diversityXp: 2,
);

Widget _levelDetailScreen() => LevelDetailScreen(
  profile: _levelDetailProfile(totalXp: 60),
  latestSessionXp: _levelDetailXp(),
  components: buildR06XpComponents(
    l10n: AppLocalizationsEn(),
    xp: _levelDetailXp(),
  ),
);
List<Override> _levelDetailOverrides() => [...preferenceOverrides()];

// ── learn (test/features/learn/*_test.dart) ────────────────────────────────

Widget _latencyCalibrationScreen() => LatencyCalibrationScreen();
List<Override> _latencyCalibrationOverrides() => [...preferenceOverrides()];

Widget _learnScreen() => LearnScreen(lesson: Lessons.firstStrums);
List<Override> _learnOverrides() {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  return [
    ...preferenceOverrides(),
    strumEngineProvider.overrideWithValue(engine),
  ];
}

class _ScoreCardFakeShareService extends ShareService {
  const _ScoreCardFakeShareService();

  @override
  Future<void> shareImage({
    required GlobalKey boundaryKey,
    required String caption,
    required String fileName,
    String? fallbackText,
    Rect? sharePositionOrigin,
  }) async {}
}

Widget _lessonScorePreviewScreen() => LessonScorePreviewScreen(
  lesson: Lessons.downUpGroove,
  accuracy: 0.85,
  maxCombo: 11,
  hits: 10,
  total: 12,
  shareService: const _ScoreCardFakeShareService(),
);
List<Override> _lessonScorePreviewOverrides() => [...preferenceOverrides()];

// ── library (test/features/library/rename_capo_title_test.dart) ───────────

Widget _libraryScreen() => const Scaffold(body: LibraryScreen());
List<Override> _libraryOverrides() => [...preferenceOverrides()];

AnalyzedSession _sessionDetailFixtureSession() => AnalyzedSession(
  id: 'a',
  createdAt: DateTime(2026, 7, 11),
  title: 'C · G',
  result: const AnalyzeResult(
    durationSec: 4,
    bpm: 90,
    chords: [TimelineChord(label: 'C', startSec: 0, endSec: 4)],
    strums: [],
  ),
);

Widget _sessionDetailScreen() =>
    SessionDetailScreen(session: _sessionDetailFixtureSession());
List<Override> _sessionDetailOverrides() => [...preferenceOverrides()];

// ── practice_hub (test/features/practice/presentation/practice_a11y_audit_test.dart)

class _PracticeHubFixtureRepo implements PracticeCatalogRepository {
  _PracticeHubFixtureRepo(this.defs);
  final List<PracticeDefinition> defs;
  @override
  List<PracticeDefinition> all() => defs;
  @override
  PracticeDefinition? byId(String id) {
    for (final d in defs) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  List<PracticeDefinition> byMode(PracticeMode mode) =>
      defs.where((d) => d.mode == mode).toList(growable: false);

  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      defs.where((d) => d.difficulty == difficulty).toList(growable: false);
}

PracticeDefinition _practiceHubStrumPatternDef(String id, String title) =>
    PracticeDefinition(
      id: id,
      schemaVersion: 1,
      titleKey: 'practiceCatalogTestSetupTitle',
      descriptionKey: 'practiceCatalogTestSetupDescription',
      mode: PracticeMode.strumPattern,
      source: PracticeSource.builtin,
      meter: const practice_meter.Meter(beatsPerBar: 4),
      defaultTempo: practice_tempo.Tempo(80),
      totalBeats: practice_beat_position.BeatPosition.quarters(8),
      events: List<PracticeEvent>.unmodifiable(
        List.generate(
          8,
          (i) => PracticeEvent(
            id: '$id.e$i',
            position: practice_beat_position.BeatPosition.quarters(i),
            direction: i.isEven ? StrumDirection.down : StrumDirection.up,
          ),
        ),
      ),
      scoringProfile: ScoringProfile.legacyLearnParity,
      skillTags: const ['rhythm.quarter_notes'],
      sourceReference: null,
      difficulty: PracticeDifficulty.beginner,
      displayTitle: title,
    );

Widget _practiceHubScreen() => const PracticeHubScreen(
  now: null,
  dailyChallenge: DailyChallenge(
    day: 19633,
    name: 'Audit',
    pattern: <StrumDirection>[],
  ),
);
List<Override> _practiceHubOverrides() {
  final repo = _PracticeHubFixtureRepo([
    _practiceHubStrumPatternDef('d1', 'Quarter downstrokes'),
    _practiceHubStrumPatternDef('d2', 'Alternating eighths'),
  ]);
  return [
    ...preferenceOverrides(),
    practiceCatalogRepositoryProvider.overrideWithValue(repo),
  ];
}

// ── practice_generator (test/features/practice_generator/presentation/*_test.dart)

Widget _planSetupScreen() {
  final controller = PlanSetupController(
    draftRepository: GenerationDraftRepository(
      keyValueStore: InMemoryKeyValueStore(),
    ),
    clock: () => DateTime.utc(2026, 8, 18),
    generateId: () => 'wizard-test-id',
    locale: 'en',
  );
  addTearDown(controller.dispose);
  return PlanSetupScreen(controller: controller);
}

List<Override> _planSetupOverrides() => [...preferenceOverrides()];

Widget _todayPlanScreen() {
  final restDay = PracticeDay(
    id: DayId('rest-day'),
    localDate: LocalDate(2026, 8, 19),
    status: PracticeItemStatus.planned,
    timeBudget: const Duration(minutes: 30),
    blocks: const <PracticeBlock>[],
    primaryFocusSkillIds: const <String>['rest'],
    reasonCodes: <String>[ScheduleDecisionReason.restDay.code],
  );
  return TodayPlanScreen(
    controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
    plan: buildPlan(days: <PracticeDay>[restDay]),
  );
}

List<Override> _todayPlanOverrides() => [...preferenceOverrides()];

// ── progress (test/features/progress/progress_screen_test.dart) ───────────

class _SeededPracticeLog extends PracticeLogController {
  _SeededPracticeLog(this._seed);
  final List<progress_entry.PracticeEntry> _seed;
  @override
  List<progress_entry.PracticeEntry> build() => _seed;
}

Widget _progressScreen() => ProgressScreen(now: DateTime(2026, 7, 9));
List<Override> _progressOverrides() => [
  ...preferenceOverrides(),
  practiceLogProvider.overrideWith(
    () => _SeededPracticeLog([
      progress_entry.PracticeEntry(
        day: 19548,
        source: progress_entry.PracticeSource.learn,
        seconds: 120,
        strokes: 10,
        chords: 3,
        directionAccuracy: 0.8,
      ),
      progress_entry.PracticeEntry(
        day: 19548,
        source: progress_entry.PracticeSource.analyze,
        seconds: 60,
        strokes: 5,
      ),
      progress_entry.PracticeEntry(
        day: 19547,
        source: progress_entry.PracticeSource.live,
        seconds: 90,
        strokes: 8,
      ),
    ]),
  ),
];

// ── vision_privacy (test/features/settings/vision_privacy_screen_test.dart)

Widget _visionPrivacyScreen() {
  final store = InMemoryKeyValueStore();
  final repository = VisionSessionRepository(store: store);
  return VisionPrivacyScreen(
    repository: repository,
    export: VisionExport(store: store),
  );
}

List<Override> _visionPrivacyOverrides() => [...preferenceOverrides()];

// ── share (test/features/share/strum_reel_test.dart) ───────────────────────

final _strumReelResult = AnalyzeResult(
  durationSec: 4,
  bpm: 100,
  chords: const [
    TimelineChord(label: 'C', startSec: 0, endSec: 2),
    TimelineChord(label: 'G', startSec: 2, endSec: 4),
  ],
  strums: [
    for (var i = 0; i < 6; i++)
      TimelineStrum(
        direction: i.isEven ? StrumDirection.down : StrumDirection.up,
        timeSec: i * 0.5,
        confidence: 1,
      ),
  ],
);

Widget _strumReelScreen() => StrumReelScreen(result: _strumReelResult);
List<Override> _strumReelOverrides() => [...preferenceOverrides()];

// ── songs (test/features/songs/*_test.dart) ─────────────────────────────────

class _SeededSongs extends SongsController {
  _SeededSongs(this._seed);
  final List<Song> _seed;
  @override
  List<Song> build() {
    super.build();
    return _seed;
  }
}

class _SeededSetlists extends SetlistsController {
  _SeededSetlists(this._seed);
  final List<Setlist> _seed;
  @override
  List<Setlist> build() {
    super.build();
    return _seed;
  }
}

const _setlistFixtureSong = Song(
  id: 'a',
  name: 'First Song',
  chords: ['C', 'G'],
  pattern: [
    StrumDirection.down, null, StrumDirection.down, null, //
    StrumDirection.down, null, StrumDirection.down, null,
  ],
  bpm: 100,
);

const _setlistFixtureSet = Setlist(id: 's', name: 'My Gig', songIds: ['a']);

Widget _setlistDetailScreen() => const SetlistDetailScreen(setlistId: 's');
List<Override> _setlistDetailOverrides() => [
  ...preferenceOverrides(),
  songsProvider.overrideWith(() => _SeededSongs([_setlistFixtureSong])),
  setlistsProvider.overrideWith(() => _SeededSetlists([_setlistFixtureSet])),
];

Widget _setlistListScreen() => const SetlistListScreen();
List<Override> _setlistListOverrides() => [
  ...preferenceOverrides(),
  songsProvider.overrideWith(() => _SeededSongs(const [])),
  setlistsProvider.overrideWith(() => _SeededSetlists([_setlistFixtureSet])),
];

Widget _songBuilderScreen() => const SongBuilderScreen();
List<Override> _songBuilderOverrides() => [...preferenceOverrides()];

const _songListD = StrumDirection.down;
const _songListU = StrumDirection.up;
const StrumDirection? _songListX = null;

Song _songListWaltz({int bpm = 60}) => Song(
  id: 'w1',
  name: 'My Waltz',
  chords: const ['C', 'G'],
  pattern: const [
    _songListD,
    _songListX,
    _songListU,
    _songListX,
    _songListU,
    _songListX,
  ],
  beatsPerBar: 3,
  bpm: bpm,
);

Widget _songListScreen() => const SongListScreen();
List<Override> _songListOverrides() => [
  ...preferenceOverrides(),
  songsProvider.overrideWith(
    () => _SeededSongs([
      _songListWaltz(),
      Song(
        id: 'c1',
        name: 'Common Time',
        chords: const ['C'],
        pattern: const [
          _songListD, _songListX, _songListD, _songListX, //
          _songListD, _songListX, _songListD, _songListX,
        ],
        bpm: 90,
      ),
    ]),
  ),
];

// ── streak (test/features/streak/streak_screen_test.dart) ─────────────────

Widget _streakScreen() => StreakScreen(now: DateTime(2026, 7, 9));
List<Override> _streakOverrides() => [...preferenceOverrides()];

// ── vision guitar calibration (test/features/vision/.../guitar_calibration_screen_test.dart)

GuitarCalibrationContext _guitarCalibrationContext() =>
    GuitarCalibrationContext(
      camera: VisionCameraPreference.back,
      orientation: CameraRotation.degrees0,
      zoom: 0.5,
      setupProfile: VisionSetupProfile.practiceBalanced,
      now: () => DateTime(2026, 1, 1, 12),
    );

VisionCalibrationRepository _emptyGuitarCalibrationRepository() =>
    VisionCalibrationRepository(
      document: JsonDocumentStore(
        store: InMemoryKeyValueStore(),
        logger: const NoopAppLogger(),
        key: StorageKeys.visionCalibration,
        legacyKey: 'ss.vision.calibration.legacy',
        name: 'vision_calibration',
        bodyKey: 'data',
      ),
      codec: const VisionCalibrationCodec(),
    );

Widget _guitarCalibrationScreen() => const GuitarCalibrationScreen();
List<Override> _guitarCalibrationOverrides() => [
  ...preferenceOverrides(),
  visionCalibrationRepositoryProvider.overrideWithValue(
    _emptyGuitarCalibrationRepository(),
  ),
  guitarCalibrationRuntimeContextProvider.overrideWithValue(
    _guitarCalibrationContext(),
  ),
];

// ---------------------------------------------------------------------------
// A-level + B-level registry (§0.0.A/R3 — the full 70 fixtured screens + the
// two R5 screens; only `WrappedPreviewScreen` stays excluded, §8 step 3).
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
  'tutor_data': _ScreenFixture(
    screenPath:
        'lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart',
    build: _tutorDataScreen,
    overridesBuilder: _tutorDataOverrides,
  ),
  'tutor_privacy': _ScreenFixture(
    screenPath:
        'lib/features/ai_tutor/presentation/screens/tutor_privacy_screen.dart',
    build: _tutorPrivacyScreen,
    overridesBuilder: _tutorPrivacyOverrides,
  ),
  'tutor_profile': _ScreenFixture(
    screenPath:
        'lib/features/ai_tutor/presentation/screens/tutor_profile_screen.dart',
    build: _tutorProfileScreen,
    overridesBuilder: _tutorProfileOverrides,
  ),
  'analyze': _ScreenFixture(
    screenPath: 'lib/features/analyze/screens/analyze_screen.dart',
    build: _analyzeScreen,
    overridesBuilder: _analyzeOverrides,
  ),
  'analysis_export': _ScreenFixture(
    screenPath:
        'lib/features/audio_analysis/presentation/analysis_export_screen.dart',
    build: _analysisExportScreen,
    overridesBuilder: _analysisExportOverrides,
  ),
  'achievement_detail': _ScreenFixture(
    screenPath:
        'lib/features/gamification/presentation/screens/achievement_detail_screen.dart',
    build: _achievementDetailScreen,
    overridesBuilder: _achievementDetailOverrides,
  ),
  'level_detail': _ScreenFixture(
    screenPath:
        'lib/features/gamification/presentation/screens/level_detail_screen.dart',
    build: _levelDetailScreen,
    overridesBuilder: _levelDetailOverrides,
  ),
  'latency_calibration': _ScreenFixture(
    screenPath: 'lib/features/learn/screens/latency_calibration_screen.dart',
    build: _latencyCalibrationScreen,
    overridesBuilder: _latencyCalibrationOverrides,
  ),
  'learn': _ScreenFixture(
    screenPath: 'lib/features/learn/screens/learn_screen.dart',
    build: _learnScreen,
    overridesBuilder: _learnOverrides,
  ),
  'lesson_score_preview': _ScreenFixture(
    screenPath: 'lib/features/learn/screens/lesson_score_preview_screen.dart',
    build: _lessonScorePreviewScreen,
    overridesBuilder: _lessonScorePreviewOverrides,
  ),
  'library': _ScreenFixture(
    screenPath: 'lib/features/library/screens/library_screen.dart',
    build: _libraryScreen,
    overridesBuilder: _libraryOverrides,
  ),
  'session_detail': _ScreenFixture(
    screenPath: 'lib/features/library/screens/session_detail_screen.dart',
    build: _sessionDetailScreen,
    overridesBuilder: _sessionDetailOverrides,
  ),
  'practice_hub': _ScreenFixture(
    screenPath:
        'lib/features/practice/presentation/screens/practice_hub_screen.dart',
    build: _practiceHubScreen,
    overridesBuilder: _practiceHubOverrides,
  ),
  'plan_setup': _ScreenFixture(
    screenPath:
        'lib/features/practice_generator/presentation/screens/plan_setup_screen.dart',
    build: _planSetupScreen,
    overridesBuilder: _planSetupOverrides,
  ),
  'today_plan': _ScreenFixture(
    screenPath:
        'lib/features/practice_generator/presentation/screens/today_plan_screen.dart',
    build: _todayPlanScreen,
    overridesBuilder: _todayPlanOverrides,
  ),
  'progress': _ScreenFixture(
    screenPath: 'lib/features/progress/screens/progress_screen.dart',
    build: _progressScreen,
    overridesBuilder: _progressOverrides,
  ),
  'vision_privacy': _ScreenFixture(
    screenPath: 'lib/features/settings/screens/vision_privacy_screen.dart',
    build: _visionPrivacyScreen,
    overridesBuilder: _visionPrivacyOverrides,
  ),
  'strum_reel': _ScreenFixture(
    screenPath: 'lib/features/share/screens/strum_reel_screen.dart',
    build: _strumReelScreen,
    overridesBuilder: _strumReelOverrides,
  ),
  'setlist_detail': _ScreenFixture(
    screenPath: 'lib/features/songs/screens/setlist_detail_screen.dart',
    build: _setlistDetailScreen,
    overridesBuilder: _setlistDetailOverrides,
  ),
  'setlist_list': _ScreenFixture(
    screenPath: 'lib/features/songs/screens/setlist_list_screen.dart',
    build: _setlistListScreen,
    overridesBuilder: _setlistListOverrides,
  ),
  'song_builder': _ScreenFixture(
    screenPath: 'lib/features/songs/screens/song_builder_screen.dart',
    build: _songBuilderScreen,
    overridesBuilder: _songBuilderOverrides,
  ),
  'song_list': _ScreenFixture(
    screenPath: 'lib/features/songs/screens/song_list_screen.dart',
    build: _songListScreen,
    overridesBuilder: _songListOverrides,
  ),
  'streak': _ScreenFixture(
    screenPath: 'lib/features/streak/screens/streak_screen.dart',
    build: _streakScreen,
    overridesBuilder: _streakOverrides,
  ),
  'guitar_calibration': _ScreenFixture(
    screenPath:
        'lib/features/vision/presentation/screens/guitar_calibration_screen.dart',
    build: _guitarCalibrationScreen,
    overridesBuilder: _guitarCalibrationOverrides,
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

// The exclusion list may only shrink (L180) — after the B-level commit
// (§8 step 3) this holds exactly the one screen with NO merged pump fixture
// anywhere in the tree, `WrappedPreviewScreen` (measured, §0.0.A/R3): the
// "no merged fixture" reason is the ONLY one that may appear here.
const _exclusions = <_ExclusionEntry>[
  _ExclusionEntry(
    screenPath: 'lib/features/share/screens/wrapped_preview_screen.dart',
    reason:
        'No merged pump fixture anywhere in the tree (measured, §0.0.A/R3) — '
        'neither test/ui/goldens/** nor test/features/** constructs this '
        'screen. Building one is new test-authoring scope beyond this '
        'measurement-only round.',
    followUpRound:
        'no round is currently queued to build a WrappedPreviewScreen pump '
        'fixture; admitting one is a user/pipeline scheduling decision, not '
        'an SDD-round assignment (measured, §0.0.A/R3)',
  ),
];

// ---------------------------------------------------------------------------
// The measurement the completion report was written against (A5 below).
//
// L613 (ADR 0112 self-heal, 2026-09-03): `docs/ui/chapter-15-completion-
// report.md` is a DATED historical record — its own header says
// "Measured against: `main @ 9ba54399` + this round's own tree". A guard
// that re-measures the LIVE tree and demands the report cite THOSE numbers
// therefore goes red the moment any later round legitimately changes
// reachability, and it goes red for a round that cannot fix it (the report
// is outside that round's allowed paths). E16-R02 is exactly that case: its
// acceptance criteria ARE +2 reachable screens, so its own success flipped
// this cell to `does not contain '73'`.
//
// The expected numbers come from a recorded snapshot of that base instead
// (`_baselinePath`, provenance in `test/fixtures/manifest.json`). L588's
// property is unchanged: every asserted fact is still derived
// independently of what the report SAYS, so a silently DELETED claim
// (not just a wrong one) still fails. The LIVE tree keeps its own guard —
// the A1 completeness group above, whose invariant (measured reachable set
// ⊆ matrix ∪ exclusion list) survives legitimate reachability growth.
// ---------------------------------------------------------------------------

const _baselinePath =
    'test/fixtures/ui/e15_r13_completion_report_baseline.json';

// E17-R01 (ADR 0112 self-heal, 2026-09-05): the SAME failure class reached
// the matrix-count cells too. The E16-R02 heal above moved only the
// reachability/migration numbers onto the recorded snapshot; the screen /
// cell / grand-total cells kept deriving their expectation from the LIVE
// `_screens` map, so any round that legitimately ADDS a screen to the matrix
// (72 → 73 screens, 1152 → 1168 cells, 1163 → 1179 tests) again turned its
// own success into a red guard over a DATED report it may not edit. Those
// counts are therefore recorded here too, measured at the report's base —
// the live matrix keeps its own guards (the A1 completeness group and
// `_runCell`'s STALE exclusion-list branch), so nothing is weakened.
final class _MatrixBaseline {
  const _MatrixBaseline({
    required this.screenCount,
    required this.viewportCount,
    required this.totalCells,
    required this.excludedCellCount,
    required this.a1CellCount,
    required this.a5CellCount,
    required this.grandTotalTests,
  });

  factory _MatrixBaseline.fromJson(Map<String, Object?> json) =>
      _MatrixBaseline(
        screenCount: json['screenCount']! as int,
        viewportCount: json['viewportCount']! as int,
        totalCells: json['totalCells']! as int,
        excludedCellCount: json['excludedCellCount']! as int,
        a1CellCount: json['a1CellCount']! as int,
        a5CellCount: json['a5CellCount']! as int,
        grandTotalTests: json['grandTotalTests']! as int,
      );

  final int screenCount;
  final int viewportCount;
  final int totalCells;
  final int excludedCellCount;
  final int a1CellCount;
  final int a5CellCount;
  final int grandTotalTests;
}

final class _BaselineScreen {
  const _BaselineScreen({
    required this.screenPath,
    required this.isReachable,
    required this.isFlagGated,
    required this.isMigrated,
  });

  final String screenPath;
  final bool isReachable;
  final bool isFlagGated;
  final bool isMigrated;
}

final class _CompletionReportBaseline {
  const _CompletionReportBaseline({
    required this.measuredScreenCount,
    required this.reachableCount,
    required this.unreachableCount,
    required this.flagGatedCount,
    required this.migratedCount,
    required this.screens,
    required this.matrix,
  });

  factory _CompletionReportBaseline.read(String path) {
    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    return _CompletionReportBaseline(
      measuredScreenCount: json['measuredScreenCount']! as int,
      reachableCount: json['reachableCount']! as int,
      unreachableCount: json['unreachableCount']! as int,
      flagGatedCount: json['flagGatedCount']! as int,
      migratedCount: json['migratedCount']! as int,
      matrix: _MatrixBaseline.fromJson(json['matrix']! as Map<String, Object?>),
      screens: [
        for (final screen
            in (json['screens']! as List<Object?>).cast<Map<String, Object?>>())
          _BaselineScreen(
            screenPath: screen['screenPath']! as String,
            isReachable: screen['reachable']! as bool,
            isFlagGated: screen['flagGated']! as bool,
            isMigrated: screen['migrated']! as bool,
          ),
      ],
    );
  }

  final int measuredScreenCount;
  final int reachableCount;
  final int unreachableCount;
  final int flagGatedCount;
  final int migratedCount;
  final List<_BaselineScreen> screens;
  final _MatrixBaseline matrix;
}

// ---------------------------------------------------------------------------
// Per-CELL overflow exclusion list (§5.2, mirrors
// `e13_r36_variant_matrix_test.dart`'s `_ExcludedCell`/`_excludedCells`
// pattern) — orthogonal to `_exclusions` above (which is about which
// SCREENS are in the matrix, §0.0.A/R3). This one records a genuine,
// measured, dated `lib/**` overflow this closing round found but — per
// brief §5.2 — may NOT fix (`lib/**` is this round's tilos zona). Every
// entry is mirrored in `docs/ui/legacy-backlog.md`. Can only SHRINK: a
// listed cell that no longer overflows fails this suite (`_runCell`'s
// `STALE exclusion-list entry` branch) rather than silently staying on the
// list forever (L180).
// ---------------------------------------------------------------------------

final class _ExcludedCell {
  const _ExcludedCell({
    required this.screen,
    required this.theme,
    required this.locale,
    required this.viewport,
    required this.textScale,
    required this.measuredOverflowPx,
    required this.measuredOn,
  });

  final String screen;
  final String theme;
  final String locale;
  final _ViewportProfile viewport;
  final double textScale;
  final double measuredOverflowPx;
  final String measuredOn;

  String get key =>
      '$screen|$theme|$locale|${_viewportNames[viewport]}|$textScale';
}

/// `lib/features/share/screens/strum_reel_screen.dart:339` — the tagline
/// `Row` (`↓↑` glyph + `l10n.reelTagline` text, `mainAxisAlignment: center`,
/// no `Flexible`/`Expanded` wrapper) inside a fixed-aspect-ratio reel card
/// narrower than the device width; the card's `landscape|1.0` cells never
/// overflow (most horizontal room relative to text), every other cell does.
/// Measured 2026-09-03 on this box, both themes identically (theme doesn't
/// affect layout, only color) — MEASURE, DO NOT FIX (`lib/**` is this
/// round's tilos zona, brief §5.2).
const _excludedCells = <_ExcludedCell>[
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'light',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 1.0,
    measuredOverflowPx: 191,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'light',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 862,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'light',
    locale: 'en',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 312,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'light',
    locale: 'hu',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 1.0,
    measuredOverflowPx: 228,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'light',
    locale: 'hu',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 935,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'light',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 419,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'dark',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 1.0,
    measuredOverflowPx: 191,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'dark',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 862,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'dark',
    locale: 'en',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 312,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'dark',
    locale: 'hu',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 1.0,
    measuredOverflowPx: 228,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'dark',
    locale: 'hu',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 935,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'strum_reel',
    theme: 'dark',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 419,
    measuredOn: '2026-09-03',
  ),

  // Four MORE measured, dated `lib/**` defects, all textScale 2.0 only
  // (each screen's own row/card layout has no accessibility-scale headroom
  // at 2.0x — brief §6's "pontosan a küszöbön (2.0) minden cella zöld"
  // requirement is the DESIGN intent A2 verifies; a genuine found defect is
  // recorded here, not silently made to pass, per §5.2/§9). Different
  // screens, different root causes — MEASURE, DO NOT FIX.

  // `lib/features/analyze/screens/analyze_screen.dart:331` — the mic-error
  // state's action Row (icon + retry label), hu locale only (longer string)
  // at landscape (least vertical room pushes it into a horizontal squeeze).
  _ExcludedCell(
    screen: 'analyze',
    theme: 'light',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 36,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'analyze',
    theme: 'dark',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 36,
    measuredOn: '2026-09-03',
  ),

  // `lib/features/learn/screens/latency_calibration_screen.dart` — compact
  // portrait, en only (the shorter locale — this one is a fixed-height
  // measurement row, not a text-length issue).
  _ExcludedCell(
    screen: 'latency_calibration',
    theme: 'light',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 25,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'latency_calibration',
    theme: 'dark',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 25,
    measuredOn: '2026-09-03',
  ),

  // `lib/features/learn/screens/learn_screen.dart:879`'s bottom action Row —
  // overflows identically (26.3px) at EVERY locale/viewport combination at
  // textScale 2.0, i.e. depends only on the scale, not locale or viewport.
  _ExcludedCell(
    screen: 'learn',
    theme: 'light',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 26.3,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'learn',
    theme: 'light',
    locale: 'en',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 26.3,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'learn',
    theme: 'light',
    locale: 'hu',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 26.3,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'learn',
    theme: 'light',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 26.3,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'learn',
    theme: 'dark',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 26.3,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'learn',
    theme: 'dark',
    locale: 'en',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 26.3,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'learn',
    theme: 'dark',
    locale: 'hu',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 26.3,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'learn',
    theme: 'dark',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 26.3,
    measuredOn: '2026-09-03',
  ),

  // `lib/features/learn/screens/lesson_score_preview_screen.dart:101`'s
  // fixed-size `SizedBox` share-card boundary — overflows identically
  // (366px) at EVERY locale/viewport combination at textScale 2.0: the card
  // is a fixed pixel size (for the share-image capture boundary) that does
  // not grow with the accessibility text scale.
  _ExcludedCell(
    screen: 'lesson_score_preview',
    theme: 'light',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 366,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'lesson_score_preview',
    theme: 'light',
    locale: 'en',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 366,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'lesson_score_preview',
    theme: 'light',
    locale: 'hu',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 366,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'lesson_score_preview',
    theme: 'light',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 366,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'lesson_score_preview',
    theme: 'dark',
    locale: 'en',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 366,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'lesson_score_preview',
    theme: 'dark',
    locale: 'en',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 366,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'lesson_score_preview',
    theme: 'dark',
    locale: 'hu',
    viewport: _ViewportProfile.compactPortrait,
    textScale: 2.0,
    measuredOverflowPx: 366,
    measuredOn: '2026-09-03',
  ),
  _ExcludedCell(
    screen: 'lesson_score_preview',
    theme: 'dark',
    locale: 'hu',
    viewport: _ViewportProfile.landscape,
    textScale: 2.0,
    measuredOverflowPx: 366,
    measuredOn: '2026-09-03',
  ),
];

final _excludedByKey = {for (final cell in _excludedCells) cell.key: cell};

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

      test('every exclusion entry carries a non-trivial reason, and its '
          'follow-up round is either a real round id or an explicit '
          '"none queued" disclosure (review E15-R13 MINOR-1: a generic '
          '"a future round … (SDD, unscheduled)" stub is machine-invisible '
          'and was previously accepted by a bare isNotEmpty check)', () {
        final roundIdPattern = RegExp(r'E\d{2}-R\d{2}');
        for (final entry in _exclusions) {
          expect(
            entry.reason.trim().length,
            greaterThan(10),
            reason: '${entry.screenPath} has a trivial/empty exclusion reason',
          );
          final namesRealRound = roundIdPattern.hasMatch(entry.followUpRound);
          final disclosesNoRoundQueued = entry.followUpRound.contains(
            'no round is currently queued',
          );
          expect(
            namesRealRound || disclosesNoRoundQueued,
            isTrue,
            reason:
                '${entry.screenPath} has a vague/generic follow-up-round '
                'placeholder — must either name a real round id '
                '(${roundIdPattern.pattern}) or explicitly state no round '
                'is currently queued',
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

  group('A5 — completion-report guard (measures completeness, not just '
      'present-row consistency, L588)', () {
    late String report;

    setUpAll(() {
      report = File(
        'docs/ui/chapter-15-completion-report.md',
      ).readAsStringSync();
    });

    // L588: a guard that only iterates the rows PRESENT in the report and
    // checks each is well-formed stays green on a silently DELETED row —
    // every fact checked here is derived from the LIVE measurement/matrix
    // state, independently of what the report currently says, so a removed
    // claim (not just a wrong one) fails this test.
    // L613: measured at the report's OWN base, not on the live tree — see
    // the `_CompletionReportBaseline` header above for the measured root
    // cause. The snapshot's four counts are recomputed from its own
    // per-screen rows first, so the fixture cannot be hand-edited into
    // agreement with a wrong report without also rewriting all 96 rows.
    test('cites the migration + reachability numbers measured at its own '
        'base (recorded snapshot, not the live tree)', () {
      final baseline = _CompletionReportBaseline.read(_baselinePath);

      expect(baseline.screens, hasLength(baseline.measuredScreenCount));
      expect(
        baseline.screens.where((s) => s.isReachable).length,
        baseline.reachableCount,
      );
      expect(
        baseline.screens.where((s) => !s.isReachable).length,
        baseline.unreachableCount,
      );
      expect(
        baseline.screens.where((s) => s.isFlagGated).length,
        baseline.flagGatedCount,
      );
      expect(
        baseline.screens.where((s) => s.isMigrated).length,
        baseline.migratedCount,
      );

      expect(report, contains('${baseline.measuredScreenCount}'));
      expect(report, contains('${baseline.reachableCount}'));
      expect(report, contains('${baseline.unreachableCount}'));
      expect(report, contains('${baseline.flagGatedCount}'));
      expect(
        report,
        contains('${baseline.migratedCount} / ${baseline.measuredScreenCount}'),
        reason:
            'the migrated/total count must be the RECORDED grep result of '
            'the report\'s own base, not a stale hand-typed number',
      );
    });

    // L613/E17-R01: the counts come from the RECORDED snapshot of the
    // report's own base (`_baselinePath`), not from the live `_screens` map
    // — the report is dated, the matrix is not. The snapshot's own product
    // is recomputed first, so the fixture cannot be hand-edited into
    // agreement with a wrong report one number at a time.
    test('cites the matrix screen/cell counts measured at its own base '
        '(recorded snapshot, not the live matrix)', () {
      final matrix = _CompletionReportBaseline.read(_baselinePath).matrix;

      expect(
        matrix.screenCount * 2 * 2 * matrix.viewportCount * 2,
        matrix.totalCells,
        reason:
            'the recorded cell count must be the product of the recorded '
            'matrix axes',
      );
      expect(
        report,
        contains('${matrix.screenCount}'),
        reason: 'matrix screen count (${matrix.screenCount}) missing/stale',
      );
      expect(
        report,
        contains('${matrix.totalCells}'),
        reason: 'total cell count (${matrix.totalCells}) missing/stale',
      );
      expect(
        report,
        contains('${matrix.excludedCellCount}'),
        reason:
            '_ExcludedCell count (${matrix.excludedCellCount}) missing/stale',
      );
    });

    // Review E15-R13 MAJOR-1 (L588 recurrence): the report quoted a
    // hand-typed "+1157: All tests passed!" `flutter test` output that
    // could not actually come out of that command — none of the cells
    // above pin the GRAND TOTAL (cells + this file's own structural
    // groups), only their individual components, so the wrong number
    // slipped through undetected.
    test('cites the grand total test count the file produced AT THE '
        'REPORT\'S BASE (cells + A1 + A5 structural groups) — catches a '
        'hand-typed, non-reproducible "All tests passed!" count '
        '(review MAJOR-1)', () {
      // The recorded A1/A5 group sizes are the `test()` counts of the
      // report's own base (there is no reflection-based way to count
      // `test()` calls at runtime); the grand total is recomputed from the
      // recorded parts, so a fixture edited to match a wrong report has to
      // stay internally consistent as well.
      final matrix = _CompletionReportBaseline.read(_baselinePath).matrix;
      final grandTotal =
          matrix.totalCells + matrix.a1CellCount + matrix.a5CellCount;

      expect(
        grandTotal,
        matrix.grandTotalTests,
        reason:
            'the recorded grand total must be the sum of the recorded parts',
      );
      expect(
        report,
        contains('${matrix.grandTotalTests}'),
        reason:
            'grand total test count (${matrix.grandTotalTests} = '
            '${matrix.totalCells} matrix cells + ${matrix.a1CellCount} A1 + '
            '${matrix.a5CellCount} A5) missing/stale — the report must cite '
            'the number `flutter test` produced at its own base',
      );
    });

    test('every currently-excluded SCREEN name is mentioned (no silent '
        'deletion of a finding)', () {
      // Normalized (lowercase, non-alnum stripped) so the report's
      // PascalCase class names (e.g. "LatencyCalibrationScreen") match the
      // matrix's snake_case keys (e.g. "latency_calibration") without
      // forcing the two to use identical spelling.
      final normalizedReport = report.toLowerCase().replaceAll(
        RegExp('[^a-z0-9]'),
        '',
      );
      final excludedScreenNames = _excludedCells.map((c) => c.screen).toSet();
      for (final name in excludedScreenNames) {
        final normalizedName = name.toLowerCase().replaceAll('_', '');
        expect(
          normalizedReport.contains(normalizedName),
          isTrue,
          reason:
              '$name has a live _ExcludedCell entry but is not mentioned in '
              'the completion report — a removed finding would stay '
              'undetected without this check',
        );
      }
    });

    test('names WrappedPreviewScreen as the sole coverage exclusion', () {
      expect(report, contains('WrappedPreviewScreen'));
      expect(_exclusions, hasLength(1));
      expect(
        _exclusions.single.screenPath,
        endsWith('wrapped_preview_screen.dart'),
      );
    });

    test('names the E15-R04 unexecuted retirement as an open item', () {
      expect(report, contains('E15-R04'));
    });
  });

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

              final excluded = _excludedByKey[cellKey];
              if (excluded == null) {
                expect(
                  result.overflowPx,
                  isNull,
                  reason:
                      'unexpected RenderFlex overflow of '
                      '${result.overflowPx}px — either this is a new '
                      'lib/** regression (blocked, this round cannot fix '
                      'lib/**) or a dated _ExcludedCell entry is missing',
                );
              } else {
                expect(
                  result.overflowPx,
                  isNotNull,
                  reason:
                      'STALE exclusion-list entry (measured '
                      '${excluded.measuredOverflowPx}px on '
                      '${excluded.measuredOn}): this cell no longer '
                      'overflows — remove the _ExcludedCell entry and its '
                      'docs/ui/legacy-backlog.md mirror (§0.0.A/R3: the '
                      'list may only shrink)',
                );
              }
            });
          }
        }
      }
    }
  }
}
