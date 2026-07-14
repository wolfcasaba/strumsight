import 'dart:typed_data';

import '../../live/engine/dsp/dsp_config.dart';
import '../../live/engine/dsp/live_pipeline.dart';
import '../../live/engine/dsp/nnls_chroma.dart';
import '../../live/engine/dsp/strum_direction_classifier.dart';
import '../../live/engine/dsp/chord_dictionary.dart';
import '../../live/engine/dsp/viterbi_chord_decoder.dart';
import '../../live/model/strum.dart';
import '../model/analyze_result.dart';
import 'chroma_denoise.dart';

/// Re-labels each detected strum's direction at its attack time — the CRNN
/// deployment seam (r165). Given the whole clip and the attack times, returns
/// one verdict per time, in order.
typedef StrumRefiner = List<StrumClassification> Function(
    Float64List pcm, int sampleRate, List<double> onsetTimes);

/// Runs the REAL Live DSP over a recorded PCM clip and distils it into a
/// timeline (chord segments + strum marks). Pure and deterministic — fully
/// unit-testable on synthesized audio.
///
/// Two passes (round 71):
/// - **Strums/tempo** stream through [LivePipeline] exactly like Live.
/// - **Chords** get the batch treatment a recording deserves: NNLS chroma per
///   hop → **full-sequence Viterbi with backtrace** ([ViterbiChordDecoder.
///   decodeBatch]) — the globally optimal path. The online decoder commits as
///   it goes, which on fast chord changes leaves 0.1 s transient segments and
///   can end a clip on a wrong label (measured: C·G·Am·F @0.8 s each gave 7
///   segments ending in Csus4); the batch path yields the clean 4.
class ClipAnalyzer {
  const ClipAnalyzer({
    this.chunkSize = 2048,
    this.strumRefiner,
    this.chromaMedianWindow = 1,
    this.bassWeight,
  });

  /// How many samples to feed per step (mirrors a mic callback size).
  final int chunkSize;

  /// Temporal-median denoise window (in chord hops) applied to the batch
  /// chroma before Viterbi (round 182). 1 = off (unchanged). On FULL-BAND
  /// audio, drum hits and bass passing-notes are transient (1-frame) while
  /// chord tones are sustained, so a per-pitch-class median over a few hops
  /// removes the transients and the spurious chords they cause. Odd, e.g. 5.
  final int chromaMedianWindow;

  /// Bass-register cosine weight for the BATCH chord dictionary (round 182,
  /// null = use `DspConfig.chordBassWeight`). On full-band audio the bass often
  /// plays passing/walking notes that drag the root to the wrong chord; a lower
  /// bass weight leans on the treble (chord) evidence. Treble weight = 1−bass.
  final double? bassWeight;

  /// Optional direction re-labeler (the CRNN, r164 A/B: 86.7 % vs the
  /// heuristic's 38.9 % on real recordings). Null → heuristic labels stand;
  /// a refiner failure also falls back — the model is an upgrade, never a
  /// dependency.
  final StrumRefiner? strumRefiner;

  AnalyzeResult analyze(List<double> pcm, int sampleRate) {
    if (pcm.isEmpty || sampleRate <= 0) return AnalyzeResult.empty;

    final strums = _refine(_strumPass(pcm, sampleRate), pcm, sampleRate);
    final duration = pcm.length / sampleRate;
    final chords = _chordPass(pcm, sampleRate, duration);

    return AnalyzeResult(
      durationSec: duration,
      bpm: _bpmFromStrums(strums),
      chords: chords,
      strums: strums,
    );
  }

  /// Direction refine pass (r165): keep every detected strum's TIME, swap
  /// its direction/confidence for the refiner's verdict. Any refiner failure
  /// keeps the heuristic labels — an analyze must never crash on the model.
  List<TimelineStrum> _refine(
      List<TimelineStrum> strums, List<double> pcm, int sampleRate) {
    final refiner = strumRefiner;
    if (refiner == null || strums.isEmpty) return strums;
    try {
      final verdicts = refiner(
        pcm is Float64List ? pcm : Float64List.fromList(pcm),
        sampleRate,
        [for (final s in strums) s.timeSec],
      );
      if (verdicts.length != strums.length) return strums;
      return [
        for (var i = 0; i < strums.length; i++)
          TimelineStrum(
            // A null verdict = honestly ambiguous → the heuristic label
            // stands (the CRNN softmax never abstains today, but the seam
            // contract allows it).
            direction: verdicts[i].direction ?? strums[i].direction,
            timeSec: strums[i].timeSec,
            confidence: verdicts[i].confidence,
          ),
      ];
    } catch (_) {
      return strums;
    }
  }

  /// Stream the clip through the Live pipeline for strum marks.
  List<TimelineStrum> _strumPass(List<double> pcm, int sampleRate) {
    final pipeline = LivePipeline(sampleRate: sampleRate);
    final strums = <TimelineStrum>[];
    Strum? lastStrum;

    for (var i = 0; i < pcm.length; i += chunkSize) {
      final end = (i + chunkSize < pcm.length) ? i + chunkSize : pcm.length;
      final chunk = pcm.sublist(i, end);

      for (final frame in pipeline.addChunk(chunk)) {
        final s = frame.latestStrum;
        // The pipeline reuses the same Strum instance until a NEW one is
        // detected, so identity marks a genuinely new strum.
        if (s != null && !identical(s, lastStrum)) {
          strums.add(TimelineStrum(
            direction: s.direction,
            // The strum's own attack time (r145): the feed position runs
            // 85–165 ms late with ±40 ms jitter (emit cadence + classify
            // delay), which corrupted fromAnalyze beat quantisation.
            timeSec: frame.latestStrumTime,
            confidence: s.confidence,
          ));
          lastStrum = s;
        }
      }
    }
    return strums;
  }

  /// Batch chord pass: per-hop NNLS chroma → full-sequence Viterbi backtrace
  /// → merge the per-frame path into contiguous segments. Boundaries are
  /// stamped at the deciding frame's window centre.
  List<TimelineChord> _chordPass(
      List<double> pcm, int sampleRate, double duration) {
    const win = DspConfig.nnlsWindow;
    const hop = DspConfig.nnlsHop;
    if (pcm.length < win) return const [];

    final signal = Float64List.fromList(pcm);
    final nc = NnlsChroma(sampleRate: sampleRate);
    final zero = Float64List(12);
    final bassFrames = <Float64List>[];
    final trebleFrames = <Float64List>[];
    final centers = <double>[];

    for (var start = 0; start + win <= signal.length; start += hop) {
      final frame = Float64List.sublistView(signal, start, start + win);
      final chroma = nc.process(frame);
      final tonal =
          chroma != null && nc.lastTonalness >= DspConfig.chordMinTonalness;
      bassFrames.add(tonal ? Float64List.fromList(nc.lastBassChroma) : zero);
      trebleFrames
          .add(tonal ? Float64List.fromList(nc.lastTrebleChroma) : zero);
      centers.add((start + win / 2) / sampleRate);
    }
    if (bassFrames.isEmpty) return const [];

    // Temporal-median denoise (round 182): strip transient drum/passing-note
    // spikes so they can't fake a chord on full-band audio (off at window 1).
    final bass = chromaMedianWindow > 1
        ? ChromaDenoise.temporalMedian(bassFrames, window: chromaMedianWindow)
        : bassFrames;
    final treble = chromaMedianWindow > 1
        ? ChromaDenoise.temporalMedian(trebleFrames, window: chromaMedianWindow)
        : trebleFrames;

    final bw = bassWeight;
    final decoder = ViterbiChordDecoder(
      selfBonus: DspConfig.chordSelfTransitionBonus,
      dictionary: bw == null
          ? null
          : ChordDictionary(
              bassWeight: bw,
              trebleWeight: 1 - bw,
              noChordScore: DspConfig.chordNoChordScore,
            ),
    );
    final path = decoder.decodeBatch(bass, treble);

    final chords = <TimelineChord>[];
    String? openLabel;
    var openStart = 0.0;
    for (var i = 0; i < path.length; i++) {
      final label = path[i]?.chord.label;
      // No-chord frames (rests, gated transitions) sustain the open segment —
      // the timeline shows chord SPANS, and this matches the pre-batch
      // behaviour the UI was built around.
      if (label != null && label != openLabel) {
        if (openLabel != null) {
          chords.add(TimelineChord(
              label: openLabel, startSec: openStart, endSec: centers[i]));
        }
        openLabel = label;
        openStart = centers[i];
      }
    }
    if (openLabel != null) {
      chords.add(TimelineChord(
          label: openLabel, startSec: openStart, endSec: duration));
    }
    return chords;
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
