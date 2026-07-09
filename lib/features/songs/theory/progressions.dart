import 'package:flutter/foundation.dart';

/// A major key the songwriter helper supports, with its six useful diatonic
/// triads in scale-degree order: I, ii, iii, IV, V, vi. (vii° is diminished and
/// out of our open-chord vocabulary, so it's omitted.)
///
/// Chord labels are spelled to match `ChordShapes` exactly (a test asserts every
/// one has a fingering). Keys C, G, D use open shapes; A and E bring in movable
/// minor barres (C#m/G#m) that the diagram renders via its base-fret window.
@immutable
class SongKey {
  const SongKey(this.name, this.diatonic);

  /// Tonic label, e.g. "C" — also the display name of the key.
  final String name;

  /// Exactly 6 labels: [I, ii, iii, IV, V, vi].
  final List<String> diatonic;

  static const all = <SongKey>[
    SongKey('C', ['C', 'Dm', 'Em', 'F', 'G', 'Am']),
    SongKey('G', ['G', 'Am', 'Bm', 'C', 'D', 'Em']),
    SongKey('D', ['D', 'Em', 'F#m', 'G', 'A', 'Bm']),
    SongKey('A', ['A', 'Bm', 'C#m', 'D', 'E', 'F#m']),
    SongKey('E', ['E', 'F#m', 'G#m', 'A', 'B', 'C#m']),
  ];
}

/// A named common chord progression expressed in scale degrees (1-based into a
/// [SongKey]'s diatonic list). Turning it into concrete chords for a chosen key
/// is what powers the one-tap "suggest a progression" helper.
@immutable
class ProgressionTemplate {
  const ProgressionTemplate(this.name, this.degrees, this.roman);

  final String name;

  /// 1-based scale degrees (1..6).
  final List<int> degrees;

  /// Human-readable roman-numeral form, e.g. "I–V–vi–IV".
  final String roman;

  /// Resolve to concrete chord labels for [key].
  List<String> chordsFor(SongKey key) =>
      degrees.map((d) => key.diatonic[d - 1]).toList();

  /// The workhorse progressions of popular music.
  static const all = <ProgressionTemplate>[
    ProgressionTemplate('Pop', [1, 5, 6, 4], 'I–V–vi–IV'),
    ProgressionTemplate("'50s", [1, 6, 4, 5], 'I–vi–IV–V'),
    ProgressionTemplate('Axis', [6, 4, 1, 5], 'vi–IV–I–V'),
    ProgressionTemplate('Folk', [1, 4, 1, 5], 'I–IV–I–V'),
    ProgressionTemplate('Pachelbel', [1, 5, 6, 3, 4, 1, 4, 5],
        'I–V–vi–iii–IV–I–IV–V'),
  ];
}
