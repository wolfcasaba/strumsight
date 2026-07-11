import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progress/model/practice_entry.dart';
import '../../progress/providers/practice_log_provider.dart';
import '../../streak/providers/streak_provider.dart';
import '../../streak/streak_logic.dart';
import '../engine/clip_analyzer.dart';
import '../engine/clip_recorder.dart';
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

/// Top-level so it can run off the UI isolate via [compute] — a long clip is a
/// lot of FFTs and must not jank the UI.
AnalyzeResult _runAnalysis((List<double>, int) args) =>
    const ClipAnalyzer().analyze(args.$1, args.$2);

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
    final sr = _recorder.sampleRate;
    // Off the UI isolate — a 30 s clip is thousands of FFTs.
    final result = await compute(_runAnalysis, (pcm, sr));
    state = AnalyzeState(phase: AnalyzePhase.done, result: result);
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
