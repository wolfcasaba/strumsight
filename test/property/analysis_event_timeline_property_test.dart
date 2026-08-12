import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart' as legacy_core;
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_provenance_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/events/event_timeline_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/legacy_evidence.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;

  test(
    'property: event timelines are ordered, unique, finite, and linked (PROPERTY_SEED=$seed)',
    () {
      final random = math.Random(seed);
      const builder = EventTimelineBuilder();

      for (var iteration = 0; iteration < 80; iteration++) {
        final sampleRate = random.nextBool() ? 44100 : 48000;
        final audio = _audio(sampleRate, sampleRate * 2);
        final strums = <LegacyStrumEvidence>[
          for (var index = 0; index < 40; index++)
            LegacyStrumEvidence(
              direction: random.nextBool()
                  ? legacy_core.StrumDirection.down
                  : legacy_core.StrumDirection.up,
              time: audio.sampleIndexToDuration(
                random.nextInt(audio.originalSamples.length),
              ),
              confidence: random.nextDouble(),
            ),
        ];
        final result = builder.build(
          runId: 'seed-$seed-$iteration',
          evidence: _evidence(sampleRate, strums),
          audio: audio,
        );
        final seen = <(Type, int?)>{};
        final onsets = <String, OnsetEvent>{};
        var previousSampleIndex = -1;

        for (final event in result.events) {
          expect(event.sampleIndex, isNotNull);
          expect(event.sampleIndex!, greaterThanOrEqualTo(previousSampleIndex));
          previousSampleIndex = event.sampleIndex!;
          expect(seen.add((event.runtimeType, event.sampleIndex)), isTrue);
          expect(event.confidence.isFinite, isTrue);
          expect(event.confidence, inInclusiveRange(0, 1));
          expect(
            event,
            isNot(
              isA<OnsetEvent>().having(
                (value) => value.confidenceSource,
                'confidenceSource',
                EventConfidenceSources.calibrated,
              ),
            ),
          );
          if (event case OnsetEvent()) onsets[event.id] = event;
        }
        for (final strum in result.events.whereType<StrumEvent>()) {
          expect(strum.onsetEventId, isNotNull);
          final onset = onsets[strum.onsetEventId];
          expect(onset, isNotNull);
          expect(onset!.sampleIndex, strum.sampleIndex);
          expect(onset.time, strum.time);
          expect(
            strum.confidenceSource,
            isNot(EventConfidenceSources.calibrated),
          );
        }
      }
    },
  );
}

LegacyEvidence _evidence(int sampleRate, List<LegacyStrumEvidence> strums) =>
    LegacyEvidence(
      duration: const Duration(seconds: 2),
      bpm: 120,
      chords: const <LegacyChordEvidence>[],
      strums: strums,
      call: LegacyClipAnalyzerCall(
        sampleRate: sampleRate,
        sampleCount: sampleRate * 2,
        labMode: false,
        hasCandidateStrumRefiner: false,
      ),
      provenance: AnalysisProvenanceBuilder().build(
        strumRefinerSource: StrumRefinerSource.none,
      ),
    );

PreprocessedAudio _audio(int sampleRate, int count) {
  final samples = List<double>.generate(
    count,
    (index) => index.isEven ? .25 : -.5,
  );
  return PreprocessedAudio(
    originalSamples: samples,
    canonicalSamples: samples,
    sampleRate: sampleRate,
    originalChannelCount: 1,
    normalizationGain: 1,
    preprocessingVersion: 'test',
  );
}
