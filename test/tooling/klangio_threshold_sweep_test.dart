// MEASURE: the live path on the DEPLOYMENT corpus, in situ.
//
//   flutter test test/tooling/klangio_threshold_sweep_test.dart
//   KLANGIO_SPLIT=guitarist4 flutter test test/tooling/klangio_threshold_sweep_test.dart
//   STRUM_3C_ASSET=assets/ml/strum_crnn_live_3c_settled.bin flutter test ...
//
// ## Why this exists, and why it did not for three rounds
//
// Klangio GST-MM-2025 is `recording_<id>_phone.wav` — a PHONE MICROPHONE, which
// `ml/klangio.py` calls "our deployment condition" in its own words. An Android app hears
// the phone mic; GuitarSet is a studio mic array. So this corpus, not GuitarSet, is the one
// a shipping claim has to survive.
//
// ADR 0569 stated that the in-situ version was "not available in this environment: the
// Klangio corpus is NOT ON THE MACHINE", ADR 0571 and ADR 0572 repeated it, and the HANDOFF
// carried "the Klangio in-situ sweep, IF the corpus lands on the machine" for three rounds.
// All of it was wrong: the corpus was in `ml/data/klangio/` (gitignored) nine and a half
// hours before the first of those ADRs was committed, and the `klangio_live70.npz` those
// ADRs measured on was BUILT by reading it (ADR 0576). The oracle-window numbers they
// produced stand — they said they were oracle numbers. The deferral did not.
//
// ## What makes this comparable to the GuitarSet sweep
//
// One instrument: the streaming pass, the settled window, the margin gate, the onset matcher
// and the gate ladder all come from `test/support/live_sweep_harness.dart`, which
// `guitarset_threshold_sweep_test.dart` also drives. A cross-corpus delta whose two sides
// came from two implementations measures the implementations (L269, L682).
//
// ## What this is NOT
//
// * Not an on-device number. Host run, no audio I/O, no thermal budget.
// * Not a NEW-PLAYER number for the shipped asset at the default split. The shipped asset
//   trained on Klangio recordings from all three guitarists (ADR 0573 D1), so the default
//   `all` run reports what the app does on audio the model has largely seen. Use
//   `KLANGIO_SPLIT=guitarist4` for the fold that is player-disjoint for the SETTLED asset —
//   and note it is NOT player-disjoint for the shipped one, which trained on 22 of that
//   guitarist's 27 recordings. There is no split of this corpus that is clean for the
//   shipped asset; its training split cannot produce one.
// * The shipped asset's own `split_by_recording(seed=42)` eval fold is NOT reproducible
//   here: it is numpy's RNG, and restating it in Dart would be a second implementation of a
//   split — the exact error class this file's header is about. Per ADR 0573 it would not be
//   a new-player number anyway.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/core/music/onset_matching.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/ml/crnn_strum_net.dart';
import 'package:strumsight/features/live/engine/ml/live_crnn_classifier.dart';

import '../support/live_sweep_harness.dart';

/// 44.1 kHz mono 16-bit, verified per file rather than assumed.
const int _sampleRate = kSweepSampleRate;

/// The canonical ladder, plus any gate named by `KLANGIO_EXTRA_GATES` (comma-separated).
///
/// Needed because [kSweepGates] is built from the SHIPPED asset's constants, so a candidate
/// asset measured on it is measured at thresholds that are not its own — and "each model at
/// its own class-blind gate" is the rule the Python ladder holds to. The settled asset's own
/// gates are 0.2929 (class_conditional, what its JSON ships) and 0.1245 (class_blind); the
/// canonical rows stay so the two assets still share a COMMON-gate comparison, which is what
/// separates the model from the gate.
///
///     KLANGIO_EXTRA_GATES=0.2929,0.1245 flutter test ...
///
/// Built once — a top-level `final` is lazy in Dart — rather than per read: the ladder is the
/// measurement's identity and must not be able to differ between the tally map and the table.
final List<Gate> _gates = _buildGates();

List<Gate> _buildGates() {
  final extra = Platform.environment['KLANGIO_EXTRA_GATES'];
  if (extra == null || extra.trim().isEmpty) return kSweepGates;
  final parsed = <Gate>[];
  for (final raw in extra.split(',')) {
    final value = double.parse(raw.trim());
    for (final margin in const [true, false]) {
      final gate = (suppress: value, margin: margin);
      // A value-equal duplicate would merge two tallies and print doubled counts — the
      // collision kSweepGates documents. Dropping it here keeps the guard below honest.
      if (!kSweepGates.contains(gate) && !parsed.contains(gate)) {
        parsed.add(gate);
      }
    }
  }
  return [...kSweepGates, ...parsed];
}

/// The asset under test. Defaults to what ships; `STRUM_3C_ASSET` points at a candidate.
///
/// Printed in the header. A table that does not name its asset is how a number from one
/// model gets divided by a number from another and called a gap (L682 §1).
String get _asset =>
    Platform.environment['STRUM_3C_ASSET'] ??
    'assets/ml/strum_crnn_live_3c.bin';

/// One annotated strum: the time and the direction the player actually used.
typedef _Annotated = ({double atSec, StrumDirection direction});

/// Parse a `.strums` file: TAB-separated `time`, `D`|`U`, chord.
///
/// Strict on the direction letter, mirroring `ml/klangio.py::parse_strums`: an unknown
/// letter means the format was misread, and a misread format would mislabel the ground
/// truth rather than fail. Blank lines are skipped.
List<_Annotated> _parseStrums(String text) {
  final out = <_Annotated>[];
  var line = 0;
  for (final raw in text.split('\n')) {
    line++;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final parts = trimmed.split('\t');
    expect(
      parts.length,
      3,
      reason: '.strums line $line: expected 3 TAB fields, got $parts',
    );
    final direction = switch (parts[1]) {
      'D' => StrumDirection.down,
      'U' => StrumDirection.up,
      _ => throw StateError(
        '.strums line $line: unknown direction ${parts[1]}',
      ),
    };
    out.add((atSec: double.parse(parts[0]), direction: direction));
  }
  return out;
}

/// Guitarist id = the LEADING DIGIT of the recording id, the same rule
/// `ml/klangio.py::guitarist_of` uses for leave-one-guitarist-out.
String _guitaristOf(String recordingId) => recordingId.substring(0, 1);

/// `KLANGIO_SPLIT=guitarist4` restricts to the fold that is player-disjoint for the
/// SETTLED asset (ADR 0554 held guitarist '4' out entirely).
bool _inSplit(String recordingId) {
  final split = Platform.environment['KLANGIO_SPLIT'] ?? 'all';
  if (split == 'all') return true;
  expect(
    split,
    'guitarist4',
    reason: 'KLANGIO_SPLIT must be "all" or "guitarist4"',
  );
  return _guitaristOf(recordingId) == '4';
}

/// Tallies for one candidate gate.
///
/// Deliberately narrower than the GuitarSet sweep's `_GateScore`: that one carries columns
/// built to chase a GuitarSet-specific question (the phantom-distance split, the detector
/// lag distribution, the production P(no-strum) comparison against a Python run over the
/// same sweeps). Those are worth porting when a Klangio question asks for them; inventing
/// them now would be columns nobody reads, which this arc has already paid for once
/// (ADR 0568).
final class _Score {
  int kept = 0;
  int onsetTp = 0;
  int onsetFp = 0;
  int onsetFn = 0;
  int settledMissing = 0;

  final Map<StrumDirection, int> tp = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };
  final Map<StrumDirection, int> fp = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };
  final Map<StrumDirection, int> fn = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };
  final Map<StrumDirection, int> stp = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };
  final Map<StrumDirection, int> sfp = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };
  final Map<StrumDirection, int> sfn = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };

  double get onsetF1 => f1(onsetTp, onsetFp, onsetFn);
  double get onsetRecall =>
      onsetTp + onsetFn == 0 ? 0 : onsetTp / (onsetTp + onsetFn);
  double get onsetPrecision =>
      onsetTp + onsetFp == 0 ? 0 : onsetTp / (onsetTp + onsetFp);

  double dirF1(StrumDirection d) => f1(tp[d]!, fp[d]!, fn[d]!);
  double get dirMacroF1 =>
      (dirF1(StrumDirection.down) + dirF1(StrumDirection.up)) / 2;

  double sDirF1(StrumDirection d) => f1(stp[d]!, sfp[d]!, sfn[d]!);
  double get sDirMacroF1 =>
      (sDirF1(StrumDirection.down) + sDirF1(StrumDirection.up)) / 2;
}

void main() {
  final root =
      Platform.environment['KLANGIO_DIR'] ??
      'ml${Platform.pathSeparator}data${Platform.pathSeparator}klangio';
  if (!Directory(root).existsSync()) {
    test('skipped: no Klangio corpus at $root (set KLANGIO_DIR)', () {});
    return;
  }

  test('MEASURE: the live path on the deployment corpus, swept', () {
    expect(
      File(_asset).existsSync(),
      isTrue,
      reason:
          '$_asset must exist — a silent fallback here is the trap the GuitarSet '
          'corpus already caught once (LESSONS L662)',
    );

    // One parse for the whole run: the offline settled pass needs the net directly, and
    // re-parsing a 1.4 MB blob per recording would be the measurement's own bottleneck.
    final settledNet = CrnnStrumNet.parse(
      ByteData.sublistView(File(_asset).readAsBytesSync()),
    );

    final ids =
        Directory(root)
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((n) => n.startsWith('recording_') && n.endsWith('.strums'))
            .map((n) => n.substring('recording_'.length, n.length - 7))
            .where(_inSplit)
            .toList()
          ..sort();
    expect(ids, isNotEmpty);

    final scores = {for (final gate in _gates) gate: _Score()};
    // Two value-equal gates would share one tally and print doubled counts — the
    // collision the harness's [kSweepGates] documents. A table that silently
    // double-counts is worse than a missing row, because nothing in it looks wrong.
    expect(
      scores.length,
      _gates.length,
      reason: 'the gate ladder has value-equal duplicates, so tallies merge',
    );

    var files = 0;
    var annotated = 0;
    var pastAudioEnd = 0;
    var coalesced = 0;
    var totalOnsets = 0;
    final byGuitarist = <String, int>{};

    for (final id in ids) {
      final wav = File(
        '$root${Platform.pathSeparator}recording_${id}_phone.wav',
      );
      final ann = File('$root${Platform.pathSeparator}recording_$id.strums');
      if (!wav.existsSync() || !ann.existsSync()) continue;
      final decoded = WavDecoder.decode(
        Uint8List.fromList(wav.readAsBytesSync()),
      );
      if (decoded == null) continue;
      expect(
        decoded.$2,
        _sampleRate,
        reason: 'recording_$id is ${decoded.$2} Hz, not $_sampleRate',
      );
      final pcm = decoded.$1;

      // Events past the end of the audio are dropped and COUNTED, the same rule
      // `ml/klangio.py` applies when it builds the training windows (`t * SR >= len(pcm)`
      // is skipped). A silently dropped annotation would inflate onset precision.
      final events = _parseStrums(ann.readAsStringSync());
      final inAudio = [
        for (final e in events)
          if (e.atSec * _sampleRate < pcm.length) e,
      ];
      pastAudioEnd += events.length - inAudio.length;
      if (inAudio.isEmpty) continue;

      files++;
      annotated += inAudio.length;
      byGuitarist[_guitaristOf(id)] =
          (byGuitarist[_guitaristOf(id)] ?? 0) + inAudio.length;
      final expectedTimes = [for (final e in inAudio) e.atSec];

      // PER FILE, never hoisted. `LiveCrnnStrumClassifier` owns a `LiveCrnnFrontend` that
      // buffers audio and indexes frames, while each file starts a fresh pipeline whose
      // frame counter restarts at zero — so one shared instance has the model reading
      // windows out of the PREVIOUS file's audio. Measured on GuitarSet: a hoisted
      // instance kept 15 of 10286 onsets at the shipped gate against 3784 in the real run.
      final crnn = LiveCrnnStrumClassifier.tryLoad(
        _asset,
        sampleRate: _sampleRate,
      );
      expect(crnn, isNotNull, reason: 'the weights must parse');
      final pass = heardWithProbs(pcm, crnn!, settledNet);
      coalesced += pass.coalesced;
      totalOnsets += pass.heard.length;

      for (final gate in _gates) {
        final score = scores[gate]!;
        final keptHeard = [
          for (final h in pass.heard)
            if ((h.pNoStrum ?? 0) <= gate.suppress &&
                (!gate.margin || marginConfirms(h)))
              h,
        ];
        score.kept += keptHeard.length;
        final pairs = matchOnsets(expectedTimes, [
          for (final h in keptHeard) h.atSec,
        ], toleranceMs: onsetToleranceMsPrimary * 1.0);
        score.onsetTp += pairs.length;
        score.onsetFp += keptHeard.length - pairs.length;
        score.onsetFn += expectedTimes.length - pairs.length;

        for (final pair in pairs) {
          final truth = inAudio[pair.expected].direction;
          final h = keptHeard[pair.detected];
          final pDown = h.pDown;
          final pUp = h.pUp;
          if (pDown == null || pUp == null) continue;
          final called = pUp > pDown ? StrumDirection.up : StrumDirection.down;
          if (called == truth) {
            score.tp[truth] = score.tp[truth]! + 1;
          } else {
            score.fn[truth] = score.fn[truth]! + 1;
            score.fp[called] = score.fp[called]! + 1;
          }
          // The SETTLED direction on the SAME retained stroke. Existence stays the FAST
          // call's decision (ADR 0559 D2), so this isolates what the second forward buys.
          final sDown = h.sDown;
          final sUp = h.sUp;
          if (sDown == null || sUp == null) {
            score.settledMissing++;
          } else {
            final sCalled = sUp > sDown
                ? StrumDirection.up
                : StrumDirection.down;
            if (sCalled == truth) {
              score.stp[truth] = score.stp[truth]! + 1;
            } else {
              score.sfn[truth] = score.sfn[truth]! + 1;
              score.sfp[sCalled] = score.sfp[sCalled]! + 1;
            }
          }
        }
      }
    }

    final out = StringBuffer()
      ..writeln()
      ..writeln('=== KLANGIO IN SITU (ADR 0576) ===')
      ..writeln('  asset:  $_asset')
      ..writeln('  split:  ${Platform.environment['KLANGIO_SPLIT'] ?? 'all'}')
      ..writeln(
        '  corpus: $files recording(s), $annotated annotated strums, '
        '$totalOnsets SuperFlux onsets',
      )
      ..writeln(
        '  by guitarist: ${(byGuitarist.keys.toList()..sort()).map((g) => '$g=${byGuitarist[g]}').join(', ')}',
      );
    if (pastAudioEnd > 0) {
      out.writeln(
        '  $pastAudioEnd annotated event(s) past the end of the audio — dropped, '
        'as ml/klangio.py does',
      );
    }
    if (coalesced > 0) {
      out.writeln(
        '  $coalesced strum(s) excluded as frame-coalesced (no recoverable time)',
      );
    }
    out
      ..writeln()
      ..writeln(
        '  THE DEPLOYMENT CONDITION, on the path the app actually runs:',
      )
      ..writeln(
        '  suppress  margin   onsetP  onsetR  onsetF1   dirMacro  down    up      '
        'kept',
      );
    for (final gate in _gates) {
      final s = scores[gate]!;
      final label = gate.suppress > 1
          ? 'none'
          : gate.suppress.toStringAsFixed(3);
      out.writeln(
        '  ${label.padRight(9)} ${(gate.margin ? 'on' : 'off').padRight(6)} '
        '${s.onsetPrecision.toStringAsFixed(4)}  '
        '${s.onsetRecall.toStringAsFixed(4)}  '
        '${s.onsetF1.toStringAsFixed(4)}   '
        '${s.dirMacroF1.toStringAsFixed(4)}    '
        '${s.dirF1(StrumDirection.down).toStringAsFixed(4)}  '
        '${s.dirF1(StrumDirection.up).toStringAsFixed(4)}  '
        '${s.kept.toString().padLeft(6)}',
      );
    }
    out
      ..writeln('  (* the first row is what production does today)')
      ..writeln()
      ..writeln(
        '  IN-SITU SETTLED TIER: the same retained strokes, direction decided by the',
      )
      ..writeln(
        '  UNTRUNCATED window while the FAST call still decides existence.',
      )
      ..writeln(
        '  suppress  margin   dirMacro(fast)  dirMacro(settled)   delta   down     '
        'up      missing',
      );
    for (final gate in _gates) {
      final s = scores[gate]!;
      final label = gate.suppress > 1
          ? 'none'
          : gate.suppress.toStringAsFixed(3);
      out.writeln(
        '  ${label.padRight(9)} ${(gate.margin ? 'on' : 'off').padRight(6)} '
        '${s.dirMacroF1.toStringAsFixed(4).padLeft(14)}  '
        '${s.sDirMacroF1.toStringAsFixed(4).padLeft(17)}  '
        '${(s.sDirMacroF1 - s.dirMacroF1).toStringAsFixed(4).padLeft(7)}  '
        '${s.sDirF1(StrumDirection.down).toStringAsFixed(4)}  '
        '${s.sDirF1(StrumDirection.up).toStringAsFixed(4)}  '
        '${s.settledMissing.toString().padLeft(7)}',
      );
    }
    // ignore: avoid_print
    print(out);

    // The measurement must have measured something. No accuracy threshold is asserted:
    // this file reports, and the ADRs decide.
    expect(files, greaterThan(0));
    expect(annotated, greaterThan(0));
    expect(scores[_gates.first]!.onsetTp, greaterThan(0));
  });
}
