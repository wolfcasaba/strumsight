import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/data/evaluation/evaluation_manifest_parser.dart';
import 'package:strumsight/features/audio_analysis/data/evaluation/evaluation_runner.dart';
import 'package:strumsight/features/audio_analysis/domain/evaluation/evaluation_report.dart';
import 'package:strumsight/features/audio_analysis/domain/evaluation/ground_truth.dart';

GroundTruthManifest _sampleManifest() => GroundTruthManifest(
  schemaVersion: '1.0',
  cases: [
    GroundTruthCase(
      id: 'case-a',
      tempoBand: TempoBand.medium,
      signalQualityTier: SignalQualityTier.clean,
      mode: EvalMode.chord,
      expected: AnnotationSet(
        events: [
          EvalEvent(id: 'e1', timeMs: 0, type: EvalEventType.onset),
          EvalEvent(id: 'e2', timeMs: 500, type: EvalEventType.onset),
        ],
        chordSegments: [EvalChordSegment(label: 'C', startMs: 0, endMs: 1000)],
        tempoBpm: 120,
        beatsMs: const [0, 500],
        pitchPoints: const [],
      ),
      detected: AnnotationSet(
        events: [
          EvalEvent(id: 'd1', timeMs: 5, type: EvalEventType.onset),
          EvalEvent(id: 'd2', timeMs: 505, type: EvalEventType.onset),
        ],
        chordSegments: [EvalChordSegment(label: 'C', startMs: 0, endMs: 1000)],
        tempoBpm: 119,
        beatsMs: const [0, 500],
        pitchPoints: const [],
      ),
      confidenceObservations: [
        ConfidenceObservation(rawScore: 0.6, correct: true),
      ],
    ),
    GroundTruthCase(
      id: 'case-b',
      tempoBand: TempoBand.fast,
      signalQualityTier: SignalQualityTier.noisy,
      mode: EvalMode.monophonic,
      expected: AnnotationSet(
        events: [EvalEvent(id: 'n1', timeMs: 0, type: EvalEventType.noteOnset)],
        pitchPoints: [PitchPoint(timeMs: 0, hz: 220)],
      ),
      detected: AnnotationSet(
        events: [EvalEvent(id: 'm1', timeMs: 10, type: EvalEventType.noteOnset)],
        pitchPoints: [PitchPoint(timeMs: 0, hz: 221)],
      ),
    ),
  ],
);

void main() {
  final runner = const EvaluationRunner();

  test(
    'the same manifest run twice produces a byte-identical report JSON',
    () {
      final manifest = _sampleManifest();
      final first = runner.run(manifest).toDeterministicJson();
      final second = runner.run(manifest).toDeterministicJson();
      expect(utf8.encode(second), orderedEquals(utf8.encode(first)));
      expect(first, isNot(contains(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}'))));
    },
  );

  test(
    'the report JSON never contains an absolute filesystem path or a '
    'username',
    () {
      final candidates = <GroundTruthManifest>[
        _sampleManifest(),
        GroundTruthManifest(
          schemaVersion: '1.0',
          cases: [
            GroundTruthCase(
              id: '/home/someone/clip.wav',
              tempoBand: TempoBand.notApplicable,
              signalQualityTier: SignalQualityTier.clean,
              mode: EvalMode.silence,
              expected: AnnotationSet(),
              detected: AnnotationSet(),
            ),
          ],
        ),
      ];
      for (final manifest in candidates) {
        final json = runner.run(manifest).toDeterministicJson();
        expect(json, isNot(contains('/home/')));
        expect(json, isNot(contains(RegExp(r'[A-Za-z]:\\'))));
      }
    },
  );

  test('EvaluationManifestParser + EvaluationRunner round-trip the ci_manifest.json fixture deterministically', () async {
    const parser = EvaluationManifestParser();
    final source = await File(
      'evaluation/analysis/fixtures/ci_manifest.json',
    ).readAsString();
    final manifest = parser.parseJsonString(source);
    final first = runner.run(manifest).toDeterministicJson();
    final second = runner.run(manifest).toDeterministicJson();
    expect(utf8.encode(second), orderedEquals(utf8.encode(first)));
    expect(first, isNot(contains('/home/')));
  });
}
