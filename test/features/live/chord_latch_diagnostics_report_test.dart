// H3 / L2 (HANDOFF) — "the chord latch does not engage on a Karplus–Strong
// signal". E14-R28 / ADR 0545 D5 does NOT fix that here: fixing it would mean
// moving `chordConfRise`, `chordNoChordScore` or the margin formula, and no
// measurement exists that would justify a new number (Ch14 §12/1).
//
// What this cell does is make the failure MEASURABLE. It drives the real
// pipeline over a deterministic Karplus–Strong chord and RECORDS, per chord
// frame, every value the latch reads: winSim, the best competing similarity,
// the margin, the raw confidence `winSim * (0.5 + 2 * margin)`, the EMA, the
// rise/release comparison, the release-debounce counter, the latch bit and the
// N.C. floor comparison. It prints them as a CSV table.
//
// DELIBERATELY EXPECTATION-FREE: not one assertion here compares a measured
// DSP value against a threshold. A cell that asserted "the latch engages"
// would either encode today's broken behaviour or force a blind retune — both
// are what this round refuses to do. The only assertions are structural (the
// harness really ran, the numbers are finite), so the report can never go
// stale silently. The user's laptop run reads the printed table.
//
// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/recognition/chord_latch_diagnostics.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';

import '../../support/synth.dart';

const _sr = 44100;

/// Streams [signal] through a fresh pipeline and returns one
/// [ChordLatchDiagnostics] per CHORD frame (~93 ms), in order.
List<ChordLatchDiagnostics> measureChordLatch(
  Float64List signal, {
  int chunk = 1024,
}) {
  final pipe = LivePipeline(sampleRate: _sr);
  final rows = <ChordLatchDiagnostics>[];
  var lastIndex = -1;
  for (var i = 0; i < signal.length; i += chunk) {
    final end = (i + chunk < signal.length) ? i + chunk : signal.length;
    pipe.addChunk(signal.sublist(i, end));
    final row = pipe.chordLatchDiagnostics;
    if (row != null && row.frameIndex != lastIndex) {
      lastIndex = row.frameIndex;
      rows.add(row);
    }
  }
  return rows;
}

void _report(String title, List<ChordLatchDiagnostics> rows) {
  print('=== chord-latch diagnostics: $title ===');
  print(ChordLatchDiagnostics.csvHeader);
  for (final row in rows) {
    print(row.toCsvRow());
  }
  if (rows.isEmpty) {
    print('(no chord frames)');
    return;
  }
  double maxOf(double Function(ChordLatchDiagnostics) f) =>
      rows.map(f).reduce((a, b) => a > b ? a : b);
  final latchedFrames = rows.where((r) => r.chordLatched).length;
  final aboveFloor = rows.where((r) => r.winSimOverNoChordFloor > 0).length;
  final tonal = rows.where((r) => r.tonalGatePassed).length;
  print(
    'summary: frames=${rows.length} tonalGatePassed=$tonal '
    'aboveNCFloor=$aboveFloor latchedFrames=$latchedFrames',
  );
  print(
    'summary: maxWinSim=${maxOf((r) => r.winSim).toStringAsFixed(4)} '
    'maxMargin=${maxOf((r) => r.margin).toStringAsFixed(4)} '
    'maxRawConf=${maxOf((r) => r.rawConfidence).toStringAsFixed(4)} '
    'maxEma=${maxOf((r) => r.chordConfEma).toStringAsFixed(4)} '
    'rise=${rows.first.chordConfRise.toStringAsFixed(4)}',
  );
  print(
    'summary: closestApproachToRise='
    '${maxOf((r) => r.emaOverRise).toStringAsFixed(4)} '
    '(negative = the latch never engaged, and by how much)',
  );
}

void _expectFinite(List<ChordLatchDiagnostics> rows, String label) {
  for (final r in rows) {
    for (final v in <double>[
      r.tonalness,
      r.winSim,
      r.secondSim,
      r.margin,
      r.rawConfidence,
      r.noChordScore,
      r.chordConfEma,
      r.winSimOverNoChordFloor,
      r.emaOverRise,
    ]) {
      expect(
        v.isFinite,
        isTrue,
        reason: '$label produced a non-finite diagnostic value',
      );
    }
  }
}

void main() {
  test('H3 report: a Karplus–Strong C-major strum pattern', () {
    final rows = measureChordLatch(
      karplusStrongStrumPattern(
        cMajorFreqs,
        count: 4,
        gapSeconds: 0.6,
        sampleRate: _sr,
      ),
    );
    _report('karplus-strong C major, 4 strums @0.6 s', rows);
    expect(rows, isNotEmpty, reason: 'the harness must produce chord frames');
    _expectFinite(rows, 'karplus-strong');
  });

  test('H3 report: a single sustained Karplus–Strong C-major chord', () {
    final rows = measureChordLatch(
      karplusStrongChord(cMajorFreqs, seconds: 2.5, sampleRate: _sr),
    );
    _report('karplus-strong C major, single 2.5 s chord', rows);
    expect(rows, isNotEmpty);
    _expectFinite(rows, 'karplus-strong sustained');
  });

  test('H3 report: the harmonic-sum reference chord, same voicing', () {
    // The SAME notes as an ideal sum of sine partials — the input the latch
    // was originally tuned against. Printed next to the KS runs so the two can
    // be diffed column by column; this is the whole point of the report.
    final rows = measureChordLatch(
      chordSignal(cMajorFreqs, seconds: 2.5, sampleRate: _sr),
    );
    _report('harmonic-sum C major reference, single 2.5 s chord', rows);
    expect(rows, isNotEmpty);
    _expectFinite(rows, 'harmonic reference');
  });

  test('the harness is deterministic: two runs give identical rows', () {
    Float64List signal() =>
        karplusStrongChord(cMajorFreqs, seconds: 1.2, sampleRate: _sr);
    final a = measureChordLatch(signal());
    final b = measureChordLatch(signal());
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].toCsvRow(), b[i].toCsvRow(), reason: 'row $i');
    }
  });
}
