import '../../data/importers/song_importer.dart';

/// Small, immutable preview data safe to retain in application state.
final class ImportPreview {
  ImportPreview({
    required this.displayName,
    required this.format,
    List<String> warnings = const <String>[],
    List<ImportPartPreview> parts = const <ImportPartPreview>[],
  }) : warnings = List<String>.unmodifiable(warnings),
       parts = List<ImportPartPreview>.unmodifiable(parts);

  final String displayName;
  final String format;
  final List<String> warnings;
  final List<ImportPartPreview> parts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportPreview &&
          other.displayName == displayName &&
          other.format == format &&
          _sameList(other.warnings, warnings) &&
          _sameList(other.parts, parts);

  @override
  int get hashCode => Object.hash(
    displayName,
    format,
    Object.hashAll(warnings),
    Object.hashAll(parts),
  );

  static bool _sameList<T>(List<T> left, List<T> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
