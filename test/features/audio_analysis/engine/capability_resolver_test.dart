import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('CapabilityResolver', () {
    final resolver = CapabilityResolver();

    test('resolves every capability for the nine required input cases', () {
      final allCapabilities = AnalysisCapability.values.toSet();
      final cases =
          <
            ({
              String name,
              CapabilityResolverInput input,
              Map<AnalysisCapability, CapabilityStatus> statuses,
              CapabilityUnavailableReason? reason,
            })
          >[
            (
              name: 'high-quality target',
              input: _input(),
              statuses: _all(CapabilityStatus.available),
              reason: null,
            ),
            (
              name: 'clipped input',
              input: _input(clippedSampleRatio: 0.06),
              statuses: _all(CapabilityStatus.unavailable),
              reason: CapabilityUnavailableReason.inputClipped,
            ),
            (
              name: 'noisy input',
              input: _input(noiseFloorDbfs: -24),
              statuses: _all(CapabilityStatus.unavailable),
              reason: CapabilityUnavailableReason.inputTooNoisy,
            ),
            (
              name: 'clip too short',
              input: _input(isClipTooShort: true),
              statuses: _all(CapabilityStatus.unavailable),
              reason: CapabilityUnavailableReason.clipTooShort,
            ),
            (
              name: 'model unavailable',
              input: _input(modelAvailable: false),
              statuses: <AnalysisCapability, CapabilityStatus>{
                ..._all(CapabilityStatus.unavailable),
                AnalysisCapability.signalQuality: CapabilityStatus.available,
              },
              reason: CapabilityUnavailableReason.modelUnavailable,
            ),
            (
              name: 'weak alignment',
              input: _input(alignmentQuality: 0.1),
              statuses: _all(CapabilityStatus.degraded),
              reason: null,
            ),
            (
              name: 'pitch supported but dynamics unavailable',
              input: _input(
                supportedCapabilities: allCapabilities.toSet()
                  ..remove(AnalysisCapability.dynamicConsistency),
              ),
              statuses: <AnalysisCapability, CapabilityStatus>{
                ..._all(CapabilityStatus.available),
                AnalysisCapability.dynamicConsistency:
                    CapabilityStatus.notApplicable,
              },
              reason: null,
            ),
            (
              name: 'confidence boundary',
              input: _input(
                signalQuality: 0.4,
                modelConfidence: 0.4,
                alignmentQuality: 0.4,
              ),
              statuses: _all(CapabilityStatus.degraded),
              reason: null,
            ),
            (
              name: 'contradicting hypotheses',
              input: _input(hypothesesAgree: false),
              statuses: _all(CapabilityStatus.unavailable),
              reason: CapabilityUnavailableReason.confidenceTooLow,
            ),
          ];

      for (final testCase in cases) {
        final result = resolver.resolve(testCase.input);
        expect(result.reports, hasLength(AnalysisCapability.values.length));
        expect(result.reports.keys, containsAll(allCapabilities));
        for (final capability in AnalysisCapability.values) {
          final report = result.reports[capability]!;
          expect(
            report.status,
            testCase.statuses[capability],
            reason: '${testCase.name}: $capability',
          );
          expect(
            report.reason,
            testCase.statuses[capability] == CapabilityStatus.unavailable
                ? testCase.reason
                : isNull,
            reason: '${testCase.name}: $capability',
          );
        }
      }
    });

    test('uses inclusive degraded and available confidence boundaries', () {
      const cells = <({double value, CapabilityStatus status})>[
        (value: 0.3999, status: CapabilityStatus.unavailable),
        (value: 0.4, status: CapabilityStatus.degraded),
        (value: 0.4001, status: CapabilityStatus.degraded),
        (value: 0.6999, status: CapabilityStatus.degraded),
        (value: 0.7, status: CapabilityStatus.available),
        (value: 0.7001, status: CapabilityStatus.available),
      ];

      for (final cell in cells) {
        final result = resolver.resolve(
          _input(
            signalQuality: cell.value,
            modelConfidence: cell.value,
            alignmentQuality: cell.value,
          ),
        );
        for (final report in result.reports.values) {
          expect(report.status, cell.status, reason: '${cell.value}');
        }
      }
    });

    test(
      'adds identity calibration provenance to every published confidence',
      () {
        final result = resolver.resolve(_input());

        for (final report in result.reports.values) {
          expect(report.calibrationVersion, CalibrationTable.identityVersion);
          expect(
            report.calibrationSource,
            ConfidenceCalibrationSource.identity,
          );
        }
      },
    );

    test('is bit-identical across one hundred equal resolutions', () {
      final first = resolver.resolve(_input());
      for (var index = 0; index < 100; index += 1) {
        final repeated = resolver.resolve(_input());
        expect(repeated.overallConfidence, first.overallConfidence);
        expect(repeated.overallStatus, first.overallStatus);
        expect(repeated.reports.keys, first.reports.keys);
        for (final capability in AnalysisCapability.values) {
          final expected = first.reports[capability]!;
          final actual = repeated.reports[capability]!;
          expect(actual.status, expected.status);
          expect(actual.confidence, expected.confidence);
          expect(actual.reason, expected.reason);
          expect(actual.details, expected.details);
        }
      }
    });

    test(
      'keeps critical signal-quality failure from claiming available overall',
      () {
        final result = resolver.resolve(_input(clippedSampleRatio: 0.06));

        expect(
          result.reports[AnalysisCapability.signalQuality]!.status,
          CapabilityStatus.unavailable,
        );
        expect(result.overallStatus, isNot(CapabilityStatus.available));
      },
    );

    test(
      'returns a not-applicable overall when no capabilities are supported',
      () {
        final result = resolver.resolve(
          _input(supportedCapabilities: const <AnalysisCapability>{}),
        );

        expect(result.overallStatus, CapabilityStatus.notApplicable);
        expect(result.overallConfidence, 0);
        for (final report in result.reports.values) {
          expect(report.status, CapabilityStatus.notApplicable);
        }
      },
    );
  });

  test(
    'only capability_resolver assigns statuses in the new confidence module',
    () {
      final files = Directory(
        'lib/features/audio_analysis/engine/confidence',
      ).listSync().whereType<File>();
      final assignments = <String>[];
      for (final file in files) {
        final content = file.readAsStringSync();
        if (content.contains('CapabilityStatus.')) assignments.add(file.path);
      }

      expect(assignments, <String>[
        'lib/features/audio_analysis/engine/confidence/capability_resolver.dart',
      ]);
    },
  );
}

Map<AnalysisCapability, CapabilityStatus> _all(CapabilityStatus status) =>
    <AnalysisCapability, CapabilityStatus>{
      for (final capability in AnalysisCapability.values) capability: status,
    };

CapabilityResolverInput _input({
  double signalQuality = 0.9,
  double modelConfidence = 0.9,
  double alignmentQuality = 0.9,
  double clippedSampleRatio = 0,
  double noiseFloorDbfs = -60,
  bool isClipTooShort = false,
  bool modelAvailable = true,
  bool hypothesesAgree = true,
  Set<AnalysisCapability>? supportedCapabilities,
}) => CapabilityResolverInput(
  signalQuality: SignalQualityReport(
    overall: signalQuality,
    peakDbfs: -3,
    rmsDbfs: -12,
    noiseFloorDbfs: noiseFloorDbfs,
    clippedSampleRatio: clippedSampleRatio,
    silentRatio: 0.1,
    tonalness: 0.9,
  ),
  eventCount: 8,
  modelConfidence: modelConfidence,
  alignmentQuality: alignmentQuality,
  mode: AnalysisMode.practiceTarget,
  hasReferenceTarget: true,
  modelAvailable: modelAvailable,
  isClipTooShort: isClipTooShort,
  hypothesesAgree: hypothesesAgree,
  supportedCapabilities: supportedCapabilities,
);
