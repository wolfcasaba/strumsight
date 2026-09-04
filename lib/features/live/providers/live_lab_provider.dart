import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analyze/public.dart';
import '../../diagnostics/public.dart';
import '../../settings/public.dart';
import '../model/recognition_runtime_info.dart';
import 'live_providers.dart';

/// Where the Live Lab capture-and-analyze is in its lifecycle (r199).
enum LiveLabPhase { idle, analyzing, empty, done }

@immutable
class LiveLabState {
  const LiveLabState({
    this.phase = LiveLabPhase.idle,
    this.result,
    this.runtimeInfo,
  });

  final LiveLabPhase phase;
  final AnalyzeResult? result;

  /// Which strum model is behind the Live pipeline right now, or why it
  /// fell back (ADR 0355) — set via [LiveLabController.reportRuntimeInfo].
  /// Null until the first report. The actual isolate → Lab wiring lands in
  /// E14-R04 (R3): this round only makes the state additively carry it.
  final RecognitionRuntimeInfo? runtimeInfo;

  static const initial = LiveLabState();
}

/// Lab-mode Live capture-and-analyze (r199): grab the engine's rolling ~30 s of
/// mic PCM (external guitar audio played into the mic), run the SAME ML+DSP
/// clip analysis the Analyze screen uses (off the UI thread), and upload the
/// diagnostics session tagged `surface: live`. Everything is best-effort — it
/// never touches the running Live detection and never throws into the UI.
class LiveLabController extends Notifier<LiveLabState> {
  @override
  LiveLabState build() => LiveLabState.initial;

  /// Capture the recent mic buffer and analyze it. No-op while already
  /// analyzing; reports `empty` when the buffer holds nothing yet.
  Future<void> captureAndAnalyze() async {
    if (state.phase == LiveLabPhase.analyzing) return;

    final engine = ref.read(strumEngineProvider);
    final (pcm, sr) = engine.recentPcm();
    if (pcm.isEmpty || sr <= 0) {
      state = const LiveLabState(phase: LiveLabPhase.empty);
      return;
    }

    state = const LiveLabState(phase: LiveLabPhase.analyzing);
    // Clear any prior diagnostics upload status for a fresh capture.
    ref.read(diagnosticsUploadProvider.notifier).reset();

    // Lab mode is what shows this panel; load the ML chord weights so the
    // capture gets the full ML-vs-DSP diagnostics.
    final labMode = ref.read(labModeProvider);
    final AnalyzeResult result;
    try {
      result = await computeClipAnalysis(pcm, sr, labMode);
    } catch (_) {
      // A capture failure must never crash Live — fall back to idle.
      state = LiveLabState.initial;
      return;
    }
    state = LiveLabState(phase: LiveLabPhase.done, result: result);

    // Upload the diagnostics session best-effort, tagged as a Live capture.
    if (result.diagnostics != null) {
      unawaited(
        ref
            .read(diagnosticsUploadProvider.notifier)
            .upload(result, pcm, sr, surface: 'live'),
      );
    }
  }

  /// Back to idle (e.g. when leaving the screen) — clears a stale result.
  void reset() => state = LiveLabState.initial;

  /// Records which strum model is currently active, or why it fell back
  /// (ADR 0355) — additive telemetry only, leaves [LiveLabState.phase] and
  /// [LiveLabState.result] untouched. The actual isolate → Lab wiring lands
  /// in E14-R04 (R3); this entry point only makes the state representable.
  void reportRuntimeInfo(RecognitionRuntimeInfo? info) {
    state = LiveLabState(
      phase: state.phase,
      result: state.result,
      runtimeInfo: info,
    );
  }
}

final liveLabProvider = NotifierProvider<LiveLabController, LiveLabState>(
  LiveLabController.new,
);
