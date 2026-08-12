import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/analyze/engine/clip_analyzer.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/clip_analyzer_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/legacy_evidence.dart';

import '../../../support/synth.dart';

void main() {
  group('ClipAnalyzer V1 to stage parity', () {
    for (final fixture in _fixtures) {
      test('matches the V1 timeline for ${fixture.label}', () async {
        final legacy = fixture.v1(fixture.samples, fixture.sampleRate);
        final evidence = await _run(
          LegacyClipAnalyzerInput(
            samples: fixture.samples,
            sampleRate: fixture.sampleRate,
            strumRefinerWeights: fixture.stageWeights,
          ),
        );

        _expectParity(
          LegacyEvidence.fromAnalyzeResult(
            legacy,
            call: LegacyClipAnalyzerCall(
              sampleRate: fixture.sampleRate,
              sampleCount: fixture.samples.length,
              labMode: false,
              hasCandidateStrumRefiner: fixture.stageWeights != null,
            ),
            provenance: evidence.provenance,
          ),
          evidence,
          fixture.label,
        );
      });
    }
  });
}

final _fixtures = <_ParityFixture>[
  _ParityFixture('silence', List<double>.filled(44100, 0)),
  _ParityFixture(
    'two chords',
    _join([
      chordSignal(cMajorFreqs, seconds: 0.8),
      chordSignal(gMajorFreqs, seconds: 0.8),
    ]),
  ),
  _ParityFixture(
    'four chords C G Am F',
    _join([
      chordSignal(cMajorFreqs, seconds: 0.8),
      chordSignal(gMajorFreqs, seconds: 0.8),
      chordSignal(aMinorFreqs, seconds: 0.8),
      chordSignal(fMajorFreqs, seconds: 0.8),
    ]),
  ),
  _ParityFixture(
    'ring-out overlap',
    overlappingStrums(
      lowFirstPerStrum: [true, false, true, false],
      gapSeconds: 0.25,
    ),
  ),
  _ParityFixture('single strum', strumSignal(lowFirst: true)),
  _ParityFixture(
    'known BPM strum sequence',
    strumPattern(lowFirstPerStrum: [true, false, true, false], gapSeconds: 0.5),
  ),
  _ParityFixture(
    'throwing refiner fallback',
    strumPattern(lowFirstPerStrum: [true, false, true]),
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

Future<LegacyEvidence> _run(LegacyClipAnalyzerInput input) async {
  final result = await const ClipAnalyzerStage().run(
    input,
    AnalysisStageContext(
      runId: 'clip-analyzer-parity-test',
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

void _expectParity(
  LegacyEvidence expected,
  LegacyEvidence actual,
  String label,
) {
  expect(actual.chords, hasLength(expected.chords.length), reason: label);
  for (var index = 0; index < expected.chords.length; index++) {
    final legacy = expected.chords[index];
    final stage = actual.chords[index];
    expect(stage.label, legacy.label, reason: '$label chord=$index label');
    expect(
      (stage.start - legacy.start).inMicroseconds.abs(),
      lessThanOrEqualTo(1),
      reason: '$label chord=$index start',
    );
    expect(
      (stage.end - legacy.end).inMicroseconds.abs(),
      lessThanOrEqualTo(1),
      reason: '$label chord=$index end',
    );
  }
  expect(actual.strums, hasLength(expected.strums.length), reason: label);
  for (var index = 0; index < expected.strums.length; index++) {
    final legacy = expected.strums[index];
    final stage = actual.strums[index];
    expect(
      stage.direction,
      legacy.direction,
      reason: '$label strum=$index direction',
    );
    expect(
      stage.confidence,
      legacy.confidence,
      reason: '$label strum=$index confidence',
    );
    expect(
      (stage.time - legacy.time).inMicroseconds.abs(),
      lessThanOrEqualTo(1),
      reason: '$label strum=$index time',
    );
  }
  expect((actual.bpm - expected.bpm).abs(), lessThanOrEqualTo(1e-9));
}
