import 'dart:math' as math;
import 'dart:typed_data';

import '../../model/chord.dart';
import 'chord_dictionary.dart';
import 'chord_matcher.dart' show ChordMatch;

/// Online (token-passing) Viterbi decoder over the chord-profile dictionary
/// (RAG chunk 012) — the principled replacement for round-4's hand-tuned
/// 3-frame hysteresis + instant-switch threshold.
///
/// The trellis score for staying in a state gains a **self-transition bonus**
/// each frame, so a challenger chord must both out-score the incumbent AND
/// persist to flip the report. That single mechanism gives smooth, flicker-free
/// tracking *and* cures the maj↔maj7 blip for free: one frame of stray extra-
/// tone energy can't overcome the bonus.
///
/// Because the switch probability is uniform over the other states, the max
/// over predecessors is `max(stay-in-s, best-of-all)` — O(N) per frame, not
/// O(N²). Scores are renormalised each frame (subtract the max) so the trellis
/// stays bounded during long sustains.
class ViterbiChordDecoder {
  ViterbiChordDecoder({
    ChordDictionary? dictionary,
    this.selfBonus = 0.22,
  }) : dictionary = dictionary ?? ChordDictionary() {
    _delta = Float64List(this.dictionary.length);
  }

  final ChordDictionary dictionary;

  /// Reward (in similarity units, `0..1`) added to a state for persisting. This
  /// is the switch threshold: a rival must beat the incumbent's per-frame
  /// similarity by more than [selfBonus] and hold it to take over. Tune on
  /// device — the one knob that used to be three hand-tuned constants.
  final double selfBonus;

  late final Float64List _delta;
  bool _seeded = false;

  /// Index of the no-chord state (always 0 in [ChordDictionary]).
  static const int _noChord = 0;

  /// Expected-target prior (chunk 016 rec #1 — round 137). In a lesson/song
  /// the target chord is KNOWN, so its trellis score gains a small per-frame
  /// bonus: ambiguous evidence (maj vs maj7, weak thirds) resolves toward the
  /// target, while a genuinely different played chord still out-scores it —
  /// the bonus is far below a real similarity gap, and it is NEVER applied to
  /// the no-chord state (expecting a chord cannot conjure one from silence).
  /// Confidence reporting stays on the RAW similarity (no self-deception).
  static const double expectedPrior = 0.05;
  int _expectedIdx = -1;

  /// Set (or clear with null) the currently expected chord label. Unknown
  /// labels (e.g. a slash chord outside the dictionary) clear the prior.
  void setExpected(String? label) {
    _expectedIdx = label == null
        ? -1
        : dictionary.profiles
            .indexWhere((p) => !p.isNoChord && p.label == label);
  }

  /// Onset-aligned updates (chunk 016 rec #2 — round 138): a strum onset is
  /// the only moment a chord CAN change, so for the next [_onsetBoostFrames]
  /// chord frames the self-transition bonus is scaled by [_onsetBonusScale] —
  /// the decoder switches decisively ON the strum and stays stable between
  /// onsets. Online path only (the batch backtrace already sees the future).
  static const int _onsetBoostFrames = 2; // ~186 ms at the 93 ms chord hop
  static const double _onsetBonusScale = 0.25;
  int _boostLeft = 0;

  /// Tell the decoder a strum onset just happened (called by the pipeline
  /// from the fast path; ~12 ms detection lag vs the 93 ms chord hop).
  void noteOnset() => _boostLeft = _onsetBoostFrames;

  /// Advance one frame with the observed bass+treble chroma pair and return the
  /// stable chord, or null when the path sits in the no-chord state (silence /
  /// noise / rest). Feed zero vectors WITH `gated: true` on a gated/silent
  /// frame — the no-chord floor then wins and the chord decays out over a
  /// couple of frames, but the frame neither consumes the onset boost nor
  /// lowers the incumbent's guard (r142 audit: a gated frame right after an
  /// onset must not cause a chord dropout ON the strum).
  ChordMatch? process(Float64List bass, Float64List treble,
      {bool gated = false}) {
    final sim = dictionary.score(bass, treble);
    final n = sim.length;

    final boosted = _boostLeft > 0 && !gated;
    final bonus = boosted ? selfBonus * _onsetBonusScale : selfBonus;
    if (boosted) _boostLeft--;

    if (!_seeded) {
      for (var s = 0; s < n; s++) {
        _delta[s] = sim[s] + (s == _expectedIdx ? expectedPrior : 0.0);
      }
      _seeded = true;
    } else {
      var bestPrev = _delta[0];
      for (var s = 1; s < n; s++) {
        if (_delta[s] > bestPrev) bestPrev = _delta[s];
      }
      for (var s = 0; s < n; s++) {
        final stay = _delta[s] + bonus;
        _delta[s] = sim[s] +
            (s == _expectedIdx ? expectedPrior : 0.0) +
            (stay > bestPrev ? stay : bestPrev);
      }
    }

    // Renormalise (subtract the max) to keep the trellis bounded, and read off
    // the current best path state.
    var best = _delta[0];
    var bestIdx = 0;
    for (var s = 1; s < n; s++) {
      if (_delta[s] > best) {
        best = _delta[s];
        bestIdx = s;
      }
    }
    for (var s = 0; s < n; s++) {
      _delta[s] -= best;
    }

    return _matchFor(bestIdx, sim);
  }

  /// Full-sequence Viterbi with backtrace (batch — Analyze, chunk 012's last
  /// stage). Takes per-frame bass+treble chroma pairs (pass zero vectors for
  /// silent/gated frames) and returns the globally optimal per-frame chord
  /// path (null = no-chord). Unlike the online [process], evidence AFTER a
  /// frame can veto a transient detour: a 0.1 s blip chord costs two switch
  /// penalties on the global path and loses to staying put — measured, this
  /// removes the junk segments the online path leaves on fast chord changes.
  List<ChordMatch?> decodeBatch(
      List<Float64List> bass, List<Float64List> treble) {
    assert(bass.length == treble.length);
    final t = bass.length;
    if (t == 0) return const [];

    final sims = List<Float64List>.generate(
        t, (i) => dictionary.score(bass[i], treble[i]));
    final path = _viterbiPath(sims, selfBonus);
    return [for (var i = 0; i < t; i++) _matchFor(path[i], sims[i])];
  }

  /// The SAME full-sequence Viterbi as [decodeBatch], but over caller-supplied
  /// per-frame emission [scores] (`N` states each) and a parallel [labels]
  /// list, instead of chroma-cosine similarities. This is the deployment seam
  /// for the ML chord head (r197): the CRNN's per-frame 25-dim log-posteriors
  /// become the emissions and the same self-transition smoothing that cleans
  /// the DSP path cleans the ML path. State 0 is the no-chord state (label
  /// `labels[0]`, conventionally `N.C.`) and decodes to `null`, mirroring
  /// [decodeBatch]. Confidence is the reported class's posterior probability
  /// `exp(score)` (the emissions are log-probabilities), not the DSP
  /// similarity/margin shape.
  ///
  /// [selfBonus] is in the SAME units as [scores]; for log-posteriors that is
  /// the log-domain, a very different scale from the 0..1 cosine [selfBonus]
  /// this class defaults to — callers must pass an explicitly tuned value.
  /// Returns a `List<ChordMatch?>` frame-aligned to [scores].
  List<ChordMatch?> decodeBatchFromScores(
      List<Float64List> scores, List<String> labels,
      {double? selfBonus}) {
    final t = scores.length;
    if (t == 0) return const [];
    assert(labels.length == scores[0].length);
    final path = _viterbiPath(scores, selfBonus ?? this.selfBonus);
    return [
      for (var i = 0; i < t; i++) _matchForLabel(path[i], scores[i], labels)
    ];
  }

  /// Shared full-sequence Viterbi forward pass + backtrace over per-frame
  /// emission [sims] (`N` states each) with a uniform switch model and a
  /// per-frame [selfBonus] persistence reward. Returns the globally optimal
  /// state index per frame. Factored out so [decodeBatch] (chroma cosine) and
  /// [decodeBatchFromScores] (ML posteriors) share ONE verified trellis.
  static Int32List _viterbiPath(List<Float64List> sims, double selfBonus) {
    final t = sims.length;
    final n = sims[0].length;

    // Forward pass. With a uniform switch model the predecessor of a switch
    // is the globally best previous state — one shared backpointer per frame
    // plus a per-state "stayed" bit is the whole trellis.
    final delta = Float64List(n);
    final stayed = List<Uint8List>.generate(t, (_) => Uint8List(n));
    final switchFrom = Int32List(t);
    for (var s = 0; s < n; s++) {
      delta[s] = sims[0][s];
    }
    for (var i = 1; i < t; i++) {
      var bestPrev = delta[0];
      var bestPrevIdx = 0;
      for (var s = 1; s < n; s++) {
        if (delta[s] > bestPrev) {
          bestPrev = delta[s];
          bestPrevIdx = s;
        }
      }
      switchFrom[i] = bestPrevIdx;
      final st = stayed[i];
      final sim = sims[i];
      var maxDelta = double.negativeInfinity;
      for (var s = 0; s < n; s++) {
        final stay = delta[s] + selfBonus;
        if (stay >= bestPrev) {
          st[s] = 1; // ties favour staying (stability)
          delta[s] = sim[s] + stay;
        } else {
          delta[s] = sim[s] + bestPrev;
        }
        if (delta[s] > maxDelta) maxDelta = delta[s];
      }
      for (var s = 0; s < n; s++) {
        delta[s] -= maxDelta; // keep the trellis bounded on long clips
      }
    }

    // Backtrace from the best final state.
    var cur = 0;
    var best = delta[0];
    for (var s = 1; s < n; s++) {
      if (delta[s] > best) {
        best = delta[s];
        cur = s;
      }
    }
    final path = Int32List(t);
    path[t - 1] = cur;
    for (var i = t - 1; i > 0; i--) {
      cur = stayed[i][cur] == 1 ? cur : switchFrom[i];
      path[i - 1] = cur;
    }
    return path;
  }

  /// Confidence from a single frame's evidence (not the accumulated trellis):
  /// the reported chord's similarity, sharpened by its margin over the best
  /// competing real chord — same shape the template matcher used, so the UI's
  /// confidence thresholds keep their meaning.
  ChordMatch? _matchFor(int idx, Float64List sim) {
    if (idx == _noChord) return null;
    final winSim = sim[idx];
    var second = 0.0;
    for (var s = 1; s < sim.length; s++) {
      if (s != idx && sim[s] > second) second = sim[s];
    }
    final margin = winSim <= 0 ? 0.0 : (winSim - second) / winSim;
    final confidence = (winSim * (0.5 + 2 * margin)).clamp(0.0, 1.0);
    return ChordMatch(Chord(dictionary.profiles[idx].label), confidence);
  }

  /// Confidence + label for a state on the ML posterior path: the winning
  /// class's posterior probability `exp(score)` (scores are log-probabilities),
  /// clamped to `0..1`. State 0 (`labels[0]`, N.C.) → null, like [_matchFor].
  ChordMatch? _matchForLabel(int idx, Float64List score, List<String> labels) {
    if (idx == _noChord) return null;
    final confidence = math.exp(score[idx]).clamp(0.0, 1.0);
    return ChordMatch(Chord(labels[idx]), confidence);
  }

  /// Reset the trellis (new session) — including the transient onset boost
  /// and the expected-chord prior: a fresh session must never inherit a past
  /// lesson's bias (the engine re-asserts an ACTIVE hint explicitly).
  void reset() {
    for (var s = 0; s < _delta.length; s++) {
      _delta[s] = 0;
    }
    _seeded = false;
    _boostLeft = 0;
    _expectedIdx = -1;
  }
}
