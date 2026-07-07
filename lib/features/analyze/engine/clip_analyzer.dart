import '../../live/engine/dsp/live_pipeline.dart';
import '../../live/model/strum.dart';
import '../model/analyze_result.dart';

/// Runs the REAL Live DSP pipeline over a recorded PCM clip and distils it into
/// a timeline (chord segments + strum marks). Pure and deterministic — the same
/// engine as Live, just batch instead of streaming, so it is fully unit-testable
/// on synthesized audio.
class ClipAnalyzer {
  const ClipAnalyzer({this.chunkSize = 2048});

  /// How many samples to feed per step (mirrors a mic callback size).
  final int chunkSize;

  AnalyzeResult analyze(List<double> pcm, int sampleRate) {
    if (pcm.isEmpty || sampleRate <= 0) return AnalyzeResult.empty;

    final pipeline = LivePipeline(sampleRate: sampleRate);
    final chords = <TimelineChord>[];
    final strums = <TimelineStrum>[];

    String? openLabel;
    double openStart = 0;
    Strum? lastStrum;
    var fed = 0;

    void closeChord(double at) {
      final label = openLabel;
      if (label != null) {
        chords.add(TimelineChord(
          label: label,
          startSec: openStart,
          endSec: at,
        ));
      }
    }

    for (var i = 0; i < pcm.length; i += chunkSize) {
      final end = (i + chunkSize < pcm.length) ? i + chunkSize : pcm.length;
      final chunk = pcm.sublist(i, end);
      fed += chunk.length;
      final t = fed / sampleRate;

      for (final frame in pipeline.addChunk(chunk)) {
        final label = frame.current?.label;
        if (label != null && label != openLabel) {
          closeChord(t);
          openLabel = label;
          openStart = t;
        }
        final s = frame.latestStrum;
        // The pipeline reuses the same Strum instance until a NEW one is
        // detected, so identity marks a genuinely new strum.
        if (s != null && !identical(s, lastStrum)) {
          strums.add(TimelineStrum(
            direction: s.direction,
            timeSec: t,
            confidence: s.confidence,
          ));
          lastStrum = s;
        }
      }
    }

    final duration = pcm.length / sampleRate;
    closeChord(duration);

    // BPM: the pipeline's tempo tracker converges as onsets accrue; derive a
    // stable estimate from the median inter-strum interval when available.
    final bpm = _bpmFromStrums(strums);

    return AnalyzeResult(
      durationSec: duration,
      bpm: bpm,
      chords: chords,
      strums: strums,
    );
  }

  double _bpmFromStrums(List<TimelineStrum> strums) {
    if (strums.length < 2) return 0;
    final intervals = <double>[];
    for (var i = 1; i < strums.length; i++) {
      final dt = strums[i].timeSec - strums[i - 1].timeSec;
      if (dt > 0.05) intervals.add(dt); // ignore near-simultaneous marks
    }
    if (intervals.isEmpty) return 0;
    intervals.sort();
    final median = intervals[intervals.length ~/ 2];
    return median > 0 ? (60 / median).clamp(30, 300).toDouble() : 0;
  }
}
