/// Reproducible Audio Analysis performance inventory for E06-R28.
///
/// Run with:
/// `flutter test --reporter expanded tool/audio_analysis_benchmark.dart`
///
/// The concrete V2 runner intentionally fails closed in this round, so the
/// three established V1 fixtures are measured by their existing harness while
/// this script measures the new cache infrastructure separately. No timing is
/// a test threshold.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/data/cache/analysis_cache.dart';
import 'package:strumsight/features/audio_analysis/domain/cache/analysis_cache_key.dart';

void main() {
  test('prints the E06-R28 performance inventory', () async {
    final baseline = await Process.run('flutter', <String>[
      'test',
      '--reporter',
      'expanded',
      'tool/audio_analysis_baseline.dart',
    ]);
    expect(baseline.exitCode, 0, reason: baseline.stderr);

    final baselineLines = <String>[
      for (final line in const LineSplitter().convert(
        baseline.stdout as String,
      ))
        if (line.contains('MODEL ') ||
            line.contains('FIXTURE ') ||
            line.contains('DETERMINISM_SHA256 '))
          line.substring(
            line.indexOf(RegExp(r'(MODEL|FIXTURE|DETERMINISM_SHA256)')),
          ),
    ];
    expect(
      baselineLines.where((line) => line.startsWith('FIXTURE ')),
      hasLength(3),
    );

    final root = await Directory.systemTemp.createTemp(
      'audio_analysis_benchmark_',
    );
    try {
      final cache = await AnalysisCache.openAtDirectory(
        directory: Directory('${root.path}/analysis_cache'),
      );
      final key = AnalysisCacheKey(
        inputFingerprint: 'benchmark-fixture-v1',
        analyzerVersion: 'benchmark-v1',
        modelManifestIds: const <String>['strum_crnn.bin@SSML-v1'],
        dspConfigHash: 'benchmark-dsp-v1',
        targetHash: AnalysisCacheKey.noTargetHash,
        featureFlagSnapshot: const <String, bool>{'audioAnalysisV2': false},
      );
      final miss = Stopwatch()..start();
      await cache.getOrCompute(
        key,
        () async => Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      miss.stop();
      final hit = Stopwatch()..start();
      await cache.getOrCompute(
        key,
        () async => throw StateError('cache hit must not recompute'),
      );
      hit.stop();

      stdout.writeln(
        'CACHE ${jsonEncode(<String, Object?>{'missMicroseconds': miss.elapsedMicroseconds, 'hitMicroseconds': hit.elapsedMicroseconds, 'entryCount': await cache.entryCount(), 'totalPayloadBytes': await cache.totalBytes(), 'cancelLatencyMicroseconds': null, 'cancelMeasurement': 'not available: V2 runner is not composed'})}',
      );
      for (final line in baselineLines) {
        stdout.writeln(line);
      }
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
