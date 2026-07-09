/// An open-position chord fingering: one entry per string, **low-E (6th) → high-E
/// (1st)**. `-1` = muted (×), `0` = open (○), `>0` = fret pressed. Enough to
/// draw a beginner chord diagram (RAG chunk 014 — a learning app must show the
/// shape, not just name the chord).
class ChordShape {
  const ChordShape(this.label, this.frets);

  final String label;

  /// 6 entries, low-E → high-E.
  final List<int> frets;

  int get maxFret => frets.where((f) => f > 0).fold(0, (a, b) => a > b ? a : b);
}

/// The common open chords a beginner meets — covers every chord used by the
/// built-in lessons plus the usual first-position triads and 7ths. Look up by
/// exact label; returns null for shapes we don't have a diagram for yet.
class ChordShapes {
  ChordShapes._();

  static const _map = <String, List<int>>{
    // Major triads.
    'C': [-1, 3, 2, 0, 1, 0],
    'A': [-1, 0, 2, 2, 2, 0],
    'G': [3, 2, 0, 0, 0, 3],
    'E': [0, 2, 2, 1, 0, 0],
    'D': [-1, -1, 0, 2, 3, 2],
    'F': [1, 3, 3, 2, 1, 1],
    // Minor triads.
    'Am': [-1, 0, 2, 2, 1, 0],
    'Em': [0, 2, 2, 0, 0, 0],
    'Dm': [-1, -1, 0, 2, 3, 1],
    // Dominant / major / minor 7ths.
    'C7': [-1, 3, 2, 3, 1, 0],
    'A7': [-1, 0, 2, 0, 2, 0],
    'G7': [3, 2, 0, 0, 0, 1],
    'E7': [0, 2, 0, 1, 0, 0],
    'D7': [-1, -1, 0, 2, 1, 2],
    'B7': [-1, 2, 1, 2, 0, 2],
    'Am7': [-1, 0, 2, 0, 1, 0],
    'Em7': [0, 2, 0, 0, 0, 0],
    'Dm7': [-1, -1, 0, 2, 1, 1],
    'Cmaj7': [-1, 3, 2, 0, 0, 0],
    'Fmaj7': [-1, -1, 3, 2, 1, 0],
    // Suspended.
    'Asus4': [-1, 0, 2, 2, 3, 0],
    'Dsus4': [-1, -1, 0, 2, 3, 3],
  };

  static ChordShape? forLabel(String label) {
    final f = _map[label];
    return f == null ? null : ChordShape(label, f);
  }

  static bool has(String label) => _map.containsKey(label);
}
