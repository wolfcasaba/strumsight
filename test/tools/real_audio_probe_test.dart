// Offline REAL-AUDIO DSP probe — the "run it on real music and see the bugs"
// harness the user asked for (round 176). It streams WAV files through the
// EXACT shipping DSP (LivePipeline + ClipAnalyzer) off-device and prints a
// per-clip report, so we can measure detection quality on real audio between
// physical APK tests.
//
// Inputs (auto-discovered, harness no-ops when absent so CI stays green):
//   ml/corpus/wav/*.wav   — dev corpus: synth voice negatives + any real clips
//                           fetched via ml/corpus/fetch.sh (see that file).
//   ml/data/klangio/recording_*_phone.wav — real guitar phone recordings.
//
// Metrics per clip (Live path, ~15 Hz frames):
//   chordShown%  fraction of frames that DISPLAY a chord (non-null). On a
//                SPEECH/noise clip this should be ~0 (the bug: it isn't).
//   changes/s    chord-label transitions per second — the "jumps around"
//                number. Real guitar is low+stable; speech churns.
//   strums       discrete strums the onset detector fired (false onsets on
//                speech are the false-arrow bug).
// A machine-readable copy lands in ml/corpus/report.json.
//
// HEAVY + DEV-ONLY: this streams the full DSP over dozens of 20 s clips (the
// sweep alone is 64 passes), so it is SKIPPED in the normal `flutter test` and
// in CI. Run it explicitly when tuning the gates on real audio:
//     DSP_PROBE=1 flutter test test/tools/real_audio_probe_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/clip_analyzer.dart';
import 'package:music_theory/features/live/engine/dsp/live_pipeline.dart';

/// Only run the heavy real-audio probe when explicitly requested (dev tuning).
final bool _enabled = Platform.environment['DSP_PROBE'] == '1';

/// The SHIPPED 3-class live strum CRNN (r175) — loaded so the harness measures
/// the on-device strum reality (the heuristic alone fires far more false onsets
/// on speech than the app, which runs this reject model). Null if absent.
Uint8List? _liveCrnn() {
  const p = 'assets/ml/strum_crnn_live_3c.bin';
  return File(p).existsSync() ? File(p).readAsBytesSync() : null;
}

const _corpusDir = 'ml/corpus/wav';
const _klangioDir = 'ml/data/klangio';
const _maxSeconds = 20.0; // cap per clip so the sweep stays fast

/// Minimal 16-bit PCM WAV reader (mono or stereo-averaged), [-1, 1] doubles.
(Float64List, int) _readWav(String path) {
  final b = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(b);
  var off = 12;
  int? sr;
  var channels = 1;
  Float64List? pcm;
  while (off + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(off, off + 4));
    final size = bd.getUint32(off + 4, Endian.little);
    if (id == 'fmt ') {
      channels = bd.getUint16(off + 10, Endian.little);
      sr = bd.getUint32(off + 12, Endian.little);
    } else if (id == 'data') {
      final n = size ~/ (2 * channels);
      pcm = Float64List(n);
      for (var i = 0; i < n; i++) {
        var acc = 0.0;
        for (var c = 0; c < channels; c++) {
          acc += bd.getInt16(off + 8 + 2 * (i * channels + c), Endian.little);
        }
        pcm[i] = acc / channels / 32768.0;
      }
    }
    off += 8 + size + (size & 1);
  }
  return (pcm!, sr!);
}

class _Probe {
  _Probe(this.name, this.kind);
  final String name;
  final String kind; // 'voice' | 'guitar'
  double chordShownPct = 0;
  double changesPerSec = 0;
  int liveStrums = 0;
  int analyzeChords = 0;
  int analyzeStrums = 0;
  double tonalP50 = 0;
  double confP50 = 0;
  double confP90 = 0;
  final Set<String> labels = {};
  Map<String, Object?> toJson() => {
        'name': name,
        'kind': kind,
        'chordShownPct': double.parse(chordShownPct.toStringAsFixed(1)),
        'changesPerSec': double.parse(changesPerSec.toStringAsFixed(2)),
        'liveStrums': liveStrums,
        'analyzeChords': analyzeChords,
        'analyzeStrums': analyzeStrums,
        'tonalP50': double.parse(tonalP50.toStringAsFixed(3)),
        'confP50': double.parse(confP50.toStringAsFixed(3)),
        'confP90': double.parse(confP90.toStringAsFixed(3)),
        'labels': labels.toList()..sort(),
      };
}

_Probe _run(String path, String kind) {
  final (full, sr) = _readWav(path);
  final cap = (sr * _maxSeconds).round();
  final pcm = full.length > cap ? Float64List.sublistView(full, 0, cap) : full;
  final p = _Probe(path.split('/').last, kind);

  // LIVE path — stream in mic-sized chunks, watch what the UI would show.
  // Load the shipped 3-class reject CRNN so the strum count matches on-device.
  final pipe = LivePipeline(sampleRate: sr, crnnWeights: _liveCrnn());
  const chunk = 2048;
  String? prevLabel;
  var changes = 0;
  var frames = 0;
  var shown = 0;
  var lastStrumSeq = 0;
  final tonals = <double>[];
  final confs = <double>[]; // chord-match confidence when a chord IS shown
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = (i + chunk < pcm.length) ? i + chunk : pcm.length;
    for (final f in pipe.addChunk(pcm.sublist(i, end))) {
      frames++;
      final label = f.current?.label;
      tonals.add(pipe.debugTonalness);
      if (label != null) {
        shown++;
        confs.add(pipe.chordConfidence);
        p.labels.add(label);
      }
      if (label != prevLabel) changes++;
      prevLabel = label;
      lastStrumSeq = f.strumSeq;
    }
  }
  final dur = pcm.length / sr;
  p.chordShownPct = frames == 0 ? 0 : 100.0 * shown / frames;
  p.changesPerSec = dur == 0 ? 0 : changes / dur;
  p.liveStrums = lastStrumSeq;
  double pct(List<double> xs, double q) {
    if (xs.isEmpty) return 0;
    final s = [...xs]..sort();
    return s[((s.length - 1) * q).round()];
  }
  p.tonalP50 = pct(tonals, 0.5);
  p.confP50 = pct(confs, 0.5);
  p.confP90 = pct(confs, 0.9);

  // ANALYZE path — the batch timeline.
  final res = const ClipAnalyzer().analyze(pcm.toList(), sr);
  p.analyzeChords = res.chords.length;
  p.analyzeStrums = res.strums.length;
  return p;
}

/// Live-only chordShown% for one clip at a given Schmitt (rise, release, hold).
double _chordShownAt(String path, double rise,
    [double release = 0.22, int hold = 3]) {
  final (full, sr) = _readWav(path);
  final cap = (sr * _maxSeconds).round();
  final pcm = full.length > cap ? Float64List.sublistView(full, 0, cap) : full;
  final pipe = LivePipeline(
      sampleRate: sr,
      crnnWeights: _liveCrnn(),
      chordConfRise: rise,
      chordConfRelease: release,
      chordReleaseHoldFrames: hold);
  const chunk = 2048;
  var frames = 0, shown = 0;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = (i + chunk < pcm.length) ? i + chunk : pcm.length;
    for (final f in pipe.addChunk(pcm.sublist(i, end))) {
      frames++;
      if (f.current != null) shown++;
    }
  }
  return frames == 0 ? 0 : 100.0 * shown / frames;
}

List<(File, String)> _discover() {
  final out = <(File, String)>[];
  final corpus = Directory(_corpusDir);
  if (corpus.existsSync()) {
    for (final f in corpus.listSync().whereType<File>()) {
      if (!f.path.endsWith('.wav')) continue;
      final n = f.path.toLowerCase();
      final voice = n.contains('speech') ||
          n.contains('hum') ||
          n.contains('noise') ||
          n.contains('talk');
      out.add((f, voice ? 'voice' : 'guitar'));
    }
  }
  final klangio = Directory(_klangioDir);
  if (klangio.existsSync()) {
    final wavs = klangio
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_phone.wav'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in wavs.take(8)) {
      out.add((f, 'guitar'));
    }
  }
  return out;
}

void main() {
  test('REAL-AUDIO release-hold sweep — chordShown% vs hold frames', () {
    if (!_enabled) return; // dev-only; set DSP_PROBE=1
    final clips = _discover();
    if (clips.isEmpty) return;
    const holds = [0, 2, 3, 4, 6, 8]; // at rise 0.54 / release 0.22
    // ignore: avoid_print
    print('\n=== RELEASE-HOLD SWEEP: avg chordShown% (rise0.54/rel0.22) ===');
    // ignore: avoid_print
    print('hold    ${holds.map((h) => h.toString().padLeft(6)).join()}');
    for (final kind in ['voice', 'guitar']) {
      final row = <String>[];
      for (final h in holds) {
        final vals = clips
            .where((c) => c.$2 == kind)
            .map((c) => _chordShownAt(c.$1.path, 0.54, 0.22, h))
            .toList();
        final avg =
            vals.isEmpty ? 0.0 : vals.reduce((a, b) => a + b) / vals.length;
        row.add(avg.toStringAsFixed(1).padLeft(6));
      }
      // ignore: avoid_print
      print('${kind.padRight(7)} ${row.join()}');
    }
  });

  test('REAL-AUDIO PROBE — Live+Analyze over corpus & guitar recordings', () {
    if (!_enabled) return; // dev-only; set DSP_PROBE=1
    final probes = <_Probe>[];

    final corpus = Directory(_corpusDir);
    if (corpus.existsSync()) {
      for (final f in corpus.listSync().whereType<File>()) {
        if (!f.path.endsWith('.wav')) continue;
        final n = f.path.toLowerCase();
        final kind = (n.contains('speech') ||
                n.contains('hum') ||
                n.contains('noise') ||
                n.contains('talk'))
            ? 'voice'
            : 'guitar';
        probes.add(_run(f.path, kind));
      }
    }

    final klangio = Directory(_klangioDir);
    if (klangio.existsSync()) {
      final wavs = klangio
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_phone.wav'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in wavs.take(8)) {
        probes.add(_run(f.path, 'guitar'));
      }
    }

    if (probes.isEmpty) {
      // ignore: avoid_print
      print('real_audio_probe: no corpus/klangio audio present — skipped.');
      return;
    }

    // ignore: avoid_print
    print('\n=== REAL-AUDIO PROBE (round 176) ===');
    // ignore: avoid_print
    print('kind    chordShown%  changes/s  strums  tonP50  confP50  confP90  clip');
    for (final p in probes) {
      // ignore: avoid_print
      print('${p.kind.padRight(7)} '
          '${p.chordShownPct.toStringAsFixed(1).padLeft(9)}  '
          '${p.changesPerSec.toStringAsFixed(2).padLeft(8)}  '
          '${p.liveStrums.toString().padLeft(6)}  '
          '${p.tonalP50.toStringAsFixed(3).padLeft(6)}  '
          '${p.confP50.toStringAsFixed(3).padLeft(7)}  '
          '${p.confP90.toStringAsFixed(3).padLeft(7)}  ${p.name}');
    }

    double avg(String kind, double Function(_Probe) sel) {
      final xs = probes.where((p) => p.kind == kind).map(sel).toList();
      return xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
    }

    // ignore: avoid_print
    print('\nVOICE  avg chordShown% = ${avg('voice', (p) => p.chordShownPct).toStringAsFixed(1)}'
        '  (want ~0)   avg changes/s = ${avg('voice', (p) => p.changesPerSec).toStringAsFixed(2)}');
    // ignore: avoid_print
    print('GUITAR avg chordShown% = ${avg('guitar', (p) => p.chordShownPct).toStringAsFixed(1)}'
        '  (want high) avg changes/s = ${avg('guitar', (p) => p.changesPerSec).toStringAsFixed(2)}');

    File('ml/corpus/report.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ')
            .convert(probes.map((p) => p.toJson()).toList()));
  });
}
