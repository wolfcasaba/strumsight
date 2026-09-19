// MEASUREMENT: what does a LISTEN-AND-REPEAT pre-roll do to the attempt after it?
//
// ## Why this has to be measured before the mode can be played
//
// `RhythmMode.listenAndRepeat` declares `demonstratesFirst: true` and
// `showsArrowRow: false`: the app plays the pattern, the notation stays hidden, and
// the learner plays it back. ADR 0546 already settled that the app cannot play audio
// while it scores — the shipped click produced **15 reported strums from 16 clicks**
// with no guitar in the signal — so demonstration and attempt have to be separated
// in time. That much is arithmetic.
//
// What is NOT arithmetic is the state the pre-roll leaves behind. A
// listen-and-repeat run pushes roughly twenty clicks through the pipeline BEFORE the
// first scored bar: the demonstration's own strokes, then the count-in's beats. The
// onset front end is adaptive — it carries a running threshold, and the chroma front
// end carries a whitening reference mean. Both are fed by whatever came before. So
// the named risk is not bleed across the gap (the gap is bars long); it is that the
// pre-roll **re-tunes the detector on clicks**, and the learner's real strokes are
// then heard against a threshold raised by a sound they are not making.
//
// That failure would be invisible in every test that starts the pipeline at bar 1,
// and it would read to the learner as "I played it and it did not count".
//
// ## The method: one control, one difference
//
// Two takes, identical from bar 1 onward — the SAME modelled performance samples,
// placed at the same absolute times:
//
//   A. the real timeline — demonstration clicks, a silent bar, count-in clicks,
//      then the attempt;
//   B. the control — the same pre-roll length as SILENCE, then the attempt.
//
// If the pre-roll is inert, the engine reports the same strokes at the same times in
// both. Any difference is the pre-roll's effect, and it is measured rather than
// assumed.
//
// The stimulus is the SHIPPED click (`Metronome.buildClickWav`) and the app's own
// chord data (`modelled_guitar.dart`). What this cannot measure is the acoustic
// path: on a device the click leaves a speaker and re-enters a microphone, losing
// level and gaining room. Mixing it straight in is the worst case for a given level,
// which is the right direction for a safety measurement.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_countin.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_grading.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_grid.dart';
import 'package:strumsight/features/learn/audio/metronome.dart';

import '../../support/modelled_guitar.dart';

/// The rung this measures: `D DU UDU` in eighths at 80 bpm, which is the pattern
/// the course already teaches WITH the arrow row (`mission.dDuUdU`). The ear rung
/// asks for the same pattern with the notation withdrawn, so nothing about the
/// playing is new here — only the channel it was learned through.
const double _bpm = 80;
const int _beatsPerBar = 4;
const int _attemptBars = 4;
const List<bool> _struck = [true, false, true, true, false, true, true, true];

/// How many times the app plays the pattern before handing it over.
///
/// Two, not one. The sources on learning a strum pattern by ear describe the first
/// step as zeroing in on the *recurring* rhythmic idea; a single presentation of a
/// one-bar pattern gives nothing to recognise as recurring.
const int _demoBars = 2;

/// One bar of silence between the demonstration and the count-in.
const int _gapBars = 1;

double get _beatSec => 60 / _bpm;
double get _barSec => _beatSec * _beatsPerBar;

/// One eighth-note slot — the closest two strokes can be, and so the ceiling on
/// how long a modelled strum may be left ringing here.
double get _slotSec => _beatSec / RhythmSubdivision.eighth.slotsPerBeat;

/// Where the attempt's bar 1 beat 1 falls on the take's own clock.
double get _attemptStartSec => (_demoBars + _gapBars + 1) * _barSec;

RhythmGrid _grid() =>
    RhythmGrid.pendulum(subdivision: RhythmSubdivision.eighth, struck: _struck);

/// The shipped click, decoded to samples.
List<double> _click({required bool accent}) {
  final wav = accent
      ? Metronome.buildClickWav(freq: 1600, amp: 0.7)
      : Metronome.buildClickWav(freq: 1000, amp: 0.5);
  final decoded = WavDecoder.decode(Uint8List.fromList(wav));
  expect(
    decoded,
    isNotNull,
    reason: 'the shipped click must be a readable WAV',
  );
  expect(decoded!.$2, modelledSampleRate);
  return decoded.$1;
}

void _mix(List<double> pcm, List<double> src, double atSec) {
  final start = (atSec * modelledSampleRate).round();
  for (var i = 0; i < src.length; i++) {
    final at = start + i;
    if (at >= 0 && at < pcm.length) pcm[at] += src[i];
  }
}

/// The whole take, with [withPreRoll] deciding whether the pre-roll SOUNDS.
///
/// The attempt's content and its absolute placement are identical either way, so the
/// two takes differ in exactly one thing.
List<double> _take({required bool withPreRoll}) {
  final grid = _grid();
  final totalSec = _attemptStartSec + _attemptBars * _barSec + 1.0;
  final pcm = List<double>.filled((totalSec * modelledSampleRate).round(), 0);

  if (withPreRoll) {
    // The demonstration: the PATTERN, not a beat. Beat 1 of each demo bar is
    // accented, which is the only metre information a single click timbre can
    // carry. Direction is deliberately not encoded — a pitch that meant "up"
    // would teach a cue that does not exist on a guitar.
    for (var bar = 0; bar < _demoBars; bar++) {
      for (final slot in grid.struckSlots) {
        final atSec =
            bar * _barSec +
            grid.onsetUs(bar: 0, slotIndex: slot.index, bpm: _bpm) / 1e6;
        _mix(pcm, _click(accent: slot.index == 0), atSec);
      }
    }
    // The count-in: the exercise's own metre, on the beat, after the silent bar.
    final countInStart = (_demoBars + _gapBars) * _barSec;
    for (var beat = 0; beat < _beatsPerBar; beat++) {
      _mix(pcm, _click(accent: beat == 0), countInStart + beat * _beatSec);
    }
  }

  // The attempt. The ring is held just under the gap to the next stroke, which is
  // a MEASURED constraint on this instrument and not a stylistic choice: an
  // overlapping Karplus-Strong strum manufactures onsets out of its own
  // interference — 22 reported for 12 struck — and this measurement counts onsets
  // (`modelled_strum_overlap_test.dart`, and the rule on `addStrummedChord`).
  for (var bar = 0; bar < _attemptBars; bar++) {
    for (final slot in grid.struckSlots) {
      final atSec =
          _attemptStartSec +
          grid.onsetUs(bar: bar, slotIndex: slot.index, bpm: _bpm) / 1e6;
      final added = addStrummedChord(
        pcm,
        'Em',
        atSec: atSec,
        ringSeconds: _slotSec * 0.9,
        down: slot.direction == StrumDirection.down,
        seedBase: 2000 + bar * 131 + slot.index * 7,
      );
      expect(added, isTrue, reason: 'Em must have a shipped fingering');
    }
  }
  return pcm;
}

/// Onsets the engine reported, expressed on the EXERCISE timeline where bar 1 beat 1
/// is zero — the same frame of reference the screen and the grader use.
List<int> _exerciseOnsetsUs(List<double> pcm) => [
  for (final atSec in strumOnsets(pcm))
    ((atSec - _attemptStartSec) * 1e6).round(),
];

void main() {
  final grid = _grid();
  final notated = grid.struckSlots.length * _attemptBars;

  test(
    'MEASURE: does an audible pre-roll change what the attempt sounds like?',
    () {
      final real = _exerciseOnsetsUs(_take(withPreRoll: true));
      final control = _exerciseOnsetsUs(_take(withPreRoll: false));

      bool counted(int atUs) => RhythmCountIn.countsTowardAttempt(
        atUs: atUs,
        toleranceUs: rhythmToleranceUs,
      );
      final realScored = real.where(counted).toList();
      final controlScored = control.where(counted).toList();
      final realDropped = real.length - realScored.length;

      // ignore: avoid_print — this is the measurement's output.
      print(
        'notated strokes          : $notated\n'
        'pre-roll ON  : reported ${real.length}, '
        'dropped before bar 1: $realDropped, scored ${realScored.length}\n'
        'pre-roll OFF : reported ${control.length}, '
        'scored ${controlScored.length}',
      );

      // 1. The pre-roll IS heard as strokes — the ADR 0546 finding, reproduced on
      //    this timeline rather than assumed from the other one.
      expect(
        realDropped,
        greaterThan(0),
        reason:
            'if the pre-roll produced no onsets at all, the separation this '
            'timeline is built around would be guarding nothing, and the '
            'measurement behind it would have to be redone',
      );

      // 2. The control counts the attempt EXACTLY, which is what makes the
      //    comparison below readable as a number rather than a ratio. It holds
      //    only because the ring is kept under the stroke gap.
      expect(
        controlScored.length,
        notated,
        reason:
            'with no pre-roll and a non-overlapping ring the engine must report '
            'one onset per notated stroke; anything else means the stimulus, not '
            'the pre-roll, is what this measurement is measuring',
      );

      // 3. Every pre-roll onset lands OUTSIDE the attempt, so the existing
      //    count-in rule is what drops them. No new mechanism is needed.
      expect(
        realScored.length,
        controlScored.length,
        reason:
            'a pre-roll click credited to the attempt would be a stroke the '
            'learner never played',
      );

      // 4. And the attempt itself is heard identically — the adaptive state was
      //    not re-tuned by twenty clicks of pre-roll. This is the claim that
      //    could not be reasoned about, only measured.
      for (
        var i = 0;
        i < math.min(realScored.length, controlScored.length);
        i++
      ) {
        expect(
          (realScored[i] - controlScored[i]).abs(),
          lessThan(5000),
          reason:
              'stroke $i moved by ${(realScored[i] - controlScored[i]).abs()}us '
              'because of the pre-roll; the learner would be graded against a '
              'detector their own demonstration had shifted',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test('the gap bar is what makes the separation hold at this tempo', () {
    // The load-bearing number, stated so a tempo change cannot quietly break it:
    // the last pre-roll sound is the count-in's final beat, one beat before bar 1.
    // That has to be further from zero than the grading tolerance, or a count-in
    // click would be credited as an early beat 1.
    final lastPreRollUs = (-_beatSec * 1e6).round();
    expect(
      lastPreRollUs.abs(),
      greaterThan(rhythmToleranceUs),
      reason:
          'at $_bpm bpm a beat is ${(_beatSec * 1000).round()}ms against a '
          '${rhythmToleranceUs ~/ 1000}ms window',
    );
    // And the demonstration's own last stroke is a further gap bar away, which is
    // why the gap exists at all: without it the demonstration would run straight
    // into the count-in, and with one click timbre a learner could not hear which
    // was which.
    final lastDemoUs = ((_demoBars * _barSec) - _attemptStartSec) * 1e6;
    expect(lastDemoUs.abs(), greaterThan(_barSec * 1e6));
  });
}
