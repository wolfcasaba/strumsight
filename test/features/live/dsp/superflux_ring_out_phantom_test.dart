// HEAL E14-R19 / H3 regression guard (ADR 0112 self-heal).
//
// DEFECT (measured on clean main@4e633b80, no round diff involved): a SINGLE
// strum that keeps ringing fires a PHANTOM second onset ~0.63 s after the
// attack. In the app that is a spurious strum arrow and a spurious Learn
// scoring event while the user simply holds the chord.
//
// ROOT CAUSE: the r166 real-data retune dropped SuperFlux `delta` 20 → 12, and
// ring-out beating bumps (measured flux 12.5–16.8) sit right on top of that
// threshold. Magnitude cannot separate them from the soft real attacks the
// retune was bought for — band SPREAD can: at the phantom frames the attack
// rises in 64/64 log-mel bands, the beating bump in 11–13.
//
// HOW IT SURFACED: the randomized property gate
// (`test/property/dsp_property_test.dart`, "random strums — one onset")
// draws stagger 6–14 ms and ring 0.5–0.9 s. 31 of 1458 grid points in that
// exact box double-fire, so ~2 % of CI seeds went red —
// `PROPERTY_SEED=33975939211` scored 17/20 against the ≥18 bar.
//
// THE PIN BELOW IS THE RAW MEASUREMENT: every (lowFirst, staggerMs, seconds)
// triple here is a grid point that actually produced two onsets before the fix,
// enumerated by sweeping the detector at `minRiseBands: 0`. It is RED on the
// pre-fix tree and GREEN after — and it pins the INVARIANT (one strum = one
// onset), not the absence of anything, so it stays valid on both sides of any
// later landing.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/strum_analyzer.dart';
import 'package:strumsight/features/live/engine/dsp/superflux_onset_detector.dart';

import '../../../support/synth.dart';

const _sr = 44100;

/// The 31 measured double-onset grid points (see the file header).
const _phantomGrid = <(bool, double, double)>[
  (true, 8.4, 0.85),
  (true, 8.4, 0.90),
  (true, 11.1, 0.70),
  (true, 11.1, 0.75),
  (true, 11.1, 0.80),
  (true, 11.1, 0.85),
  (true, 11.1, 0.90),
  (true, 12.9, 0.80),
  (true, 12.9, 0.85),
  (true, 12.9, 0.90),
  (true, 13.0, 0.80),
  (true, 13.0, 0.85),
  (true, 13.0, 0.90),
  (false, 8.2, 0.65),
  (false, 8.2, 0.70),
  (false, 8.2, 0.75),
  (false, 8.2, 0.80),
  (false, 8.2, 0.85),
  (false, 8.2, 0.90),
  (false, 8.3, 0.65),
  (false, 8.3, 0.70),
  (false, 8.3, 0.75),
  (false, 8.3, 0.80),
  (false, 8.3, 0.85),
  (false, 8.3, 0.90),
  (false, 11.0, 0.65),
  (false, 11.0, 0.70),
  (false, 11.0, 0.75),
  (false, 11.0, 0.80),
  (false, 11.0, 0.85),
  (false, 11.0, 0.90),
];

List<double> _detectorOnsets({
  required bool lowFirst,
  required double staggerMs,
  required double seconds,
}) {
  final signal = strumSignal(
    lowFirst: lowFirst,
    staggerMs: staggerMs,
    seconds: seconds,
  );
  final det = SuperFluxOnsetDetector(sampleRate: _sr);
  final out = <double>[];
  for (final frame in frames(signal, det.window, det.hop)) {
    final t = det.processFrame(frame);
    if (t != null) out.add(t);
  }
  return out;
}

void main() {
  test('one ringing strum stays ONE onset on every measured phantom point', () {
    final offenders = <String>[];
    for (final (lowFirst, staggerMs, seconds) in _phantomGrid) {
      final onsets = _detectorOnsets(
        lowFirst: lowFirst,
        staggerMs: staggerMs,
        seconds: seconds,
      );
      if (onsets.length != 1) {
        offenders.add(
          'lowFirst=$lowFirst stagger=${staggerMs}ms ring=${seconds}s '
          '-> ${onsets.length} onsets '
          '${onsets.map((t) => t.toStringAsFixed(3)).toList()}',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'ring-out beating fired a phantom onset again — the band-spread gate '
          '(SuperFluxOnsetDetector.minRiseBands) no longer separates a pluck '
          '(64/64 bands) from beating (11–13 bands):\n${offenders.join('\n')}',
    );
  });

  test('the same grid stays ONE event through the full StrumAnalyzer', () {
    // The detector is the trigger, but what the app consumes is StrumEvent —
    // the phantom reached the UI through this path, so pin it here too.
    final offenders = <String>[];
    for (final (lowFirst, staggerMs, seconds) in _phantomGrid) {
      final signal = strumSignal(
        lowFirst: lowFirst,
        staggerMs: staggerMs,
        seconds: seconds,
      );
      final analyzer = StrumAnalyzer(sampleRate: _sr);
      var events = 0;
      for (final frame in frames(
        signal,
        DspConfig.onsetWindow,
        DspConfig.onsetHop,
      )) {
        if (analyzer.process(frame) != null) events++;
      }
      if (events != 1) {
        offenders.add(
          'lowFirst=$lowFirst stagger=${staggerMs}ms ring=${seconds}s '
          '-> $events events',
        );
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the gate does not silence real attacks — recall side of the sweep', () {
    // Counter-weight to the two pins above: a gate that fixed the phantom by
    // detecting nothing would also pass them. Repeated strums must still all
    // fire, and the gate must sit where the measured sweep put it — raising it
    // past 20 cost real recall (87.2 % at 24 vs 89.6 % at 16 on the 2 013
    // labeled Klangio strums), so this pins the ceiling, not just the value.
    expect(
      SuperFluxOnsetDetector(sampleRate: _sr).minRiseBands,
      inInclusiveRange(14, 20),
      reason:
          'below 14 the phantom returns (measured beating peak = 13 bands); '
          'above 20 the gate starts eating soft real attacks',
    );

    final signal = strumPattern(
      lowFirstPerStrum: [true, false, true, false],
      gapSeconds: 0.5,
    );
    final det = SuperFluxOnsetDetector(sampleRate: _sr);
    var fired = 0;
    for (final frame in frames(signal, det.window, det.hop)) {
      if (det.processFrame(frame) != null) fired++;
    }
    expect(fired, 4, reason: 'every real attack must still fire');
  });
}
