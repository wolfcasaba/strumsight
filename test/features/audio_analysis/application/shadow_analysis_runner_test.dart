import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/analyze/engine/clip_analyzer.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

import '../../../support/synth.dart';

void main() {
  group('ShadowAnalysisRunner', () {
    for (final fixture in _fixtures) {
      test('keeps the V1 result byte-identical for ${fixture.label}', () async {
        var v2Starts = 0;
        final runner = ShadowAnalysisRunner(
          v1Analyze: const ClipAnalyzer().analyze,
          v2Runner: _Runner(() {
            v2Starts++;
            return AnalysisRunResult(
              completion: AnalysisCompletionStatus.complete,
              document: _document(),
            );
          }),
        );
        final expected = const ClipAnalyzer().analyze(
          fixture.samples,
          fixture.sampleRate,
        );

        final actual = await runner.run(
          samples: fixture.samples,
          sampleRate: fixture.sampleRate,
          v2Input: _document(),
          labModeActive: true,
          audioAnalysisV2Enabled: true,
        );

        expect(
          jsonEncode(actual.v1Result.toJson()),
          jsonEncode(expected.toJson()),
        );
        expect(v2Starts, 1, reason: 'the full Lab gate is open');
      });
    }

    test('isolates a throwing V2 runner from the V1 result', () async {
      final runner = ShadowAnalysisRunner(
        v1Analyze: _v1,
        v2Runner: _Runner(() => throw StateError('V2 failure')),
      );

      final result = await runner.run(
        samples: const <double>[0],
        sampleRate: 44100,
        v2Input: _document(),
        labModeActive: true,
        audioAnalysisV2Enabled: true,
      );

      expect(result.v1Result, _v1(const <double>[0], 44100));
      expect(result.diffReport!.v2Failed, isTrue);
    });

    test('isolates a cancelled V2 run from the V1 result', () async {
      final runner = ShadowAnalysisRunner(
        v1Analyze: _v1,
        v2Runner: _Runner(
          () => const AnalysisRunResult(
            completion: AnalysisCompletionStatus.cancelled,
          ),
        ),
      );

      final result = await runner.run(
        samples: const <double>[0],
        sampleRate: 44100,
        v2Input: _document(),
        labModeActive: true,
        audioAnalysisV2Enabled: true,
      );

      expect(result.v1Result, _v1(const <double>[0], 44100));
      expect(result.diffReport!.v2Failed, isTrue);
    });

    for (final cell in <({bool labMode, bool flag, int starts})>[
      (labMode: false, flag: false, starts: 0),
      (labMode: false, flag: true, starts: 0),
      (labMode: true, flag: false, starts: 0),
      (labMode: true, flag: true, starts: 1),
    ]) {
      test(
        'starts V2 only for Lab=${cell.labMode}, flag=${cell.flag}',
        () async {
          var starts = 0;
          final runner = ShadowAnalysisRunner(
            v1Analyze: _v1,
            v2Runner: _Runner(() {
              starts++;
              return AnalysisRunResult(
                completion: AnalysisCompletionStatus.complete,
                document: _document(),
              );
            }),
          );

          final result = await runner.run(
            samples: const <double>[0],
            sampleRate: 44100,
            v2Input: _document(),
            labModeActive: cell.labMode,
            audioAnalysisV2Enabled: cell.flag,
          );

          expect(starts, cell.starts);
          expect(result.v1Result, _v1(const <double>[0], 44100));
          expect(result.diffReport, cell.starts == 1 ? isNotNull : isNull);
        },
      );
    }
  });
}

final _fixtures = <({String label, List<double> samples, int sampleRate})>[
  (label: 'silence', samples: List<double>.filled(44100, 0), sampleRate: 44100),
  (
    label: 'two chords',
    samples: _join(<List<double>>[
      chordSignal(cMajorFreqs, seconds: .08),
      chordSignal(gMajorFreqs, seconds: .08),
    ]),
    sampleRate: 44100,
  ),
  (
    label: 'four chords C G Am F',
    samples: _join(<List<double>>[
      chordSignal(cMajorFreqs, seconds: .08),
      chordSignal(gMajorFreqs, seconds: .08),
      chordSignal(aMinorFreqs, seconds: .08),
      chordSignal(fMajorFreqs, seconds: .08),
    ]),
    sampleRate: 44100,
  ),
  (
    label: 'ring-out overlap',
    samples: overlappingStrums(lowFirstPerStrum: <bool>[true, false]),
    sampleRate: 44100,
  ),
  (
    label: 'single strum',
    samples: strumSignal(lowFirst: true),
    sampleRate: 44100,
  ),
  (
    label: 'known BPM strum sequence',
    samples: strumPattern(lowFirstPerStrum: <bool>[true, false]),
    sampleRate: 44100,
  ),
  (
    label: 'throwing refiner fallback',
    samples: strumPattern(lowFirstPerStrum: <bool>[true]),
    sampleRate: 44100,
  ),
  (label: 'empty input', samples: const <double>[], sampleRate: 44100),
  (label: 'sample rate zero', samples: const <double>[], sampleRate: 0),
];

AnalyzeResult _v1(List<double> _, int _) => AnalyzeResult.empty;

List<double> _join(List<List<double>> clips) => <double>[
  for (final clip in clips) ...clip,
];

AnalysisDocument _document() => AnalysisDocument(
  id: 'shadow-document',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 13),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.importedFile,
    duration: const Duration(seconds: 1),
    sampleRate: 44100,
    channelCount: 1,
    fingerprint: 'shadow-fixture',
  ),
  provenance: AnalysisProvenance(
    appVersion: 'test',
    analyzerVersion: 'test',
    pipelineVersion: 'test',
    stageVersions: const <String, String>{},
    dspConfigHash: 'test',
    modelManifestIds: const <String>[],
    inputFingerprint: 'shadow-fixture',
    platform: 'test',
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
    duration: const Duration(seconds: 1),
    events: <AnalysisEvent>[
      OnsetEvent(
        id: 'event-1',
        time: const Duration(milliseconds: 100),
        confidence: 0.5,
      ),
    ],
    chordSegments: <ChordSegment>[
      ChordSegment(
        label: 'C',
        start: Duration.zero,
        end: const Duration(seconds: 1),
        confidence: 0.5,
      ),
    ],
    tempoPoints: <TempoPoint>[TempoPoint(time: Duration.zero, bpm: 120)],
  ),
  metrics: const <AnalysisMetricResult>[],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);

final class _Runner implements AnalysisRunner {
  _Runner(this._result);

  final AnalysisRunResult Function() _result;

  @override
  AnalysisRunHandle start(AnalysisDocument _) => _Handle(_result());
}

final class _Handle implements AnalysisRunHandle {
  const _Handle(this._value);

  final AnalysisRunResult _value;

  @override
  Future<void> cancel() async {}

  @override
  Stream<AnalysisProgressEvent> get progress => const Stream.empty();

  @override
  Future<AnalysisRunResult> get result =>
      Future<AnalysisRunResult>.value(_value);

  @override
  String get runId => 'shadow-test';
}
