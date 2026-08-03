import '../../domain/models/song_measure.dart';

/// Bounded, unambiguous linear repeat expansion for trainer preview.
final class MusicXmlRepeatExpander {
  const MusicXmlRepeatExpander({this.maxExpandedMeasures = 4096});

  final int maxExpandedMeasures;

  MusicXmlRepeatExpansion expand(List<SongMeasure> measures) {
    final output = <int>[];
    var repeatStart = 0;
    for (var index = 0; index < measures.length; index++) {
      output.add(index);
      if (measures[index].repeatStart) repeatStart = index;
      final count = measures[index].repeatEndCount;
      if (count != null) {
        for (var pass = 1; pass < count; pass++) {
          for (var repeated = repeatStart; repeated <= index; repeated++) {
            if (output.length >= maxExpandedMeasures) {
              return const MusicXmlRepeatExpansion.displayOnly();
            }
            output.add(repeated);
          }
        }
      }
      if (output.length > maxExpandedMeasures) {
        return const MusicXmlRepeatExpansion.displayOnly();
      }
    }
    return MusicXmlRepeatExpansion.expanded(output);
  }
}

final class MusicXmlRepeatExpansion {
  const MusicXmlRepeatExpansion.expanded(this.measureIndexes)
    : isDisplayOnly = false;
  const MusicXmlRepeatExpansion.displayOnly()
    : measureIndexes = const <int>[],
      isDisplayOnly = true;

  final List<int> measureIndexes;
  final bool isDisplayOnly;
}
