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

  /// Advance one frame with the observed bass+treble chroma pair and return the
  /// stable chord, or null when the path sits in the no-chord state (silence /
  /// noise / rest). Feed zero vectors on a gated/silent frame — the no-chord
  /// floor then wins and the chord decays out over a couple of frames.
  ChordMatch? process(Float64List bass, Float64List treble) {
    final sim = dictionary.score(bass, treble);
    final n = sim.length;

    if (!_seeded) {
      for (var s = 0; s < n; s++) {
        _delta[s] = sim[s];
      }
      _seeded = true;
    } else {
      var bestPrev = _delta[0];
      for (var s = 1; s < n; s++) {
        if (_delta[s] > bestPrev) bestPrev = _delta[s];
      }
      for (var s = 0; s < n; s++) {
        final stay = _delta[s] + selfBonus;
        _delta[s] = sim[s] + (stay > bestPrev ? stay : bestPrev);
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

    if (bestIdx == _noChord) return null;

    // Confidence from THIS frame's evidence (not the accumulated trellis):
    // the reported chord's similarity, sharpened by its margin over the best
    // competing real chord — same shape the template matcher used, so the UI's
    // confidence thresholds keep their meaning.
    final winSim = sim[bestIdx];
    var second = 0.0;
    for (var s = 1; s < n; s++) {
      if (s != bestIdx && sim[s] > second) second = sim[s];
    }
    final margin = winSim <= 0 ? 0.0 : (winSim - second) / winSim;
    final confidence = (winSim * (0.5 + 2 * margin)).clamp(0.0, 1.0);

    return ChordMatch(Chord(dictionary.profiles[bestIdx].label), confidence);
  }

  /// Reset the trellis (new session).
  void reset() {
    for (var s = 0; s < _delta.length; s++) {
      _delta[s] = 0;
    }
    _seeded = false;
  }
}
