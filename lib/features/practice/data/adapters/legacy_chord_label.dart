/// Reduces a legacy chord label to the detector's canonical major/minor
/// vocabulary. Returns null for absent, blank or unparseable labels.
///
/// The Practice V2 chord model is the 24 sharp-spelled major/minor labels
/// exposed by `isCanonicalPracticeChordLabel`. Anything outside that set
/// (extended chords like `Em7`, `Cmaj7`, slash inversions like `G/B`, or
/// hand-edited oddities like `H` / `x`) collapses here:
///
///   * the canonical majmin root+m (`Em`, `G`) round-trips unchanged;
///   * 7ths, sus, add and maj variants reduce to their parent major/minor;
///   * flat / sharp spellings normalise to sharps;
///   * anything unparseable returns `null` so the caller can fall back to a
///     strum-only target — see ADR 0071 §2 for why losing a single label is
///     better than dropping an entire legacy record.
library;

/// Pitch classes (`C=0..B=11`) for every supported root spelling, mapped to
/// the canonical sharp-spelled output name. The lookup table is the single
/// source of truth for enharmonic rewriting.
const Map<String, int> _rootPitchClasses = {
  'C': 0,
  'B#': 0,
  'C#': 1,
  'Db': 1,
  'D': 2,
  'D#': 3,
  'Eb': 3,
  'E': 4,
  'Fb': 4,
  'F': 5,
  'E#': 5,
  'F#': 6,
  'Gb': 6,
  'G': 7,
  'G#': 8,
  'Ab': 8,
  'A': 9,
  'A#': 10,
  'Bb': 10,
  'B': 11,
  'Cb': 11,
};

const List<String> _sharpRootNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Reduces [label] to the canonical 24 maj/min vocabulary, or `null` when
/// the label is absent, blank, or unparseable.
///
/// Algorithm (matches ADR 0071 §2):
///   1. null or blank -> null.
///   2. Drop the slash-bass portion (`G/B` -> `G`).
///   3. Validate the root character (`A`..`G`), with an optional `#`/`b`.
///   4. Trailing suffix starting with `m` (but not `maj`) -> minor; otherwise
///      major.
///   5. Rewrite the root to its sharp spelling.
///   6. Concatenate the suffix (`m` for minor, empty for major).
String? legacyPracticeChordLabel(String? label) {
  if (label == null) return null;
  var trimmed = label.trim();
  if (trimmed.isEmpty) return null;

  final slash = trimmed.indexOf('/');
  if (slash >= 0) {
    trimmed = trimmed.substring(0, slash).trim();
    if (trimmed.isEmpty) return null;
  }

  if (trimmed.codeUnitAt(0) < 0x41 || trimmed.codeUnitAt(0) > 0x47) {
    return null;
  }
  var cursor = 1;
  final rootEnd =
      cursor + 1 <= trimmed.length &&
          (trimmed[cursor] == '#' || trimmed[cursor] == 'b')
      ? 2
      : 1;
  final root = trimmed.substring(0, rootEnd);
  final suffix = trimmed.substring(rootEnd);
  final pitch = _rootPitchClasses[root];
  if (pitch == null) return null;

  final isMinor =
      suffix.isNotEmpty &&
      suffix.codeUnitAt(0) == 0x6d && // 'm'
      !(suffix.length >= 3 && suffix.startsWith('maj'));
  final rootName = _sharpRootNames[pitch];
  return isMinor ? '${rootName}m' : rootName;
}
