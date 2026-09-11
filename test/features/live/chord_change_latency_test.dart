// MEASUREMENT: how long does the engine take to FOLLOW a chord change?
//
// ## Why this has to be measured before a change-timing score can exist
//
// The curriculum's change rungs teach "change without stopping", and the obvious
// next score is "your change arrived N ms late". That number would be the learner's
// lateness PLUS the decoder's own confirmation latency, and a blended figure
// presented as the learner's is exactly the false claim the design forbids — the
// same trap the strum path already has a calibration for, except that a chord
// decision has no measured true onset to correct back to.
//
// So this file measures the engine's half first, on audio where the change happens
// at an instant known by construction. Whether a change-timing score is possible at
// all is a conclusion FROM the number, not a plan the number was collected to
// support: if the latency is large or scattered, the honest outcome is that the app
// does not score change timing, and says so.
//
// What this cannot measure, said plainly: a real player's left hand. These changes
// are instantaneous and perfectly fingered. A real beginner's change is a gradual
// arrival of six strings, and the decoder's behaviour on THAT is not in here.
import 'package:flutter_test/flutter_test.dart';

import '../../support/modelled_guitar.dart';

const double _secondsEach = 2.0;

/// When the engine first CONFIRMS [label] at or after [fromSec], in seconds, or
/// null when it never does.
double? _firstConfirmation(
  List<ChordFrame> frames,
  String label, {
  required double fromSec,
}) {
  for (final frame in frames) {
    if (frame.atSec < fromSec) continue;
    if (frame.isConfirmed && frame.label == label) return frame.atSec;
  }
  return null;
}

/// How long after the strike of chord `index` the engine confirmed it.
double? _followLatencyMs(
  List<ChordFrame> frames,
  List<String> labels,
  int index,
) {
  final struckAt = index * _secondsEach;
  final confirmed = _firstConfirmation(
    frames,
    labels[index],
    fromSec: struckAt,
  );
  if (confirmed == null) return null;
  return (confirmed - struckAt) * 1000;
}

void main() {
  // The four changes the beginner course actually teaches, each as the second
  // chord of a pair so there is a previous shape still ringing to be followed OUT
  // of — a change measured from silence would be easier than any real change.
  const changes = <List<String>>[
    ['Em', 'Am'],
    ['Am', 'D'],
    ['D', 'G'],
    ['G', 'C'],
  ];

  test('MEASURE: the engine\'s own latency in following a chord change', () {
    final latencies = <double>[];
    final missed = <String>[];

    for (final pair in changes) {
      final frames = chordFrames(
        strumSequence(pair, secondsEach: _secondsEach),
      );
      final first = _followLatencyMs(frames, pair, 0);
      final second = _followLatencyMs(frames, pair, 1);
      // ignore: avoid_print
      print(
        '${pair[0]} -> ${pair[1]}: '
        'first confirmed after ${first?.toStringAsFixed(0) ?? "never"} ms, '
        'the CHANGE followed after ${second?.toStringAsFixed(0) ?? "never"} ms',
      );
      if (second == null) {
        missed.add('${pair[0]}->${pair[1]}');
      } else {
        latencies.add(second);
      }
    }

    if (latencies.isNotEmpty) {
      final sorted = latencies.toList()..sort();
      final median = sorted[sorted.length ~/ 2];
      // ignore: avoid_print
      print(
        'FOLLOW LATENCY: median ${median.toStringAsFixed(0)} ms, '
        'range ${sorted.first.toStringAsFixed(0)}-'
        '${sorted.last.toStringAsFixed(0)} ms '
        'over ${latencies.length} of ${changes.length} changes',
      );
    }
    if (missed.isNotEmpty) {
      // ignore: avoid_print
      print('NEVER FOLLOWED: ${missed.join(", ")}');
    }

    // A floor, not a target. The point of this cell is the printed table and the
    // decision it supports; a tight threshold on synthetic audio would fail for
    // reasons that say nothing about a real guitar.
    expect(
      latencies.length,
      greaterThanOrEqualTo(2),
      reason:
          'if the engine cannot follow most of the course changes at all, a '
          'change-timing score is not merely imprecise — it is impossible, and '
          'that is what this measurement is for',
    );
  });

  test('MEASURE: is the latency consistent enough to be corrected for?', () {
    // A systematic lag can be subtracted; a scattered one cannot. This is the
    // same distinction the strum calibration makes with `isStable`, and it is what
    // decides whether "your change was N ms late" can ever be honest.
    final latencies = <double>[];
    for (final pair in changes) {
      final frames = chordFrames(
        strumSequence(pair, secondsEach: _secondsEach),
      );
      final latency = _followLatencyMs(frames, pair, 1);
      if (latency != null) latencies.add(latency);
    }
    if (latencies.length < 2) {
      // ignore: avoid_print
      print('too few followed changes to say anything about spread');
      return;
    }
    final mean = latencies.reduce((a, b) => a + b) / latencies.length;
    final spread = latencies
        .map((l) => (l - mean).abs())
        .reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print(
      'CONSISTENCY: mean ${mean.toStringAsFixed(0)} ms, '
      'worst deviation ${spread.toStringAsFixed(0)} ms',
    );
  });

  test(
    'MEASURE: does the PREVIOUS chord keep being confirmed after the change?',
    () {
      // The failure mode that would make a change-timing score lie in the other
      // direction: if the old shape stays confirmed well into the new bar, a learner
      // who changed on time would be marked late.
      for (final pair in changes) {
        final frames = chordFrames(
          strumSequence(pair, secondsEach: _secondsEach),
        );
        final lastOld = frames
            .where((frame) => frame.isConfirmed && frame.label == pair[0])
            .fold<double?>(null, (latest, frame) => frame.atSec);
        final overhangMs = lastOld == null
            ? null
            : (lastOld - _secondsEach) * 1000;
        // ignore: avoid_print
        print(
          '${pair[0]} -> ${pair[1]}: the old shape was last confirmed '
          '${overhangMs == null ? "never" : "${overhangMs.toStringAsFixed(0)} ms"} '
          'after the change',
        );
      }
    },
  );
}
