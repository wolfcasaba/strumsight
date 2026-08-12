import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart' as legacy_core;
import 'package:strumsight/features/analyze/engine/clip_analyzer.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_provenance_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/events/event_timeline_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/clip_analyzer_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/legacy_evidence.dart';

import '../../../support/synth.dart';

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

    test(
      'preserves V1 strum timestamps, counts, and directions for R09 fixtures',
      () async {
        for (final fixture in _r09ParityFixtures) {
          final v1 = fixture.v1(fixture.samples, fixture.sampleRate);
          final evidence = await _runClipAnalyzerStage(
            LegacyClipAnalyzerInput(
              samples: fixture.samples,
              sampleRate: fixture.sampleRate,
              strumRefinerWeights: fixture.stageWeights,
            ),
          );

          if (fixture.sampleRate <= 0) {
            expect(v1.strums, isEmpty, reason: fixture.label);
            expect(evidence.strums, isEmpty, reason: fixture.label);
            continue;
          }

          final timeline = EventTimelineBuilder().build(
            runId: 'r09-${fixture.label}',
            evidence: evidence,
            audio: _audioFromSamples(
              fixture.samples,
              sampleRate: fixture.sampleRate,
            ),
          );
          final strums = timeline.events.whereType<StrumEvent>().toList();

          expect(timeline.suppressedEvents, isEmpty, reason: fixture.label);
          expect(strums, hasLength(v1.strums.length), reason: fixture.label);
          for (var index = 0; index < v1.strums.length; index++) {
            final expected = v1.strums[index];
            final actual = strums[index];
            expect(
              (actual.time.inMicroseconds -
                      (expected.timeSec * Duration.microsecondsPerSecond)
                          .round())
                  .abs(),
              lessThanOrEqualTo(1),
              reason: '${fixture.label} strum=$index time',
            );
            expect(
              actual.direction,
              expected.direction == legacy_core.StrumDirection.down
                  ? StrumDirection.down
                  : StrumDirection.up,
              reason: '${fixture.label} strum=$index direction',
            );
          }
        }
      },
    );

    test('measures attack strength and local RMS from original PCM', () {
      const sampleRate = 1000;
      final samples = List<double>.filled(100, .5)..[10] = .9;
      final result = EventTimelineBuilder().build(
        runId: 'known-dynamics',
        evidence: _evidence(
          sampleRate: sampleRate,
          strums: const <LegacyStrumEvidence>[
            LegacyStrumEvidence(
              direction: legacy_core.StrumDirection.down,
              time: Duration(milliseconds: 10),
              confidence: .8,
            ),
          ],
        ),
        audio: _audioFromSamples(samples, sampleRate: sampleRate),
      );

      final onset = result.events.whereType<OnsetEvent>().single;
      expect(onset.attackStrength, closeTo(.9, 1e-9));
      expect(onset.localRms, closeTo(0.5108624004141064, 1e-9));
    });
  });
}

final _r09ParityFixtures = <_ParityFixture>[
  _ParityFixture('silence', List<double>.filled(44100, 0)),
  _ParityFixture(
    'two chords',
    _join(<List<double>>[
      chordSignal(cMajorFreqs, seconds: .8),
      chordSignal(gMajorFreqs, seconds: .8),
    ]),
  ),
  _ParityFixture(
    'four chords C G Am F',
    _join(<List<double>>[
      chordSignal(cMajorFreqs, seconds: .8),
      chordSignal(gMajorFreqs, seconds: .8),
      chordSignal(aMinorFreqs, seconds: .8),
      chordSignal(fMajorFreqs, seconds: .8),
    ]),
  ),
  _ParityFixture(
    'ring-out overlap',
    overlappingStrums(
      lowFirstPerStrum: <bool>[true, false, true, false],
      gapSeconds: .25,
    ),
  ),
  _ParityFixture('single strum', strumSignal(lowFirst: true)),
  _ParityFixture(
    'known BPM strum sequence',
    strumPattern(
      lowFirstPerStrum: <bool>[true, false, true, false],
      gapSeconds: .5,
    ),
  ),
  _ParityFixture(
    'throwing refiner fallback',
    strumPattern(lowFirstPerStrum: <bool>[true, false, true]),
    stageWeights: Uint8List(16),
    v1: (samples, sampleRate) => ClipAnalyzer(
      strumRefiner: (pcm, sr, onsets) => throw StateError('fixture refiner'),
    ).analyze(samples, sampleRate),
  ),
  _ParityFixture('empty input', const <double>[]),
  _ParityFixture('sample rate zero', const <double>[], sampleRate: 0),
];

final class _ParityFixture {
  _ParityFixture(
    this.label,
    List<double> samples, {
    this.sampleRate = 44100,
    this.stageWeights,
    this.v1 = _defaultV1,
  }) : samples = List<double>.unmodifiable(samples);

  final String label;
  final List<double> samples;
  final int sampleRate;
  final Uint8List? stageWeights;
  final AnalyzeResult Function(List<double>, int) v1;
}

AnalyzeResult _defaultV1(List<double> samples, int sampleRate) =>
    const ClipAnalyzer().analyze(samples, sampleRate);

List<double> _join(List<List<double>> clips) => <double>[
  for (final clip in clips) ...clip,
];

Future<LegacyEvidence> _runClipAnalyzerStage(
  LegacyClipAnalyzerInput input,
) async {
  final result = await const ClipAnalyzerStage().run(
    input,
    AnalysisStageContext(
      runId: 'event-timeline-builder-parity-test',
      phase: AnalysisProgressPhase.extractingEvents,
      cancellationToken: AnalysisCancellationSource(),
      eventSink: (_) {},
    ),
  );
  return switch (result) {
    Success<LegacyEvidence>(:final value) => value,
    Failure<LegacyEvidence>(:final error) => throw StateError(error.code),
  };
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
  return _audioFromSamples(samples, sampleRate: sampleRate);
}

PreprocessedAudio _audioFromSamples(
  List<double> samples, {
  required int sampleRate,
}) {
  return PreprocessedAudio(
    originalSamples: samples,
    canonicalSamples: samples,
    sampleRate: sampleRate,
    originalChannelCount: 1,
    normalizationGain: 1,
    preprocessingVersion: 'test',
  );
}
