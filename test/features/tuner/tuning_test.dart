import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/model/guitar_strings.dart';
import 'package:music_theory/features/tuner/model/tuning.dart';

/// Round 89 — alternate tunings (GuitarTuna-class parity). A tuning is a
/// named set of six strings; the tuner's chips + nearest-string mapping
/// follow the SELECTED tuning, not hardwired standard.
void main() {
  test('every preset has six strings, low to high', () {
    for (final t in Tunings.all) {
      expect(t.strings.length, 6, reason: t.id);
      for (var i = 1; i < 6; i++) {
        expect(t.strings[i].midi, greaterThan(t.strings[i - 1].midi),
            reason: '${t.id} must be ordered low→high');
      }
    }
  });

  test('drop D lowers ONLY the 6th string to D2', () {
    final d = Tunings.dropD.strings;
    final s = Tunings.standard.strings;
    expect(d.first.midi, 38);
    expect(d.first.label, 'D2');
    for (var i = 1; i < 6; i++) {
      expect(d[i].midi, s[i].midi);
    }
  });

  test('half-step down drops every string one semitone, labelled in flats',
      () {
    final h = Tunings.halfStepDown.strings;
    final s = Tunings.standard.strings;
    for (var i = 0; i < 6; i++) {
      expect(h[i].midi, s[i].midi - 1);
    }
    expect(h.map((x) => x.label).toList(),
        ['Eb2', 'Ab2', 'Db3', 'Gb3', 'Bb3', 'Eb4']);
  });

  test('DADGAD is D2 A2 D3 G3 A3 D4', () {
    expect(Tunings.dadgad.strings.map((x) => x.midi).toList(),
        [38, 45, 50, 55, 57, 62]);
  });

  test('byId resolves presets and falls back to standard for junk', () {
    expect(Tunings.byId('dropD'), same(Tunings.dropD));
    expect(Tunings.byId('no-such-tuning'), same(Tunings.standard));
  });

  test('nearest honours the given string set — a low D claims the D2 chip',
      () {
    // 73.4 Hz is D2. Under standard tuning the nearest string is E2 (2
    // semitones); under drop D it must be the lowered 6th string itself.
    final std = GuitarStrings.nearest(73.4);
    final drop = GuitarStrings.nearest(73.4, strings: Tunings.dropD.strings);
    expect(std!.label, 'E2');
    expect(drop!.label, 'D2');
  });
}
