import 'dart:math' as math;
import 'dart:typed_data';

/// A chord vocabulary entry: a 24-dim **profile** (bass 12 + treble 12) that a
/// whole observed chord frame is compared against (RAG chunk 012).
///
/// This is the fix for the round-26 extended-chord failure. Note-templates make
/// a 7th a *superset* of its triad (Cmaj7 ⊇ C) so a superset always scores ≥ the
/// subset; a chord PROFILE instead asks "does the 7th's evidence actually match"
/// — Cmaj7 and C differ specifically in the treble B weight, so the added tone
/// has to be *present* to win, not merely allowed.
class ChordProfile {
  ChordProfile._(
      this.label, this.isNoChord, this._bass, this._treble, this.bias);

  /// Display label, e.g. `C`, `Am`, `G7`, `Cmaj7`, `Dm7`, `Asus4`, `E5`,
  /// or `N.C.` for the no-chord state.
  final String label;

  /// The no-chord state — a flat profile with a small scoring boost so
  /// silence/noise resolves here rather than to a random chord.
  final bool isNoChord;

  final Float64List _bass; // L2-unit, 12
  final Float64List _treble; // L2-unit, 12

  /// Occam prior: a small similarity handicap on richer (4-note) chords so an
  /// extension must be *clearly* present to beat its parent triad, not merely
  /// win by the faint phantom 7th that a major third's own overtone leaves
  /// behind (chunk 012). Zero for triads.
  final double bias;

  /// Similarity of an observed (bass, treble) chroma pair to this profile:
  /// a [bassWeight]/[trebleWeight]-blended cosine in `0..1`, minus the [bias]
  /// handicap. The no-chord profile returns [ChordDictionary.noChordScore]
  /// regardless of input.
  double similarity(
    Float64List bass,
    Float64List treble, {
    required double bassWeight,
    required double trebleWeight,
  }) {
    if (isNoChord) return 0; // handled by the dictionary's no-chord floor
    final b = _dot(_bass, bass);
    final t = _dot(_treble, treble);
    final blended =
        (bassWeight * b + trebleWeight * t) / (bassWeight + trebleWeight);
    final s = blended - bias;
    return s < 0 ? 0 : s;
  }

  static double _dot(Float64List a, Float64List b) {
    var s = 0.0;
    for (var i = 0; i < 12; i++) {
      s += a[i] * b[i];
    }
    return s < 0 ? 0 : s;
  }
}

/// The chord-profile dictionary + the frame-wise scorer (RAG chunk 012).
///
/// Vocabulary = root × quality, plus a no-chord state. Per Chordino we start
/// small (maj, min, dom7, maj7, min7, sus4, sus2, power5) and can grow. Each
/// quality is defined by its chord-tone semitone offsets and the relative
/// weight each tone carries in the *treble* profile; the *bass* profile is
/// root-heavy (with a little fifth) because the bass note is the root.
class ChordDictionary {
  ChordDictionary({
    this.bassWeight = 0.35,
    this.trebleWeight = 0.65,
    this.noChordScore = 0.55,
    this.extensionPenalty = 1.0,
  }) {
    _build();
  }

  /// How much the bass-register cosine counts vs the treble-register cosine.
  final double bassWeight;
  final double trebleWeight;

  /// Constant similarity assigned to the no-chord state. A frame only beats
  /// N.C. once a real chord's blended cosine clears this floor, so diffuse /
  /// silent frames resolve to N.C. instead of a random chord (chunk 012's
  /// "no-chord boost").
  final double noChordScore;

  /// Global scale on the per-quality Occam biases (1.0 = use them as tabled) —
  /// the prior that keeps a plain triad from being renamed a 7th by phantom
  /// overtone energy. Set to 0 to disable all handicaps. See [ChordProfile.bias].
  final double extensionPenalty;

  static const _pitchClasses = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  /// Quality → (suffix, chord-tone offsets, matching treble weights, Occam
  /// bias). The third and the seventh carry full weight so a maj↔maj7 or
  /// maj↔min decision hinges on the tone that actually distinguishes them; the
  /// fifth is lighter because it is the most often omitted / octave-doubled
  /// tone.
  //
  // Chordino's conservative starter set (chunk 012): maj, min, dom7, maj7,
  // min7, sus4 + N.C. — grow later. We deliberately EXCLUDE power-5 and sus2:
  // a `[root, fifth]` power profile has no third to contradict, so it "steals"
  // any triad whose third is quiet (the round-26 failure), and sus2 collides
  // with a neighbouring root's fifth. Add them back only with real-guitar data.
  //
  // The per-quality Occam bias (last field) is the similarity handicap that
  // stops phantom overtone energy from renaming a triad. A MAJOR third's 3rd
  // harmonic lands a *major* 7th above the root, and a MINOR third's lands a
  // *minor* 7th — so maj7/m7 need a firm handicap, whereas a played dom7 (whose
  // minor 7th has no such strong phantom source) needs almost none or real
  // A7/B7 voicings would collapse to the bare triad.
  static const _qualities = <List<Object>>[
    ['', [0, 4, 7], [1.0, 1.0, 0.7], 0.0], // major
    ['m', [0, 3, 7], [1.0, 1.0, 0.7], 0.0], // minor
    ['7', [0, 4, 7, 10], [1.0, 0.9, 0.6, 0.9], 0.02], // dominant 7
    ['maj7', [0, 4, 7, 11], [1.0, 0.9, 0.6, 0.9], 0.055], // major 7
    ['m7', [0, 3, 7, 10], [1.0, 0.9, 0.6, 0.9], 0.055], // minor 7
    // sus4 gets a real Occam handicap (round 181): with bias 0.0 it had NO
    // guard, so on real audio a stray 4th (an adjacent chord's ring-out, a
    // bass note, another instrument) flipped D→Dsus4 / G→Gsus4 (MEASURED on
    // the SoundCloud probe). A genuine, sustained sus4 (root+4th+5th all clearly
    // present) still beats the triad by far — the `C+F+G → Csus4` unit test
    // holds — but a faint passing 4th no longer renames a plain triad.
    ['sus4', [0, 5, 7], [1.0, 1.0, 0.7], 0.04], // suspended 4
    // dim/aug (round 78): they differ from m/maj only in the FIFTH — the
    // lightest chord tone — so the altered fifth carries FULL weight here
    // (it IS the distinguishing evidence) and a small rarity bias keeps
    // ambiguous frames on the common triads. Gated by the multi-seed
    // property suite (no stealing measured).
    ['dim', [0, 3, 6], [1.0, 1.0, 0.9], 0.02], // diminished
    ['aug', [0, 4, 8], [1.0, 1.0, 0.9], 0.02], // augmented
  ];

  late final List<ChordProfile> _profiles;

  /// All vocabulary entries; index 0 is the no-chord state.
  List<ChordProfile> get profiles => _profiles;

  int get length => _profiles.length;

  void _build() {
    _profiles = [];
    // Index 0: no-chord (flat unit profiles).
    final flat = Float64List(12)..fillRange(0, 12, 1 / math.sqrt(12));
    _profiles.add(ChordProfile._('N.C.', true, flat, flat, 0));

    for (final q in _qualities) {
      final suffix = q[0] as String;
      final offsets = (q[1] as List).cast<int>();
      final weights = (q[2] as List).cast<num>();
      final bias = (q[3] as num).toDouble() * extensionPenalty;
      for (var root = 0; root < 12; root++) {
        final treble = Float64List(12);
        for (var i = 0; i < offsets.length; i++) {
          treble[(root + offsets[i]) % 12] += weights[i].toDouble();
        }
        // Bass profile: root-heavy, a little fifth (a common bass alternative).
        final bass = Float64List(12);
        bass[root] += 1.0;
        bass[(root + 7) % 12] += 0.3;
        _l2(treble);
        _l2(bass);
        _profiles.add(ChordProfile._(
            _pitchClasses[root] + suffix, false, bass, treble, bias));
      }
    }
  }

  /// Score every profile against one observed (bass, treble) chroma pair.
  /// Returns a same-length list of similarities aligned to [profiles]; the
  /// no-chord entry is filled with [noChordScore].
  Float64List score(Float64List bass, Float64List treble) {
    final out = Float64List(_profiles.length);
    for (var i = 0; i < _profiles.length; i++) {
      final p = _profiles[i];
      out[i] = p.isNoChord
          ? noChordScore
          : p.similarity(bass, treble,
              bassWeight: bassWeight, trebleWeight: trebleWeight);
    }
    return out;
  }

  static void _l2(Float64List v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm <= 0) return;
    for (var i = 0; i < v.length; i++) {
      v[i] /= norm;
    }
  }
}
