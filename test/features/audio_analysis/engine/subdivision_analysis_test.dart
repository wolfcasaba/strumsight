import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('SubdivisionAnalysis', () {
    test('recognises clean quarter notes as subdivision one', () {
      final result = const SubdivisionAnalyzer().analyze(
        events: _events(const <int>[
          0,
          1000,
          2000,
          3000,
          4000,
          5000,
          6000,
          7000,
        ]),
        beatGrid: _grid(),
      );

      expect(result.status, CapabilityStatus.available);
      expect(result.subdivision, 1);
    });

    test('recognises clean eighth notes as subdivision two', () {
      final result = const SubdivisionAnalyzer().analyze(
        events: _events(const <int>[
          0,
          500,
          1000,
          1500,
          2000,
          2500,
          3000,
          3500,
        ]),
        beatGrid: _grid(),
      );

      expect(result.status, CapabilityStatus.available);
      expect(result.subdivision, 2);
    });

    test('recognises clean triplets as subdivision three', () {
      final result = const SubdivisionAnalyzer().analyze(
        events: _events(const <int>[
          0,
          333,
          667,
          1000,
          1333,
          1667,
          2000,
          2333,
          2667,
        ]),
        beatGrid: _grid(),
      );

      expect(result.status, CapabilityStatus.available);
      expect(result.subdivision, 3);
    });

    test('recognises clean sixteenths as subdivision four', () {
      final result = const SubdivisionAnalyzer().analyze(
        events: _events(const <int>[0, 250, 500, 750, 1000, 1250, 1500, 1750]),
        beatGrid: _grid(),
      );

      expect(result.status, CapabilityStatus.available);
      expect(result.subdivision, 4);
    });

    test(
      'marks candidates within the inclusive five percent boundary ambiguous',
      () {
        final result = SubdivisionAnalysis.forCandidateDeviations(
          candidateDeviations: const <int, double>{
            1: 1.2,
            2: 1.0,
            3: 1.05,
            4: 1.3,
          },
        );

        expect(result.status, CapabilityStatus.degraded);
        expect(result.subdivision, isNull);
      },
    );

    test('keeps a 1.049 ratio ambiguous and a 1.051 ratio decisive', () {
      final below = SubdivisionAnalysis.forCandidateDeviations(
        candidateDeviations: const <int, double>{
          1: 1.2,
          2: 1.0,
          3: 1.049,
          4: 1.3,
        },
      );
      final above = SubdivisionAnalysis.forCandidateDeviations(
        candidateDeviations: const <int, double>{
          1: 1.2,
          2: 1.0,
          3: 1.051,
          4: 1.3,
        },
      );

      expect(below.status, CapabilityStatus.degraded);
      expect(above.status, CapabilityStatus.available);
      expect(above.subdivision, 2);
    });
  });
}

BeatGrid _grid() => BeatGrid(
  beats: <BeatPoint>[
    for (var index = 0; index < 9; index++)
      BeatPoint(
        index: index,
        time: Duration(milliseconds: index * 1000),
        confidence: 1,
        source: BeatSource.target,
      ),
  ],
  bars: const <BarPoint>[],
  beatsPerBar: 4,
  beatsPerBarSource: BeatsPerBarSource.target,
  status: CapabilityStatus.available,
  meterStatus: CapabilityStatus.available,
);

List<AnalysisEvent> _events(List<int> milliseconds) => <AnalysisEvent>[
  for (var index = 0; index < milliseconds.length; index++)
    OnsetEvent(
      id: 'event-$index',
      time: Duration(milliseconds: milliseconds[index]),
      confidence: 1,
    ),
];
