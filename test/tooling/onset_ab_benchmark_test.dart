import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/data/evaluation/recognition_evaluation_runner.dart';
import 'package:strumsight/features/live/domain/evaluation/recognition_metrics.dart';
import 'package:strumsight/features/live/engine/dsp/onset_detector_variant.dart';
import 'package:strumsight/features/live/engine/dsp/superflux_onset_detector.dart';

import '../../tool/benchmarks/onset_ab_benchmark.dart';
import '../support/synth.dart';

/// E14-R16 gate (ADR 0524) — fixture-free: every case below is a
/// deterministically synthesized signal or a hand-built event list (ADR
/// 0524 D7); `test/fixtures/audio/` is this round's forbidden zone.
const _sr = 44100;

/// A realistic single strum: onset lands near 0.1 s (the shipped
/// `strumSignal` helper's default lead silence).
OnsetAbCase _strumCase({String caseId = 'single-strum'}) {
  final signal = strumSignal(lowFirst: true, seconds: 0.6);
  return OnsetAbCase(
    caseId: caseId,
    sampleRate: _sr,
    durationMs: (signal.length * 1000 / _sr).round(),
    pcm: signal,
    expectedEvents: [
      RecognitionExpectedEvent(timeMs: 100, kind: RecognitionEventKind.onset),
    ],
  );
}

void main() {
  group('onset A/B benchmark — E14-R16 acceptance matrix (ADR 0524)', () {
    test(
      '1. all four variant ids appear in the report over the SAME case list, '
      'each with the merge-elt 25/50/100 ms metric tree',
      () {
        final report = buildOnsetAbReport([_strumCase()]);

        expect(report.perVariant.keys.toSet(), OnsetVariantId.values.toSet());
        for (final id in OnsetVariantId.values) {
          final overall = report.perVariant[id]!.overall;
          expect(overall.onsetTolerance25Ms.definition.toleranceMs, 25);
          expect(overall.onsetTolerance50Ms.definition.toleranceMs, 50);
          expect(overall.onsetTolerance100Ms.definition.toleranceMs, 100);
          expect(report.perVariant[id]!.caseCount, 1);
        }
      },
    );

    test('2. the `current` variant onset list is element-for-element identical '
        'to the directly instantiated shipped SuperFluxOnsetDetector', () {
      final signal = strumPattern(
        lowFirstPerStrum: [true, false, true],
        gapSeconds: 0.3,
      );

      final directDetector = SuperFluxOnsetDetector(sampleRate: _sr);
      final directOnsets = <double>[];
      for (final frame in frames(
        signal,
        directDetector.window,
        directDetector.hop,
      )) {
        final t = directDetector.processFrame(frame);
        if (t != null) directOnsets.add(t);
      }

      final variant = createOnsetDetectorVariant(
        OnsetVariantId.current,
        sampleRate: _sr,
      );
      final variantOnsets = <double>[];
      for (final frame in frames(signal, variant.window, variant.hop)) {
        final t = variant.processFrame(frame);
        if (t != null) variantOnsets.add(t);
      }

      expect(directOnsets, isNotEmpty, reason: 'the fixture must fire');
      expect(variantOnsets, directOnsets);
    });

    test(
      '3. every onset metric is delegated: tolerance keys == onsetTolerancesMs '
      'and matchingRule carries the Kuhn text (can only come from the '
      'merge-elt contract)',
      () {
        final report = buildOnsetAbReport([_strumCase()]);

        expect(report.toJson()['onsetTolerancesMs'], onsetTolerancesMs);

        for (final id in OnsetVariantId.values) {
          final overall = report.perVariant[id]!.overall;
          for (final metric in [
            overall.onsetTolerance25Ms,
            overall.onsetTolerance50Ms,
            overall.onsetTolerance100Ms,
          ]) {
            expect(
              metric.definition.matchingRule,
              contains("Kuhn's maximum-cardinality"),
              reason: 'variant ${id.name}',
            );
          }
        }
      },
    );

    test('4. inclusive 50 ms boundary on the benchmark\'s OWN scoring path '
        '(scoreCases → computeRecognitionMetrics, no second matcher): '
        '49 ms matches, 50 ms matches (inclusive), 51 ms does not', () {
      // deviationMs is the |detected - expected| gap, tested against the 50
      // ms tolerance — NOT an offset from the literal value 50 (the brief's
      // own derivation: `t=50; [t-1, t, t+1]` == [49, 50, 51]).
      RecognitionPrecisionRecallF1 cellFor(int deviationMs) {
        final recognitionCase = RecognitionCase(
          caseId: 'boundary-$deviationMs',
          expectedEvents: [
            RecognitionExpectedEvent(
              timeMs: 1000,
              kind: RecognitionEventKind.onset,
            ),
          ],
          detectedEvents: [
            RecognitionDetectedEvent(
              timeMs: 1000 + deviationMs,
              kind: RecognitionEventKind.onset,
              accepted: true,
              confidence: 1.0,
            ),
          ],
        );
        return scoreCases([recognitionCase]).overall.onsetTolerance50Ms;
      }

      final under = cellFor(49); // 49 ms — under the boundary
      expect(under.truePositives, 1, reason: '49 ms — under the boundary');
      expect(under.falsePositives, 0);
      expect(under.falseNegatives, 0);

      final onBoundary = cellFor(50); // 50 ms exactly — inclusive
      expect(
        onBoundary.truePositives,
        1,
        reason: '50 ms — ON the boundary, inclusive',
      );
      expect(onBoundary.falsePositives, 0);
      expect(onBoundary.falseNegatives, 0);

      final over = cellFor(51); // 51 ms — over the boundary
      expect(over.truePositives, 0, reason: '51 ms — over the boundary');
      expect(over.falsePositives, 1);
      expect(over.falseNegatives, 1);
    });

    test('5. determinism — two runs on the same input produce byte-identical '
        'deterministic JSON, and it never carries a timing key', () {
      final cases = [_strumCase()];
      final first = buildOnsetAbReport(cases).toDeterministicJson();
      final second = buildOnsetAbReport(cases).toDeterministicJson();

      expect(first, second);
      for (final forbidden in [
        'elapsed',
        'wallClock',
        'cpu',
        'durationMicros',
        'timestamp',
      ]) {
        expect(
          first.contains(forbidden),
          isFalse,
          reason: 'deterministic report must not carry "$forbidden"',
        );
      }
    });

    test('6. timing is measured on a SEPARATE, explicitly machine-dependent '
        'channel (deviceId + buildSha), and the deterministic report still '
        'carries the algorithmic latency percentiles', () {
      final cases = [_strumCase()];
      final report = buildOnsetAbReport(cases);
      final timing = measureOnsetAbTiming(
        cases,
        deviceId: 'ci_host',
        buildSha: 'deadbeef',
      );

      expect(timing.deviceId, 'ci_host');
      expect(timing.buildSha, 'deadbeef');
      final timingJson = timing.toJsonString();
      expect(timingJson, contains('deviceId'));
      expect(timingJson, contains('buildSha'));
      expect(timingJson, contains('MACHINE-DEPENDENT'));
      for (final id in OnsetVariantId.values) {
        expect(timing.perVariant[id], isNotNull, reason: id.name);
      }

      final currentLatency =
          report.perVariant[OnsetVariantId.current]!.overall.latencyP50Ms;
      expect(
        currentLatency.value,
        isNotNull,
        reason: 'the strum fixture must yield at least one confirmed onset',
      );
    });

    test(
      '7. an unannotated case renders "not measured", never a coerced 0',
      () {
        final signal = Float64List(_sr); // 1 s of true silence
        final unannotated = OnsetAbCase(
          caseId: 'no-annotation',
          sampleRate: _sr,
          durationMs: 1000,
          pcm: signal,
          expectedEvents: const [],
        );

        final report = buildOnsetAbReport([unannotated]);
        final onset50 = report
            .perVariant[OnsetVariantId.current]!
            .overall
            .onsetTolerance50Ms;
        expect(onset50.precision, isNull);
        expect(onset50.recall, isNull);
        expect(onset50.f1, isNull);

        final markdown = renderOnsetAbMarkdown(report);
        expect(markdown, contains('not measured'));
        expect(markdown, isNot(contains('0.0000')));
      },
    );

    test('8. the production constants have not moved — pinned via the shipped '
        "detector's public defaults, and every new variant reads the same "
        'values (no re-typed literal)', () {
      final shipped = SuperFluxOnsetDetector(sampleRate: _sr);
      expect(shipped.delta, 12.0);
      expect(shipped.lambda, 1.0);
      expect(shipped.minIoiSec, 0.06);
      expect(shipped.window, 1024);
      expect(shipped.hop, 256);
      expect(shipped.bands, 64);
      expect(shipped.lag, 2);

      for (final id in OnsetVariantId.values) {
        final variant = createOnsetDetectorVariant(id, sampleRate: _sr);
        expect(variant.window, shipped.window, reason: id.name);
        expect(variant.hop, shipped.hop, reason: id.name);
        expect(variant.delta, shipped.delta, reason: id.name);
        expect(variant.lambda, shipped.lambda, reason: id.name);
        expect(variant.minIoiSec, shipped.minIoiSec, reason: id.name);
      }
    });

    test('9. a per-variant manifest round-trips through '
        'RecognitionEvaluationRunner with IDENTICAL onset metrics', () {
      final recognitionCase = RecognitionCase(
        caseId: 'roundtrip',
        durationMs: 2000,
        expectedEvents: [
          RecognitionExpectedEvent(
            timeMs: 100,
            kind: RecognitionEventKind.onset,
          ),
          RecognitionExpectedEvent(
            timeMs: 500,
            kind: RecognitionEventKind.onset,
          ),
        ],
        detectedEvents: [
          RecognitionDetectedEvent(
            timeMs: 110,
            kind: RecognitionEventKind.onset,
            accepted: true,
            confidence: 0.9,
          ),
        ],
        detectionLatenciesMs: const [40],
      );

      final directReport = scoreCases([recognitionCase]);
      final manifestSource = jsonEncode(manifestJson([recognitionCase]));
      final reparsed = const RecognitionEvaluationRunner().runFromJsonString(
        manifestSource,
      );

      expect(reparsed.toJson(), equals(directReport.toJson()));
    });
  });
}
