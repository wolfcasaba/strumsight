// Cost of one strum-direction CRNN forward pass, and what the settled tier adds.
//
// Why this exists (E18-R41). ADR 0563 measured the settled tier's BENEFIT
// (+0.0551 direction macro-F1, held out) and its RELATIVE cost (a second forward
// on 19.8 % of strokes once routed by margin), but left the absolute cost as
// "~29 ms on a JIT test harness, which is not an on-device figure". That is an
// upper bound masquerading as a data point, exactly the confusion ADR 0474 exists
// to prevent — so the number belongs in the benchmark record, with its `kind`
// stated, not in prose.
//
// It also resolves a contradiction. `crnn_strum_net.dart`'s own header claims the
// net is "~350k params / ~1 ms per window". The JIT harness measured ~29 ms, 29x
// that. One of the two is wrong about the shipped path's cost, and the difference
// decides whether the direction model is a rounding error or the dominant DSP
// cost.
//
// Pure Dart on purpose (no Flutter import), so the same file can run two ways:
//
//   flutter test --reporter expanded tool/benchmarks/strum_direction_forward_benchmark.dart
//   dart compile exe tool/benchmarks/strum_direction_forward_benchmark.dart -o bench.exe && ./bench.exe
//
// The first is the repo's existing convention and comparable to the other
// `ci_host` records. The second is AOT, which is what actually ships, and is the
// tighter bound on a phone — still x86 desktop, so NOT an on-device number.
//
// Usage: [--asset=path] [--iterations=N] [--json=out.json] [--sha=abcdef]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:strumsight/features/live/engine/ml/crnn_strum_net.dart';
import 'benchmark_record.dart';

/// Window shape the live model consumes: 15 log-mel rows of 128 mels
/// (`CrnnFrontend.preFrames + postFrames`, `LogMelExtractor` mel count).
const int _rows = 15;
const int _mels = 128;

/// Two tempos, because the load is LINEAR in strokes per second and one figure
/// invites the wrong conclusion. 200 bpm sixteenths is the stress case the onset
/// detector is tuned for (`strum_analyzer.dart` cites ~75 ms between strokes);
/// 80 bpm eighths is a beginner practising.
const Map<String, double> _strokesPerSecond = <String, double>{
  '200 bpm sixteenths (stress)': 200 * 4 / 60,
  '80 bpm eighths (beginner)': 80 * 2 / 60,
};

/// Multiply-accumulates in one forward, derived from the layer shapes in
/// `crnn_strum_net.dart` and the asset's own tensors. Reported because the gap
/// between this and the PARAMETER count is the whole explanation for the latency:
///
///   conv1  15x128x16 outputs x 9          =  0.28 M   (then maxpool W/2)
///   conv2  15x64x32   outputs x 9x16      =  4.42 M   (then maxpool W/2)
///   conv3  15x32x48   outputs x 9x32      =  6.64 M   (then maxpool W/2)
///   GRU    15 steps x (768 + 128) x 384   =  5.16 M
///   dense  128 x 3                        =  0.00 M
///                                           -------
///                                           16.5 M MACs
///
/// against 363 891 parameters — **45x** more work than the parameter count, because
/// a conv kernel is applied at every spatial position and the GRU matrices at every
/// one of the 15 timesteps. A latency estimated from parameters alone is wrong by
/// that factor, which is exactly the error `crnn_strum_net.dart`'s header made.
const double _macsPerForward = 16.5e6;

/// Fraction of strokes routed to a settled verdict at the shipped margin
/// (`StrumAnalyzer._settleBelowMargin = 0.30`), MEASURED in
/// `ml/probe_settled_tier_value.py` on the held-out GuitarSet split.
const double _settledFraction = 0.198;

String _argValue(List<String> args, String name, String fallback) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
  }
  return fallback;
}

String _buildSha(List<String> args) {
  final given = _argValue(args, 'sha', '');
  if (given.isNotEmpty) return given;
  try {
    final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
    final sha = (result.stdout as String).trim();
    if (sha.isNotEmpty) return sha;
  } on ProcessException {
    // Fall through: a missing git is not a reason to fail a measurement, but it
    // IS a reason to refuse to invent a sha — the record schema rejects an empty
    // one, which is the behaviour we want.
  }
  return 'no-git';
}

double _median(List<int> samples) {
  final sorted = [...samples]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2.0;
}

void main([List<String> arguments = const []]) {
  final assetPath = _argValue(
    arguments,
    'asset',
    'assets/ml/strum_crnn_live_3c.bin',
  );
  final iterations = int.parse(_argValue(arguments, 'iterations', '200'));
  final file = File(assetPath);
  if (!file.existsSync()) {
    stderr.writeln('asset not found: $assetPath');
    exitCode = 2;
    return;
  }

  final net = CrnnStrumNet.parse(ByteData.sublistView(file.readAsBytesSync()));
  // A window that is not constant: a flat input can let a branchy kernel take an
  // unrepresentative path, and the measurement is meant to stand in for real audio.
  final window = <List<double>>[
    for (var r = 0; r < _rows; r++)
      <double>[
        for (var c = 0; c < _mels; c++)
          // Deterministic, spread over the range a normalised log-mel occupies.
          ((r * 31 + c * 17) % 97) / 97.0 * 6.0 - 3.0,
      ],
  ];

  // Warm up: the first calls pay lazy initialisation and, under JIT, profiling
  // and optimisation. Timing them would measure the warm-up, not the steady state.
  for (var i = 0; i < 20; i++) {
    net.forward(window);
  }

  final samples = <int>[];
  for (var i = 0; i < iterations; i++) {
    final watch = Stopwatch()..start();
    net.forward(window);
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }

  final median = _median(samples);
  final mean = samples.fold<int>(0, (a, b) => a + b) / samples.length;
  final p95 =
      ([...samples]..sort())[(samples.length * 0.95).floor().clamp(
            0,
            samples.length - 1,
          )]
          .toDouble();

  // Derived load, per second of audio at the fastest tuned tempo. Reported
  // because the per-call figure on its own has misled this project once already:
  // 29 ms sounds fatal until it is multiplied by how often it actually happens.
  final stressRate = _strokesPerSecond.values.first;
  final fastPerSecondUs = median * stressRate;
  final settledPerSecondUs = median * stressRate * _settledFraction;

  final sha = _buildSha(arguments);
  final timestamp = DateTime.now().toUtc().toIso8601String();
  const source = 'tool/benchmarks/strum_direction_forward_benchmark.dart';
  BenchmarkRecord record(
    String metric,
    double value,
    String unit,
  ) => BenchmarkRecord(
    schemaVersion: 1,
    metric: metric,
    value: value,
    unit: unit,
    sampleCount: iterations,
    // `measured` is correct for all four: every value is a real run's output
    // on this host. What is NOT measured here is the on-device figure, and
    // that is why no record claims a phone deviceId — inventing one is a
    // parse failure by design (ADR 0474 D2).
    kind: 'measured',
    direction: 'lowerIsBetter',
    source: source,
    buildSha: sha,
    deviceId: 'ci_host',
    timestamp: timestamp,
  );

  final records = <BenchmarkRecord>[
    record('strum_direction_forward_latency_median', median, 'us'),
    record('strum_direction_forward_latency_p95', p95, 'us'),
    record(
      'strum_direction_fast_tier_load_per_audio_second',
      fastPerSecondUs,
      'us',
    ),
    record(
      'strum_direction_settled_tier_load_per_audio_second',
      settledPerSecondUs,
      'us',
    ),
  ];

  stdout.writeln('asset            $assetPath');
  stdout.writeln('iterations       $iterations (after 20 warm-up calls)');
  stdout.writeln('window           $_rows x $_mels');
  stdout.writeln('build            $sha on ci_host');
  stdout.writeln('');
  stdout.writeln(
    'forward latency  median ${median.toStringAsFixed(1)} us  '
    'mean ${mean.toStringAsFixed(1)} us  p95 ${p95.toStringAsFixed(1)} us',
  );
  stdout.writeln('');
  stdout.writeln(
    'work per forward  ${(_macsPerForward / 1e6).toStringAsFixed(1)} M MACs '
    'for 363 891 parameters (45x) -> '
    '${(_macsPerForward / median / 1000).toStringAsFixed(2)} GMAC/s',
  );
  stdout.writeln(
    '                  a latency estimated from the PARAMETER count alone is '
    'wrong by that 45x.',
  );
  stdout.writeln('');
  stdout.writeln('load per second of audio (linear in strokes/s):');
  for (final entry in _strokesPerSecond.entries) {
    final rate = entry.value;
    final fast = median * rate;
    final settled = fast * _settledFraction;
    stdout.writeln(
      '  ${entry.key.padRight(28)} ${rate.toStringAsFixed(1)} strokes/s',
    );
    stdout.writeln(
      '    fast tier, every stroke     '
      '${(fast / 1000).toStringAsFixed(1).padLeft(6)} ms/s  '
      '= ${(fast / 10000).toStringAsFixed(1).padLeft(5)} % of one core',
    );
    stdout.writeln(
      '    settled tier, '
      '${(_settledFraction * 100).toStringAsFixed(1)}% routed     '
      '${(settled / 1000).toStringAsFixed(1).padLeft(6)} ms/s  '
      '= ${(settled / 10000).toStringAsFixed(1).padLeft(5)} % of one core',
    );
  }
  stdout.writeln('');
  stdout.writeln(
    'NOT measured here: the on-device figure. This is an x86 host, '
    'so these are',
  );
  stdout.writeln(
    'bounds for a phone, not values on one — and which KIND of '
    'bound depends on',
  );
  stdout.writeln(
    'how the file was run (JIT under flutter test, or AOT via '
    'dart compile exe).',
  );

  final jsonPath = _argValue(arguments, 'json', '');
  if (jsonPath.isNotEmpty) {
    File(jsonPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'records': [for (final r in records) r.toJson()],
      })}\n',
    );
    stdout.writeln('\nwrote $jsonPath (${records.length} records)');
  }
}
