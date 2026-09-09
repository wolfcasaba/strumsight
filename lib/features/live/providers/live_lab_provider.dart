import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../analyze/public.dart';
import '../../diagnostics/public.dart';
import '../../settings/public.dart';
import '../data/shadow/recognition_shadow_gate.dart';
import '../data/shadow/recognition_shadow_recorder.dart';
import '../data/shadow/recognition_shadow_session.dart';
import '../domain/recognition/recognition_mode.dart';
import '../engine/ml/chord_crnn_shadow_runner.dart';
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
    this.shadow,
  });

  final LiveLabPhase phase;
  final AnalyzeResult? result;

  /// Which strum model is behind the Live pipeline right now, or why it
  /// fell back (ADR 0355) — set via [LiveLabController.reportRuntimeInfo].
  /// Null until the first report. The actual isolate → Lab wiring lands in
  /// E14-R04 (R3): this round only makes the state additively carry it.
  final RecognitionRuntimeInfo? runtimeInfo;

  /// The E14-R23/R26 shadow comparison for the captured buffer, or `null`
  /// when no capture has run yet. A snapshot whose gates are both closed is
  /// NOT null: it is the honest "the shadow bands are off in this build"
  /// report, and the panel renders it as such instead of showing nothing.
  final RecognitionShadowSnapshot? shadow;

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
    final shadow = await _runShadowComparison(pcm, sr);
    if (!ref.mounted) return;
    state = LiveLabState(
      phase: LiveLabPhase.done,
      result: result,
      runtimeInfo: _withShadowBands(state.runtimeInfo, shadow),
      shadow: shadow,
    );

    // Upload the diagnostics session best-effort, tagged as a Live capture.
    if (result.diagnostics != null) {
      unawaited(
        ref
            .read(diagnosticsUploadProvider.notifier)
            .upload(result, pcm, sr, surface: 'live'),
      );
    }
  }

  /// Runs the E14-R23 strum shadow and the E14-R26 chord-CRNN shadow over
  /// the SAME captured buffer, off the UI isolate.
  ///
  /// Gating (ADR 0548 D1): both bands come from
  /// [RecognitionShadowGate.fromFlags] and nothing else. With both gates
  /// closed no model asset is loaded, no isolate is spawned and no inference
  /// runs — the returned snapshot is the constant `disabled` shape. That is
  /// the "flag OFF ⇒ zero extra inference" contract, and a test counts the
  /// asset loads to prove it.
  ///
  /// Nothing this produces can reach recognition: the comparison runs on a
  /// second, short-lived pipeline over recorded audio, and its output goes
  /// only into [LiveLabState.shadow].
  Future<RecognitionShadowSnapshot?> _runShadowComparison(
    List<double> pcm,
    int sr,
  ) async {
    final gate = RecognitionShadowGate.fromFlags(
      ref.read(appConfigProvider).flags,
    );
    if (!gate.runsAnything) {
      return RecognitionShadowSnapshot.disabled(mode: RecognitionMode.free);
    }
    final strumWeights = gate.strumEnabled ? await _liveStrumWeights() : null;
    final chordWeights = gate.chordEnabled ? await _chordShadowWeights() : null;
    if (!ref.mounted) return null;
    return compute(
      runRecognitionShadow,
      RecognitionShadowRequest(
        pcm: pcm,
        sampleRate: sr,
        gate: gate,
        strumWeights: strumWeights,
        chordWeights: chordWeights,
        chordSha256: ChordCrnnShadowRunner.shippedChordModelSha256,
      ),
    );
  }

  /// Copies the shadow bands onto the runtime info the Lab already holds, so
  /// one export carries both "which model decided" and "which candidate ran
  /// beside it". Returns the info unchanged when there is nothing to attach.
  static RecognitionRuntimeInfo? _withShadowBands(
    RecognitionRuntimeInfo? info,
    RecognitionShadowSnapshot? shadow,
  ) {
    if (info == null || shadow == null) return info;
    final chordRan = shadow.chordShadowEnabled &&
        shadow.chordFallbackReason == null;
    return info.withShadowBands(
      recognitionMode: shadow.mode,
      shadowStage: shadow.strumStage,
      chordModelId: chordRan
          ? RecognitionRuntimeInfo.chordModelCrnn
          : RecognitionRuntimeInfo.chordModelNone,
      chordModelVersion: chordRan
          ? ChordCrnnShadowRunner.chordModelFormatVersion
          : 0,
      chordModelSha256: chordRan
          ? ChordCrnnShadowRunner.shippedChordModelSha256
          : '',
      chordFallbackReason: shadow.chordFallbackReason,
    );
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
      shadow: state.shadow,
    );
  }
}

final liveLabProvider = NotifierProvider<LiveLabController, LiveLabState>(
  LiveLabController.new,
);

/// How many times the shadow path has loaded a model asset in this app run.
/// A COUNTER, not a cache: the "flag OFF ⇒ zero extra inference" test reads
/// it, because "no bytes were even loaded" is a stronger and cheaper claim
/// than "an inference ran and its result was dropped".
@visibleForTesting
int debugShadowAssetLoads = 0;

/// The live strum weights the shadow pipeline reproduces production with.
/// Same asset preference order as `RealStrumEngine`; null keeps the
/// heuristic, which the shadow report then records as "candidate
/// unavailable" rather than inventing a verdict.
Future<Uint8List?> _liveStrumWeights() async {
  for (final asset in const [
    'assets/ml/strum_crnn_live_3c.bin',
    'assets/ml/strum_crnn_live.bin',
  ]) {
    try {
      final data = await rootBundle.load(asset);
      debugShadowAssetLoads++;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      // Try the next asset; null (the heuristic) is a valid outcome and is
      // reported, not hidden.
    }
  }
  return null;
}

/// The shipped chord CRNN weights. A missing asset is not swallowed: the
/// runner turns it into `FallbackReason.assetMissing`, which the snapshot
/// carries and the Lab panel shows.
Future<Uint8List?> _chordShadowWeights() async {
  try {
    final data = await rootBundle.load('assets/ml/chord_crnn.bin');
    debugShadowAssetLoads++;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}
