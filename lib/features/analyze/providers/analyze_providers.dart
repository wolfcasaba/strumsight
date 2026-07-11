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
  final ClipRecorder _recorder = ClipRecorder();

  @override
  AnalyzeState build() => AnalyzeState.initial;

  /// The recorder, exposed so the UI can poll elapsed time while recording.
  ClipRecorder get recorder => _recorder;

  Future<void> startRecording() async {
    if (state.phase == AnalyzePhase.recording) return;
    state = switch (await _recorder.start()) {
      MicStart.ok => const AnalyzeState(phase: AnalyzePhase.recording),
      MicStart.denied => const AnalyzeState(phase: AnalyzePhase.micDenied),
      MicStart.failed => const AnalyzeState(phase: AnalyzePhase.micError),
    };
  }

  Future<void> stopAndAnalyze() async {
    if (state.phase != AnalyzePhase.recording) return;
    final pcm = await _recorder.stop();
    final sr = _recorder.sampleRate;
    state = const AnalyzeState(phase: AnalyzePhase.analyzing);
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
