import 'dart:typed_data';

import '../strum_direction_classifier.dart';
import 'string_arrival_cue.dart';

/// Shape-informed fusion behind the r139 classifier seam.
///
/// Wraps the shipped classifier ([inner]: the live CRNN, or the heuristic)
/// and, whenever the played VOICING is known ([setVoicing] — the guided
/// modes display the shape, so they know it), lets the chord-shape-informed
/// [StringArrivalCue] speak first. MEASURED on GuitarSet Rock/Funk comping
/// (docs/eval/string-arrival-fusion-2026-09-15.md, 1996 sweeps the live path
/// heard): shipped CRNN alone 46.4 % → "cue whenever it speaks, else CRNN"
/// 62.3 %; on the cue's high tier the CRNN scores 56.5 % where the cue
/// scores 97.7 %. Every confidence gate between those two rules lost
/// coverage without gaining accuracy, so the rule is the simplest one.
///
/// Without a voicing (the free Live mirror) this is a transparent pass-through
/// — bit-identical to the inner classifier. A no-strum suppression by the
/// inner classifier is always honoured (the cue never resurrects an onset the
/// reject head refused; that fusion is unmeasured).
///
/// Audio: keeps a 1 s raw ring fed per hop, exactly like the CRNN front-end,
/// and hands the cue the span it needs at the verdict instant. The verdict is
/// taken ~78 ms after the attack, so the cue runs with [StringArrivalCue.postSec]
/// = 0.075 (validated on GuitarSet at that truncation, same probe).
class ShapeInformedStrumClassifier implements StrumDirectionClassifier {
  ShapeInformedStrumClassifier({
    required this.inner,
    required this.sampleRate,
    this.window = 1024,
    this.hop = 256,
    StringArrivalCue? cue,
  }) : _ring = Float64List(sampleRate),
       cue = cue ?? StringArrivalCue(sampleRate: sampleRate, postSec: 0.075);

  final StrumDirectionClassifier inner;
  final int sampleRate;
  final int window;
  final int hop;
  final StringArrivalCue cue;

  /// Delegated: this wrapper adds a direction CUE, never a second deadline —
  /// the settled tier is entirely the inner classifier's decision (ADR 0556 D3).
  @override
  int? get settleAfterFrames => inner.settleAfterFrames;

  /// r144 attack estimate: the onset frame's start + 2.5 hops.
  static const double attackOffsetFrames = 2.5;

  final Float64List _ring;
  int _end = 0;
  bool _first = true;
  List<double?>? _voicingHz;

  /// Which side produced the last verdict: `'cue'`, `'inner'`, or `null`
  /// before any verdict (diagnostics / wiring proof only).
  String? lastVerdictSource;

  /// The last cue result (diagnostics only).
  StringArrivalResult? lastCueResult;

  /// Per-string fundamentals (Hz, low → high, null = muted) of the shape the
  /// player is expected to hold, or null to disable the cue.
  void setVoicing(List<double?>? hz) => _voicingHz = hz;

  List<double?>? get voicingHz => _voicingHz;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) {
    inner.observe(frame, features);
    if (_first) {
      _append(frame, 0);
      _first = false;
    } else {
      _append(frame, window - hop);
    }
  }

  void _append(Float64List frame, int from) {
    for (var i = from; i < frame.length; i++) {
      _ring[_end % _ring.length] = frame[i];
      _end++;
    }
  }

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) {
    final c = inner.classifyAt(
      onsetFrame: onsetFrame,
      currentFrame: currentFrame,
    );
    final hz = _voicingHz;
    if (c.suppressed || hz == null) {
      lastVerdictSource = 'inner';
      return c;
    }
    final attack = ((onsetFrame + attackOffsetFrames) * hop).round();
    final pre = (cue.preSec * sampleRate).round();
    final post = (cue.postSec * sampleRate).round();
    final available = currentFrame * hop + window;
    final slice = Float64List(pre + post);
    final oldest = _end - _ring.length;
    for (var i = 0; i < slice.length; i++) {
      final abs = attack - pre + i;
      if (abs < 0 || abs < oldest || abs >= available || abs >= _end) continue;
      slice[i] = _ring[abs % _ring.length];
    }
    final r = cue.analyze(slice, pre, hz);
    lastCueResult = r;
    if (r.direction == null) {
      lastVerdictSource = 'inner';
      return c;
    }
    lastVerdictSource = 'cue';
    // No pDown/pUp: the pipeline treats a probability-less verdict as
    // confirmed (the cue already abstained on everything below its ladder).
    return StrumClassification(
      direction: r.direction,
      confidence: r.confidence,
    );
  }
}
