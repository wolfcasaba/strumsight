import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/chord_shape.dart';
import 'package:music_theory/features/songs/theory/progressions.dart';

void main() {
  test('every diatonic chord in every supported key has a fingering', () {
    final playable = ChordShapes.allLabels.toSet();
    for (final key in SongKey.all) {
      expect(key.diatonic.length, 6, reason: '${key.name} needs I..vi');
      for (final chord in key.diatonic) {
        expect(playable, contains(chord),
            reason: '${key.name}: $chord has no ChordShapes fingering');
      }
    }
  });

  test('Pop (I–V–vi–IV) resolves correctly per key', () {
    final c = SongKey.all.firstWhere((k) => k.name == 'C');
    final g = SongKey.all.firstWhere((k) => k.name == 'G');
    final pop = ProgressionTemplate.all.firstWhere((p) => p.name == 'Pop');
    expect(pop.chordsFor(c), ['C', 'G', 'Am', 'F']);
    expect(pop.chordsFor(g), ['G', 'D', 'Em', 'C']);
  });

  test("'50s (I–vi–IV–V) in C is the doo-wop turnaround", () {
    final c = SongKey.all.firstWhere((k) => k.name == 'C');
    final fifties = ProgressionTemplate.all.firstWhere((p) => p.name == "'50s");
    expect(fifties.chordsFor(c), ['C', 'Am', 'F', 'G']);
  });

  test('Pachelbel is 8 chords and stays within the diatonic set', () {
    final d = SongKey.all.firstWhere((k) => k.name == 'D');
    final pac =
        ProgressionTemplate.all.firstWhere((p) => p.name == 'Pachelbel');
    final chords = pac.chordsFor(d);
    expect(chords.length, 8);
    expect(chords.toSet().every(d.diatonic.contains), isTrue);
  });

  test('every template degree is a valid 1..6 index', () {
    for (final p in ProgressionTemplate.all) {
      expect(p.degrees.every((deg) => deg >= 1 && deg <= 6), isTrue,
          reason: '${p.name} has an out-of-range degree');
    }
  });
}
