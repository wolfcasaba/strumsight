import 'tempo_map.dart';
import 'song_section.dart';

final class SongMeasure {
  SongMeasure({
    required this.index,
    required this.durationBeats,
    this.displayNumber,
    this.pickup = false,
    this.repeatStart = false,
    this.repeatEndCount,
    this.alternateEnding,
  }) {
    if (index < 0 ||
        durationBeats.ticks <= 0 ||
        (repeatEndCount != null && repeatEndCount! <= 0)) {
      throw SongStructureValidationException('songMeasure.invalid');
    }
  }

  final int index;
  final BeatPosition durationBeats;
  final int? displayNumber;
  final bool pickup;
  final bool repeatStart;
  final int? repeatEndCount;
  final int? alternateEnding;

  @override
  bool operator ==(Object other) =>
      other is SongMeasure &&
      other.index == index &&
      other.durationBeats == durationBeats &&
      other.displayNumber == displayNumber &&
      other.pickup == pickup &&
      other.repeatStart == repeatStart &&
      other.repeatEndCount == repeatEndCount &&
      other.alternateEnding == alternateEnding;

  @override
  int get hashCode => Object.hash(
    index,
    durationBeats,
    displayNumber,
    pickup,
    repeatStart,
    repeatEndCount,
    alternateEnding,
  );
}
