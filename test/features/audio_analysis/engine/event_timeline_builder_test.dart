import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart' as legacy_core;
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_provenance_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/events/event_timeline_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/legacy_evidence.dart';

void main() {
  group('EventTimelineBuilder', () {
    test('builds an onset/strum pair with stable linked IDs', () {
      final result = EventTimelineBuilder().build(
        runId: 'run-42',
        evidence: _evidence(
          strums: const <LegacyStrumEvidence>[
            LegacyStrumEvidence(
              direction: legacy_core.StrumDirection.down,
              time: Duration(milliseconds: 50),
              confidence: .8,
            ),
          ],
        ),
        audio: _audio(),
      );

      expect(result.events, hasLength(2));
      final onset = result.events.first as OnsetEvent;
      final strum = result.events.last as StrumEvent;
      expect(onset.id, 'run-42:onset:2400');
      expect(strum.id, 'run-42:strum:2400');
      expect(onset.sampleIndex, 2400);
      expect(strum.sampleIndex, 2400);
      expect(onset.time, const Duration(milliseconds: 50));
      expect(strum.time, onset.time);
      expect(strum.onsetEventId, onset.id);
      expect(strum.direction, StrumDirection.down);
      expect(strum.directionConfidence, .8);
      expect(onset.confidenceSource, 'heuristic');
      expect(strum.confidenceSource, 'heuristic');
      expect(result.suppressedEvents, isEmpty);
    });

    test('suppresses the whole second pair below 50 milliseconds', () {
      final result = EventTimelineBuilder().build(
        runId: 'run-42',
        evidence: _evidence(
          strums: const <LegacyStrumEvidence>[
            LegacyStrumEvidence(
              direction: legacy_core.StrumDirection.down,
              time: Duration.zero,
              confidence: .8,
            ),
            LegacyStrumEvidence(
              direction: legacy_core.StrumDirection.up,
              time: Duration(microseconds: 49979),
              confidence: .7,
            ),
          ],
        ),
        audio: _audio(sampleCount: 5000),
      );

      expect(result.events, hasLength(2));
      expect(result.suppressedEvents, hasLength(2));
      expect(
        result.suppressedEvents.map((entry) => entry.reason),
        everyElement(EventSuppressionReason.minimumSeparation),
      );
      expect(
        result.suppressedEvents.map((entry) => entry.event),
        everyElement(isA<AnalysisEvent>()),
      );
    });

    test('keeps pairs exactly at and above the Duration threshold', () {
      for (final time in const <Duration>[
        Duration(milliseconds: 50),
        Duration(microseconds: 50021),
      ]) {
        final result = EventTimelineBuilder().build(
          runId: 'run-42',
          evidence: _evidence(
            strums: <LegacyStrumEvidence>[
              const LegacyStrumEvidence(
                direction: legacy_core.StrumDirection.down,
                time: Duration.zero,
                confidence: .8,
              ),
              LegacyStrumEvidence(
                direction: legacy_core.StrumDirection.up,
                time: time,
                confidence: .7,
              ),
            ],
          ),
          audio: _audio(sampleCount: 6000),
        );

        expect(result.events, hasLength(4), reason: '$time');
        expect(result.suppressedEvents, isEmpty, reason: '$time');
      }
    });

    test('uses Duration separation at 48000 and 44100 Hz', () {
      for (final sampleRate in <int>[48000, 44100]) {
        final thresholdSamples = sampleRate ~/ 20;
        for (final offset in <int>[
          thresholdSamples - 1,
          thresholdSamples,
          thresholdSamples + 1,
        ]) {
          final audio = _audio(sampleRate: sampleRate, sampleCount: sampleRate);
          final result = EventTimelineBuilder().build(
            runId: 'run-$sampleRate-$offset',
            evidence: _evidence(
              sampleRate: sampleRate,
              strums: <LegacyStrumEvidence>[
                const LegacyStrumEvidence(
                  direction: legacy_core.StrumDirection.down,
                  time: Duration.zero,
                  confidence: .8,
                ),
                LegacyStrumEvidence(
                  direction: legacy_core.StrumDirection.up,
                  time: audio.sampleIndexToDuration(offset),
                  confidence: .7,
                ),
              ],
            ),
            audio: audio,
          );

          final keepsSecondPair = offset >= thresholdSamples;
          expect(
            result.events,
            hasLength(keepsSecondPair ? 4 : 2),
            reason: '$sampleRate Hz at $offset samples',
          );
          expect(
            result.suppressedEvents,
            hasLength(keepsSecondPair ? 0 : 2),
            reason: '$sampleRate Hz at $offset samples',
          );
        }
      }
    });

    test('orders an equal-index onset before its linked strum', () {
      final result = EventTimelineBuilder().build(
        runId: 'run-42',
        evidence: _evidence(
          strums: const <LegacyStrumEvidence>[
            LegacyStrumEvidence(
              direction: legacy_core.StrumDirection.down,
              time: Duration.zero,
              confidence: .8,
            ),
          ],
        ),
        audio: _audio(),
      );

      final onset = result.events[0] as OnsetEvent;
      final strum = result.events[1] as StrumEvent;
      expect(onset.sampleIndex, strum.sampleIndex);
      expect(strum.onsetEventId, onset.id);
    });

    test('keeps IDs deterministic while namespacing separate runs', () {
      final input = _evidence(
        strums: const <LegacyStrumEvidence>[
          LegacyStrumEvidence(
            direction: legacy_core.StrumDirection.down,
            time: Duration(milliseconds: 50),
            confidence: .8,
          ),
        ],
      );
      final builder = EventTimelineBuilder();
      final first = builder.build(
        runId: 'one',
        evidence: input,
        audio: _audio(),
      );
      final second = builder.build(
        runId: 'one',
        evidence: input,
        audio: _audio(),
      );
      final otherRun = builder.build(
        runId: 'two',
        evidence: input,
        audio: _audio(),
      );

      expect(
        first.events.map((event) => event.id),
        second.events.map((event) => event.id),
      );
      expect(
        first.events.map((event) => event.id),
        isNot(otherRun.events.map((event) => event.id)),
      );
      expect(
        first.events.map((event) => event.id.split(':').skip(1)),
        otherRun.events.map((event) => event.id.split(':').skip(1)),
      );
    });

    test('handles empty evidence and native sample boundaries', () {
      final emptyAudio = _audio(sampleCount: 0);
      final empty = EventTimelineBuilder().build(
        runId: 'empty',
        evidence: _evidence(strums: const <LegacyStrumEvidence>[]),
        audio: emptyAudio,
      );
      expect(empty.events, isEmpty);

      final audio = _audio(sampleCount: 48000);
      final result = EventTimelineBuilder().build(
        runId: 'boundaries',
        evidence: _evidence(
          strums: <LegacyStrumEvidence>[
            const LegacyStrumEvidence(
              direction: legacy_core.StrumDirection.down,
              time: Duration.zero,
              confidence: .8,
            ),
            LegacyStrumEvidence(
              direction: legacy_core.StrumDirection.up,
              time: audio.sampleIndexToDuration(
                audio.originalSamples.length - 1,
              ),
              confidence: .7,
            ),
          ],
        ),
        audio: audio,
      );
      expect(
        result.events.whereType<StrumEvent>().map((event) => event.sampleIndex),
        <int?>[0, 47999],
      );
    });
  });
}

LegacyEvidence _evidence({
  required List<LegacyStrumEvidence> strums,
  int sampleRate = 48000,
}) => LegacyEvidence(
  duration: const Duration(seconds: 1),
  bpm: 120,
  chords: const <LegacyChordEvidence>[],
  strums: strums,
  call: LegacyClipAnalyzerCall(
    sampleRate: sampleRate,
    sampleCount: sampleRate,
    labMode: false,
    hasCandidateStrumRefiner: false,
  ),
  provenance: AnalysisProvenanceBuilder().build(
    strumRefinerSource: StrumRefinerSource.none,
  ),
);

PreprocessedAudio _audio({int sampleRate = 48000, int sampleCount = 48000}) {
  final samples = List<double>.filled(sampleCount, .25);
  return PreprocessedAudio(
    originalSamples: samples,
    canonicalSamples: samples,
    sampleRate: sampleRate,
    originalChannelCount: 1,
    normalizationGain: 1,
    preprocessingVersion: 'test',
  );
}
