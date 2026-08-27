import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/performance/thermal_state_adapter.dart';

/// The default heuristic input: no observed pressure. Test-overridable
/// (§0.0/B3) — `application/vision_session_controller.dart` has zero thermal
/// callers today (measured), so this presentation-only provider is the only
/// source of thermal load until a later round wires the real capture path.
final visionThermalDecisionProvider = Provider<VisionThermalDecision>(
  (ref) => const ThermalStateAdapter().evaluate(
    heuristic: const VisionThermalHeuristicInput(
      receivedFrames: 0,
      droppedFrames: 0,
      averageFreshnessMs: 0,
      averageProcessingTimeMs: 0,
    ),
  ),
);

/// The Stage's thermal presentation state — a NAMED state distinct from
/// [CalibrationLossState] (§0.0/B3, A5): tracking loss and thermal pressure
/// are unrelated causes and must never share one banner or text.
enum VisionThermalUiState { normal, throttled }

/// The load (0..100) at or above which the Stage shows the thermal banner.
/// A presentation constant only — no rendering authority exists for this
/// yet in `application/`/`data/`.
const int visionThermalThrottleLoad = 70;

final visionThermalUiStateProvider = Provider<VisionThermalUiState>((ref) {
  final decision = ref.watch(visionThermalDecisionProvider);
  return decision.load >= visionThermalThrottleLoad
      ? VisionThermalUiState.throttled
      : VisionThermalUiState.normal;
});
