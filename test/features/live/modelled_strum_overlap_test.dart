// MEASUREMENT: what the modelled guitar can and cannot be used to count.
//
// ## Why this file exists
//
// While building the listen-and-repeat timeline measurement
// (`demonstration_preroll_test.dart`) the engine reported **43 onsets for 24 notated
// strokes** — and in BOTH takes, so it was not what that measurement was about. An
// unexplained 79% over-report touching a shipped, scored rung (`mission.dDuUdU` is
// `D DU UDU` in eighths at 80 bpm) is not something to route around.
//
// Three candidates were named and separated by measurement rather than argued:
//
//   1. the eighth-note SPACING is too dense for the detector;
//   2. the LivePipeline layer adds onsets the raw detector does not;
//   3. the STIMULUS produces them, and the engine is only reporting what is there.
//
// It is (3), and the discriminator is below: at the same gap, the same ring ratio and
// the same detector, the additive-harmonic model (`synth.dart`) reports exactly the
// struck count while the Karplus-Strong chord model (`modelled_guitar.dart`) reports
// nearly twice it — and the LivePipeline agrees with the raw detector to the onset in
// every cell, which rules out (2).
//
// ## The mechanism, and how far the claim goes
//
// `addStrummedChord` sums an independent, noise-excited Karplus-Strong voice per
// string per strum. Two strums overlapping means two independently seeded noisy
// voices at the SAME pitch sounding together, and those interfere: the sum gets
// random constructive bursts that look exactly like attacks. The harmonic model's
// voices are deterministic and in phase, so overlapping copies add smoothly and
// produce no new transients.
//
// A real guitar does neither. Re-striking a string RE-EXCITES it — the old vibration
// is largely replaced, not summed alongside a second copy of itself. Both models sum;
// only the noisy one manufactures transients when it does.
//
// **What this therefore does NOT establish**: that the engine counts a real guitar's
// eighth-note strumming correctly. The immune stimulus is immune because it is
// smooth, not because it is realistic, so it cannot clear the engine on real audio.
// That remains open and needs a recording — named in
// `docs/research/real-audio-hearing-probe-2026-09.md`.
//
// **What it does establish, and is the rule to carry forward**: a measurement that
// counts ONSETS must keep `ringSeconds` at or below the gap to the next strum, or it
// is counting the model's own interference. `metronome_click_pollution_test.dart`
// prints `23/16` for exactly this reason; those printed counts are not its claim
// (ADR 0546 rests on chord identity and on clicks with no guitar at all), and its
// stimulus is deliberately left alone so the ADR's numbers stay reproducible.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/superflux_onset_detector.dart';

import '../../support/modelled_guitar.dart';
import '../../support/synth.dart';

/// Eighths at 80 bpm — the spacing of the course's own pattern rung.
const double _gapSec = 0.375;
const int _strums = 12;

List<double> _karplusStrong({required double ringSeconds}) {
  final total = 0.1 + _strums * _gapSec + ringSeconds + 0.5;
  final pcm = List<double>.filled((total * modelledSampleRate).round(), 0);
  for (var i = 0; i < _strums; i++) {
    final added = addStrummedChord(
      pcm,
      'Em',
      atSec: 0.1 + i * _gapSec,
      ringSeconds: ringSeconds,
      down: i.isEven,
      seedBase: 2000 + i * 131,
    );
    expect(added, isTrue, reason: 'Em must have a shipped fingering');
  }
  return pcm;
}

List<double> _additiveHarmonic({required double ringSeconds}) =>
    overlappingStrums(
      lowFirstPerStrum: List.generate(_strums, (i) => i.isEven),
      gapSeconds: _gapSec,
      ringSeconds: ringSeconds,
      sampleRate: modelledSampleRate,
    ).toList();

/// The RAW detector — the layer the adversarial property tests drive directly.
int _rawOnsetCount(List<double> pcm) {
  final detector = SuperFluxOnsetDetector(sampleRate: modelledSampleRate);
  var onsets = 0;
  for (var i = 0; i + detector.window <= pcm.length; i += detector.hop) {
    final frame = Float64List.fromList(pcm.sublist(i, i + detector.window));
    if (detector.processFrame(frame) != null) onsets++;
  }
  return onsets;
}

void main() {
  test(
    'MEASURE: ring ratio, stimulus model, and layer — which one is it?',
    () {
      for (final ratio in const [0.8, 2.0, 2.4]) {
        final ring = _gapSec * ratio;
        final takes = {
          'KS-chord': _karplusStrong(ringSeconds: ring),
          'harmonic': _additiveHarmonic(ringSeconds: ring),
        };
        for (final take in takes.entries) {
          final viaPipeline = strumOnsets(take.value).length;
          final viaDetector = _rawOnsetCount(take.value);
          // ignore: avoid_print — this is the measurement's output.
          print(
            'ring/gap ${ratio.toStringAsFixed(1)} ${take.key.padRight(8)}: '
            'struck $_strums | LivePipeline $viaPipeline | '
            'rawSuperFlux $viaDetector',
          );

          // The layer is not the cause, in any cell. Asserted for every row rather
          // than once, because "the pipeline adds nothing" is the claim that makes
          // every other onset measurement in the suite transferable between layers.
          expect(
            viaPipeline,
            viaDetector,
            reason:
                'the LivePipeline reported a different count from the detector it '
                'wraps, which would mean onset measurements taken at one layer say '
                'nothing about the other',
          );

          if (ratio <= 1.0) {
            // Non-overlapping: both models are exact, so the detector is not being
            // defeated by the SPACING.
            expect(
              viaPipeline,
              _strums,
              reason:
                  '${take.key} at ring <= gap must count exactly, or eighth-note '
                  'spacing alone would be the problem',
            );
          } else if (take.key == 'harmonic') {
            // Overlapping, smooth: still exact. This is the cell that isolates the
            // cause to the stimulus model.
            expect(
              viaPipeline,
              _strums,
              reason:
                  'the additive-harmonic model stayed exact while overlapping, so '
                  'overlap as such does not manufacture onsets',
            );
          } else {
            // Overlapping, noise-excited: inflated. Pinned as a property of the
            // INSTRUMENT so a future caller cannot quietly rediscover it as an
            // engine defect.
            expect(
              viaPipeline,
              greaterThan(_strums),
              reason:
                  'if this stopped inflating, the rule written on '
                  'addStrummedChord would be stale and measurements could safely '
                  'use a longer ring again',
            );
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
