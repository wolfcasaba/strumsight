// The whole point of this file is to exercise the deprecated compatibility
// paths, so the deprecation warning is expected here and only here.
// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';

// Deliberately the OLD paths (SDD Ch2 §10.2 re-export shims).
import 'package:strumsight/features/live/model/chord.dart';
import 'package:strumsight/features/live/model/chord_event.dart';
import 'package:strumsight/features/live/model/strum.dart';
import 'package:strumsight/features/tuner/model/guitar_strings.dart';
import 'package:strumsight/features/tuner/model/tuning.dart';
import 'package:strumsight/features/live/engine/dsp/sliding_framer.dart';

// The canonical paths, to prove the shim resolves to the SAME type — a shim
// that accidentally re-declared a type would compile but split the domain.
import 'package:strumsight/core/music/chord.dart' as core_chord;
import 'package:strumsight/core/music/strum.dart' as core_strum;

/// E01-R10 §10.2 — the old import paths must keep working for one transition
/// period, so a later round can delete the shims deliberately instead of the
/// move breaking consumers that were not migrated yet.
void main() {
  test('the legacy music-model paths still resolve', () {
    const chord = Chord('Am');
    const strum = Strum(direction: StrumDirection.down, confidence: 0.5);
    const event = ChordEvent(chord: chord, confidence: 0.5, seq: 1, timeSec: 0);
    expect(chord.label, 'Am');
    expect(strum.isDown, isTrue);
    expect(event.chord, chord);
  });

  test('the legacy tuning paths still resolve', () {
    expect(Tunings.byId('dropD').strings.first.label, 'D2');
    expect(GuitarStrings.standard, hasLength(6));
  });

  test('the legacy SlidingFramer path still resolves', () {
    final framer = SlidingFramer(window: 2, hop: 1);
    expect(framer.add(const [1, 2]).map((f) => f.toList()), [
      [1, 2],
    ]);
  });

  test('the shim re-exports the canonical type, it does not redeclare it', () {
    // If the shim declared its own Chord/Strum these assignments would not
    // compile — that is the check, the runtime expects are incidental.
    const core_chord.Chord viaCore = Chord('C');
    const core_strum.Strum viaCoreStrum = Strum(
      direction: StrumDirection.up,
      confidence: 1,
    );
    expect(viaCore, const core_chord.Chord('C'));
    expect(viaCoreStrum.isUp, isTrue);
  });
}
