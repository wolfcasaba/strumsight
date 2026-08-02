import 'song_id.dart';

enum SongSectionKind {
  intro,
  verse,
  preChorus,
  chorus,
  bridge,
  solo,
  breakdown,
  outro,
  custom,
}

class SongStructureValidationException implements Exception {
  SongStructureValidationException(this.code);
  final String code;
  @override
  String toString() => 'SongStructureValidationException($code)';
}

final class SongSection {
  SongSection({
    required this.id,
    required String name,
    required this.startMeasure,
    required this.endMeasureExclusive,
    this.kind = SongSectionKind.custom,
    this.colorKey,
  }) : name = name.trim() {
    if (this.name.isEmpty ||
        startMeasure < 0 ||
        endMeasureExclusive <= startMeasure) {
      throw SongStructureValidationException('songSection.range.invalid');
    }
  }

  final SongSectionId id;
  final String name;
  final int startMeasure;
  final int endMeasureExclusive;
  final SongSectionKind kind;
  final String? colorKey;
}
