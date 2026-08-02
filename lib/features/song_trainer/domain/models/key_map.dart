import 'song_section.dart';
import 'tempo_map.dart';

enum KeyMode { major, minor }

final class KeySignature {
  KeySignature(this.tonic, this.mode) {
    if (tonic < -6 || tonic > 11) {
      throw SongStructureValidationException('keySignature.tonic.invalid');
    }
  }
  final int tonic;
  final KeyMode mode;
  @override
  bool operator ==(Object other) =>
      other is KeySignature && other.tonic == tonic && other.mode == mode;
  @override
  int get hashCode => Object.hash(tonic, mode);
}

final class KeyChange {
  const KeyChange({required this.at, required this.key});
  final BeatPosition at;
  final KeySignature key;
}

final class KeyMap {
  KeyMap(Iterable<KeyChange> changes) : changes = List.unmodifiable(changes) {
    if (this.changes.isEmpty || this.changes.first.at != BeatPosition.zero) {
      throw SongStructureValidationException('keyMap.firstBoundary.invalid');
    }
    for (var i = 1; i < this.changes.length; i++) {
      if (this.changes[i].at <= this.changes[i - 1].at) {
        throw SongStructureValidationException('keyMap.boundaries.invalid');
      }
    }
  }
  factory KeyMap.constant(KeySignature key) =>
      KeyMap([KeyChange(at: BeatPosition.zero, key: key)]);
  final List<KeyChange> changes;
}
