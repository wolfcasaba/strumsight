/// Small, immutable preview data safe to retain in application state.
final class ImportPreview {
  ImportPreview({
    required this.displayName,
    required this.format,
    List<String> warnings = const <String>[],
  }) : warnings = List<String>.unmodifiable(warnings);

  final String displayName;
  final String format;
  final List<String> warnings;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportPreview &&
          other.displayName == displayName &&
          other.format == format &&
          _sameWarnings(other.warnings, warnings);

  @override
  int get hashCode =>
      Object.hash(displayName, format, Object.hashAll(warnings));

  static bool _sameWarnings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
