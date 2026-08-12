/// Reduces decoder aliases to the canonical internal spelling.
///
/// This intentionally does not select a display spelling: UI may present the
/// canonical [C#] as [Db] according to its own key-aware policy.
final class ChordLabelNormalizer {
  const ChordLabelNormalizer();

  static const Map<String, String> _flatRoots = <String, String>{
    'Db': 'C#',
    'Eb': 'D#',
    'Gb': 'F#',
    'Ab': 'G#',
    'Bb': 'A#',
  };

  String normalize(String label) {
    final trimmed = label.trim();
    final match = RegExp(r'^([A-G](?:#|b)?)(.*)$').firstMatch(trimmed);
    if (match == null) return trimmed;

    final root = _flatRoots[match.group(1)!] ?? match.group(1)!;
    final suffix = match.group(2)!;
    return '$root${_normalizeQuality(suffix)}';
  }

  static String _normalizeQuality(String suffix) => switch (suffix) {
    '' || 'M' || 'maj' => '',
    'm' || 'min' => 'm',
    final value when value.startsWith('min') => 'm${value.substring(3)}',
    _ => suffix,
  };
}
