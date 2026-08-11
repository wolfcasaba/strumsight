import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final random = math.Random(seed);
  const codec = AnalysisDocumentCodec();

  test(
    'property: encoded native documents are finite and retain microseconds',
    () {
      for (var index = 0; index < 40; index++) {
        final microseconds = random.nextInt(1000000);
        final document = AnalysisDocument(
          id: 'property-$index',
          schemaVersion: analysisDocumentSchemaVersion,
          createdAt: DateTime.utc(2026),
          mode: AnalysisMode.freePlay,
          input: AnalysisInputSummary(
            source: AnalysisInputSource.microphone,
            duration: Duration(microseconds: microseconds),
            sampleRate: 44100,
            channelCount: 1,
            fingerprint: 'property-$index',
          ),
          provenance: AnalysisProvenance(
            appVersion: '1',
            analyzerVersion: '1',
            pipelineVersion: '1',
            stageVersions: const <String, String>{},
            dspConfigHash: 'hash',
            modelManifestIds: const <String>[],
            inputFingerprint: 'property-$index',
            platform: 'android',
            featureFlagSnapshot: const <String, bool>{},
          ),
          signalQuality: SignalQualityReport(
            overall: 0,
            peakDbfs: 0,
            rmsDbfs: 0,
            noiseFloorDbfs: 0,
            clippedSampleRatio: 0,
            silentRatio: 0,
            tonalness: 0,
          ),
          capabilities: const <CapabilityReport>[],
          timeline: AnalysisTimeline(
            duration: Duration(microseconds: microseconds),
          ),
          metrics: const <AnalysisMetricResult>[],
          hotspots: const <AnalysisHotspot>[],
          insights: const <AnalysisInsight>[],
          warnings: const <AnalysisWarning>[],
          completion: AnalysisCompletion(
            status: AnalysisCompletionStatus.complete,
          ),
        );
        final decoded = codec.decode(codec.encode(document));
        expect(
          decoded.valueOrNull?.timeline.duration,
          Duration(microseconds: microseconds),
          reason: 'seed=$seed index=$index',
        );
        _expectFiniteJson(jsonDecode(codec.encode(document)));
      }
    },
  );
}

void _expectFiniteJson(Object? value) {
  switch (value) {
    case num():
      expect(value.isFinite, isTrue);
    case Map<Object?, Object?>():
      for (final nested in value.values) {
        _expectFiniteJson(nested);
      }
    case Iterable<Object?>():
      for (final nested in value) {
        _expectFiniteJson(nested);
      }
  }
}
