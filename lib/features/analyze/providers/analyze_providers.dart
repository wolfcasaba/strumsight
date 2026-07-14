import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../live/engine/ml/chord_crnn.dart';
import '../../live/engine/ml/crnn_strum_net.dart';
import '../../live/engine/ml/strum_crnn.dart';
import '../../diagnostics/providers/diagnostics_providers.dart';
import '../../progress/model/practice_entry.dart';
import '../../progress/providers/practice_log_provider.dart';
import '../../settings/providers/lab_mode_provider.dart';
import '../../streak/providers/streak_provider.dart';
import '../../streak/streak_logic.dart';
import '../engine/clip_analyzer.dart';
import '../engine/clip_recorder.dart';
import '../engine/ml_chord_decoder.dart';
import '../model/analyze_result.dart';

enum AnalyzePhase { idle, recording, analyzing, done, micDenied, micError }

@immutable
class AnalyzeState {
  const AnalyzeState({this.phase = AnalyzePhase.idle, this.result});

  final AnalyzePhase phase;
  final AnalyzeResult? result;

  // No copyWith on purpose: it could never CLEAR `result`, silently carrying
  // a stale run forward — every transition constructs its state explicitly.

  static const initial = AnalyzeState();
}

/// Top-level so it can run off the UI isolate via [compute] — a long clip is
/// a lot of FFTs and must not jank the UI. The third element is the CRNN
/// weights asset's bytes (r165: rootBundle is main-isolate-only, so the
/// caller loads them and the isolate parses); null or unparseable → the
/// heuristic labels stand.
AnalyzeResult runClipAnalysis(
    (List<double>, int, Uint8List?, bool, Uint8List?) args) {
  final (pcm, sr, weights, labMode, chordWeights) = args;
  StrumCrnn? crnn;
  if (weights != null) {
    try {
      crnn = StrumCrnn(CrnnStrumNet.parse(ByteData.sublistView(weights)));
    } catch (_) {
      crnn = null; // fall back to the heuristic, never fail an analyze
    }
  }
  final result = ClipAnalyzer(strumRefiner: crnn?.classifyClip).analyze(pcm, sr);

  // Lab mode (r197): ALSO run the ML chord model and attach both timelines +
  // their agreement. Best-effort — the ML path never fails an analyze, and it
  // only runs when the flag is on AND the model asset is present.
  if (labMode && chordWeights != null) {
    try {
      final chordNet = ChordCrnn.parse(ByteData.sublistView(chordWeights));
      final mlChords =
          MlChordDecoder(chordNet).decode(pcm, sr, result.durationSec);
      final agreement = MlChordDecoder.agreementFraction(
          result.chords, mlChords, result.durationSec);
      return result.withDiagnostics(
          MlChordDiagnostics(mlChords: mlChords, agreement: agreement));
    } catch (_) {
      // Diagnostics are a bonus; the DSP result stands unchanged on any error.
    }
  }
  return result;
}

/// The CRNN weights asset, loaded once (null where the asset is absent —
/// e.g. a stripped build — which simply keeps the heuristic path).
Future<Uint8List?> _crnnWeights() async {
  try {
    final data = await rootBundle.load('assets/ml/strum_crnn.bin');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

/// The full-band CHORD CRNN weights asset (r197), loaded once and ONLY when Lab
/// mode is on (null where absent — a stripped build simply skips the ML path).
Future<Uint8List?> _chordWeights() async {
  try {
    final data = await rootBundle.load('assets/ml/chord_crnn.bin');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

/// Drives the Analyze screen: record → analyse (off-thread) → result.
class AnalyzeController extends Notifier<AnalyzeState> {
  /// [recorder] is injectable for tests; defaults to the real one.
  AnalyzeController({ClipRecorder? recorder})
      : _recorder = recorder ?? ClipRecorder();

  final ClipRecorder _recorder;

  /// Whether the Analyze screen is on stage. The round-102 dispose-time
  /// cancel only covered a take already in the `recording` phase; a tab
  /// switch DURING the mic-start handshake slipped past it and the landing
  /// start went live behind another tab (round 114 — hot-mic leak).
  bool _screenAttached = false;

  @override
  AnalyzeState build() => AnalyzeState.initial;

  /// The recorder, exposed so the UI can poll elapsed time while recording.
  ClipRecorder get recorder => _recorder;

  /// Called from the screen's initState.
  void screenAttached() => _screenAttached = true;

  /// Called synchronously from the screen's dispose — touches no provider
  /// state itself; the recording cancel is deferred (the tree is finalizing)
  /// and an in-flight start is aborted by [startRecording] when it lands.
  void screenDetached() {
    _screenAttached = false;
    if (state.phase == AnalyzePhase.recording) {
      Future(cancelRecording);
    }
  }

  Future<void> startRecording() async {
    if (state.phase == AnalyzePhase.recording) return;
    final started = await _recorder.start();
    if (!_screenAttached) {
      // The screen left during the mic handshake — release the take instead
      // of recording invisibly behind another tab (round 114).
      if (started == MicStart.ok) {
        unawaited(_recorder.stop());
        state = AnalyzeState.initial;
      }
      return;
    }
    state = switch (started) {
      MicStart.ok => const AnalyzeState(phase: AnalyzePhase.recording),
      MicStart.denied => const AnalyzeState(phase: AnalyzePhase.micDenied),
      MicStart.failed => const AnalyzeState(phase: AnalyzePhase.micError),
    };
  }

  Future<void> stopAndAnalyze() async {
    if (state.phase != AnalyzePhase.recording) return;
    // Leave `recording` BEFORE the stop-flush await: a deferred
    // cancelRecording firing in that window would double-stop the mic and
    // reset the state under the analysis (round 114, review R2).
    state = const AnalyzeState(phase: AnalyzePhase.analyzing);
    final pcm = await _recorder.stop();
    await _analyze(pcm, _recorder.sampleRate);
  }

  /// Analyze an IMPORTED clip (round 179): the user picks/shares a `.wav` from
  /// their device, the UI decodes it to mono PCM, and it runs through the
  /// identical DSP a mic recording does — no mic involved. Ignored mid-record
  /// (the mic take owns the pipeline) and no-ops on empty audio.
  Future<void> analyzeImported(List<double> pcm, int sampleRate) async {
    if (state.phase == AnalyzePhase.recording) return;
    if (pcm.isEmpty || sampleRate <= 0) return;
    state = const AnalyzeState(phase: AnalyzePhase.analyzing);
    await _analyze(pcm, sampleRate);
  }

  /// Shared tail: run the analysis off the UI isolate, publish the result, and
  /// credit practice if it found real content. Assumes the state is already
  /// `analyzing` (set by the caller before its own awaits).
  Future<void> _analyze(List<double> pcm, int sr) async {
    // Lab mode gates the ML chord path: when OFF, the chord weights aren't even
    // loaded and the isolate does zero extra work (r197).
    final labMode = ref.read(labModeProvider);
    // A fresh analyze clears any prior upload status.
    ref.read(diagnosticsUploadProvider.notifier).reset();
    final chordWeights = labMode ? await _chordWeights() : null;
    // Off the UI isolate — a 30 s clip is thousands of FFTs.
    final result = await compute(runClipAnalysis,
        (pcm, sr, await _crnnWeights(), labMode, chordWeights));
    state = AnalyzeState(phase: AnalyzePhase.done, result: result);
    // Lab mode (r198): package the diagnostics session (ML-vs-DSP events +
    // the recorded clip) and upload it best-effort. Fire-and-forget — the
    // result is already published above; a diagnostics failure never disturbs
    // it (the uploader never throws).
    if (labMode && result.diagnostics != null) {
      unawaited(
          ref.read(diagnosticsUploadProvider.notifier).upload(result, pcm, sr));
    }
    // A completed analysis with real content counts as practice (chunk 013).
    if (result.chords.isNotEmpty || result.strums.isNotEmpty) {
      ref.read(streakProvider.notifier).recordPracticeToday();
      ref.read(practiceLogProvider.notifier).record(PracticeEntry(
            day: StreakLogic.epochDayOf(DateTime.now()),
            source: PracticeSource.analyze,
            seconds: result.durationSec.round(),
            strokes: result.strums.length,
            chords: result.chords.map((c) => c.label).toSet().length,
          ));
    }
  }

  /// Leaving the screen mid-recording: release the MIC and discard the take
  /// (round 102). The controller outlives the screen so finished results
  /// survive tab switches — but a hot mic must not.
  void cancelRecording() {
    if (state.phase != AnalyzePhase.recording) return;
    unawaited(_recorder.stop());
    state = AnalyzeState.initial;
  }

  void reset() => state = AnalyzeState.initial;
}

final analyzeControllerProvider =
    NotifierProvider<AnalyzeController, AnalyzeState>(AnalyzeController.new);
// NOTE: `AnalyzeController.new` still works — the constructor's only
// parameter is optional; tests inject a fake recorder via overrideWith.
