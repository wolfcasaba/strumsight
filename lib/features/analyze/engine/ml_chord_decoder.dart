import 'dart:math' as math;
import 'dart:typed_data';

import '../../live/engine/dsp/cqt_extractor.dart';
import '../../live/engine/dsp/viterbi_chord_decoder.dart';
import '../../live/engine/ml/chord_crnn.dart';
import '../model/analyze_result.dart';

/// The ML chord-recognition path for the Analyze batch pipeline (ship-path
/// step 4, r197). Runs ALONGSIDE the DSP chord path — NOT a replacement — so
/// the two timelines can be diffed in Lab mode (upcoming ML-vs-DSP
/// diagnostics). Gated behind `labModeProvider`: zero work when the flag is
/// off (the caller never constructs this).
///
/// Pipeline: `pcm → CqtExtractor (nFrames,144) → ChordCrnn.infer → per-frame
/// 25-dim posteriors → log(p+eps) emissions → ViterbiChordDecoder
/// .decodeBatchFromScores` → contiguous chord segments.
///
/// **Windowing:** `ChordCrnn.infer` is sequence-length agnostic (its GRU is
/// recurrent, conv is local, BatchNorm uses fixed moving stats), so the WHOLE
/// clip's CQT is decoded in one pass — no fixed-100-frame windowing/stitching
/// is needed even though the model was trained on 100-frame windows. This gives
/// the recurrent layer full context.
///
/// **Hop / alignment:** the ML timeline is time-stamped in seconds from the CQT
/// frame grid — frame `i`'s centre is `i * (CqtExtractor.hop / CqtExtractor.sr)`
/// s (= `i * 2048/22050 ≈ 92.9 ms`, starting at 0). The DSP path
/// ([ClipAnalyzer._chordPass]) hops `DspConfig.nnlsHop` (4096) samples at the
/// INPUT sample rate with a `nnlsWindow/2` centre offset — the same ~92.9 ms
/// cadence at 44.1 kHz but a DIFFERENT frame grid and start offset. The two
/// timelines therefore align in ABSOLUTE TIME (seconds), NOT frame-for-frame by
/// index; agreement is measured by sampling both at the ML hop (see
/// [agreementFraction]).
class MlChordDecoder {
  MlChordDecoder(this._crnn);

  final ChordCrnn _crnn;

  /// The 25 majmin labels, index-aligned to `ml/chords/labels.py`
  /// (0 = N.C., 1..12 = C..B major, 13..24 = C..B minor).
  static const List<String> majmin25Labels = [
    'N.C.',
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
    'Cm', 'C#m', 'Dm', 'D#m', 'Em', 'Fm', 'F#m', 'Gm', 'G#m', 'Am', 'A#m', 'Bm',
  ];

  /// Self-transition bonus for the Viterbi over the CRNN's LOG-posteriors.
  /// This is in the log-probability domain, a wholly different scale from the
  /// DSP path's 0..1 cosine `chordSelfTransitionBonus` (0.22). This value is a
  /// PLACEHOLDER — it MUST be tuned from real ML-vs-DSP diagnostics data once
  /// Lab mode is collecting it (r197 leaves the seam open for that).
  static const double posteriorSelfBonus = 2.0;

  /// log(0) guard added before taking the log of a posterior.
  static const double _eps = 1e-8;

  /// Seconds per CQT frame (the ML chord hop).
  static double get frameHopSec => CqtExtractor.hop / CqtExtractor.sr;

  /// Decode [pcm] (mono, [sampleRate] Hz) into an ML chord timeline spanning
  /// `[0, duration]`. Empty / too-short input → an empty timeline.
  List<TimelineChord> decode(List<double> pcm, int sampleRate, double duration) {
    if (pcm.isEmpty) return const [];
    final f32 = pcm is Float32List ? pcm : Float32List.fromList(pcm);
    final cqt = CqtExtractor().extract(f32, sampleRate);
    if (cqt.isEmpty) return const [];

    // Per-frame 25-dim posteriors → log(p+eps) emissions.
    final post = _crnn.infer(cqt);
    final scores = <Float64List>[
      for (final frame in post)
        Float64List.fromList([for (final p in frame) math.log(p + _eps)]),
    ];

    final path = ViterbiChordDecoder().decodeBatchFromScores(
        scores, majmin25Labels,
        selfBonus: posteriorSelfBonus);

    // Merge the per-frame path into contiguous segments, exactly like the DSP
    // _chordPass: a no-chord (null) frame sustains the open segment; boundaries
    // are stamped at the deciding frame's centre (i * hop).
    final hop = frameHopSec;
    final chords = <TimelineChord>[];
    String? openLabel;
    var openStart = 0.0;
    for (var i = 0; i < path.length; i++) {
      final label = path[i]?.chord.label;
      if (label != null && label != openLabel) {
        if (openLabel != null) {
          chords.add(TimelineChord(
              label: openLabel, startSec: openStart, endSec: i * hop));
        }
        openLabel = label;
        openStart = i * hop;
      }
    }
    if (openLabel != null) {
      chords.add(TimelineChord(
          label: openLabel, startSec: openStart, endSec: duration));
    }
    return chords;
  }

  /// Fraction (0..1) of time-frames (sampled at the ML hop over `[0, duration]`)
  /// where the DSP and ML chord timelines agree, both reduced to the 25-class
  /// majmin space. A pure diagnostic — the DSP dictionary emits richer labels
  /// (`Cmaj7`, `G7`, `Asus4`, ...) than the ML head's majmin, so comparing raw
  /// labels would understate agreement; [majminReduce] folds both first.
  static double agreementFraction(
      List<TimelineChord> dsp, List<TimelineChord> ml, double duration) {
    if (duration <= 0) return 0;
    final hop = frameHopSec;
    final n = (duration / hop).floor();
    if (n <= 0) return 0;
    var agree = 0;
    for (var i = 0; i < n; i++) {
      final t = (i + 0.5) * hop;
      if (majminReduce(_labelAt(dsp, t)) == majminReduce(_labelAt(ml, t))) {
        agree++;
      }
    }
    return agree / n;
  }

  static String? _labelAt(List<TimelineChord> chords, double t) {
    for (final c in chords) {
      if (t >= c.startSec && t < c.endSec) return c.label;
    }
    return null;
  }

  // --- majmin reduction (Dart port of ml/chords/labels.py) ------------------

  static const Map<String, int> _pc = {
    'C': 0, 'B#': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4,
    'Fb': 4, 'F': 5, 'E#': 5, 'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 'Ab': 8,
    'A': 9, 'A#': 10, 'Bb': 10, 'B': 11, 'Cb': 11,
  };
  static const List<String> _names = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  /// Reduce any chord label to its canonical majmin form (`C`..`B`, `Cm`..`Bm`,
  /// or `N.C.`). Mirrors `to_majmin_class`/`class_to_label` in labels.py:
  /// a null/empty/unparseable/no-chord label → `N.C.`.
  static String majminReduce(String? label) {
    if (label == null) return 'N.C.';
    final s = label.trim();
    if (s.isEmpty || s == 'N.C.' || s == 'N' || s == 'NC' || s == 'X') {
      return 'N.C.';
    }
    String root;
    String rest;
    if (s.length >= 2 && (s[1] == '#' || s[1] == 'b')) {
      root = s.substring(0, 2);
      rest = s.substring(2);
    } else {
      root = s.substring(0, 1);
      rest = s.substring(1);
    }
    final pc = _pc[root];
    if (pc == null) return 'N.C.';
    return _isMinorThird(rest) ? '${_names[pc]}m' : _names[pc];
  }

  /// Does the quality suffix carry a MINOR third? (majmin reduction rule —
  /// mirrors `_is_minor_third` in labels.py).
  static bool _isMinorThird(String rest) {
    var r = rest.split('/').first;
    r = r.replaceFirst(RegExp(r'^[-: ]+'), '');
    final low = r.toLowerCase();
    if (low.startsWith('maj') ||
        (r.isNotEmpty && r[0] == 'M' && !low.startsWith('min'))) {
      return false;
    }
    if (low.startsWith('min') ||
        low.startsWith('dim') ||
        low.startsWith('o') ||
        low.contains('hdim')) {
      return true;
    }
    return low.startsWith('m');
  }
}
