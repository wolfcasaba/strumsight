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

  @override
  bool operator ==(Object other) =>
      other is KeyChange && other.at == at && other.key == key;

  @override
  int get hashCode => Object.hash(at, key);
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

  @override
  bool operator ==(Object other) =>
      other is KeyMap && _listEquals(other.changes, changes);

  @override
  int get hashCode => Object.hashAll(changes);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
