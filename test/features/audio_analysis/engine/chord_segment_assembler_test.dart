import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/harmony/chord_frame_evidence.dart';
import 'package:strumsight/features/audio_analysis/engine/harmony/chord_segment_assembler.dart';
import 'package:strumsight/features/audio_analysis/engine/harmony/decoder_source.dart';

const _second = Duration(seconds: 1);

ChordFrameEvidence _frame(
  int milliseconds,
  String? label, {
  double confidence = 0.8,
  DecoderSource source = DecoderSource.dsp,
}) => ChordFrameEvidence.complete(
  time: Duration(milliseconds: milliseconds),
  topLabel: label,
  topConfidence: label == null ? null : confidence,
  noChordProbability: label == null ? 1 : 0,
  tonalness: label == null ? 0 : 1,
  source: source,
);

void _expectSegment(
  Object actual, {
  required String label,
  required int startMilliseconds,
  required int endMilliseconds,
}) {
  final segment = actual as dynamic;
  expect(segment.label, label);
  expect(segment.start, Duration(milliseconds: startMilliseconds));
  expect(segment.end, Duration(milliseconds: endMilliseconds));
}

void main() {
  const assembler = ChordSegmentAssembler();

  group('V1 parity policy', () {
    final fixtures = <String, List<ChordFrameEvidence>>{
      'C to G': <ChordFrameEvidence>[_frame(0, 'C'), _frame(800, 'G')],
      'C G Am F': <ChordFrameEvidence>[
        _frame(0, 'C'),
        _frame(800, 'G'),
        _frame(1600, 'Am'),
        _frame(2400, 'F'),
      ],
      'ring-out overlap': <ChordFrameEvidence>[
        _frame(0, 'C'),
        _frame(250, 'G'),
        _frame(500, 'Am'),
      ],
      'fast transition': <ChordFrameEvidence>[_frame(0, 'C'), _frame(299, 'G')],
      'silence gap': <ChordFrameEvidence>[
        _frame(0, 'C'),
        _frame(400, null),
        _frame(600, 'C'),
      ],
      'all no-chord': <ChordFrameEvidence>[_frame(0, null), _frame(500, null)],
    };

    for (final entry in fixtures.entries) {
      test('${entry.key} retains V1 boundaries by default', () {
        final clipDuration = entry.key == 'C G Am F'
            ? const Duration(milliseconds: 3200)
            : _second;
        final segments = assembler.assemble(
          frames: entry.value,
          clipDuration: clipDuration,
        );

        switch (entry.key) {
          case 'C to G':
            expect(segments, hasLength(2));
            _expectSegment(
              segments[0],
              label: 'C',
              startMilliseconds: 0,
              endMilliseconds: 800,
            );
            _expectSegment(
              segments[1],
              label: 'G',
              startMilliseconds: 800,
              endMilliseconds: 1000,
            );
          case 'C G Am F':
            expect(segments, hasLength(4));
            for (var index = 0; index < 4; index++) {
              _expectSegment(
                segments[index],
                label: const <String>['C', 'G', 'Am', 'F'][index],
                startMilliseconds: index * 800,
                endMilliseconds: index == 3 ? 3200 : (index + 1) * 800,
              );
            }
          case 'ring-out overlap':
            expect(segments, hasLength(3));
            _expectSegment(
              segments[0],
              label: 'C',
              startMilliseconds: 0,
              endMilliseconds: 250,
            );
            _expectSegment(
              segments[1],
              label: 'G',
              startMilliseconds: 250,
              endMilliseconds: 500,
            );
            _expectSegment(
              segments[2],
              label: 'Am',
              startMilliseconds: 500,
              endMilliseconds: 1000,
            );
          case 'fast transition':
            expect(segments, hasLength(2));
            _expectSegment(
              segments[0],
              label: 'C',
              startMilliseconds: 0,
              endMilliseconds: 299,
            );
            _expectSegment(
              segments[1],
              label: 'G',
              startMilliseconds: 299,
              endMilliseconds: 1000,
            );
          case 'silence gap':
            expect(segments, hasLength(1));
            _expectSegment(
              segments.single,
              label: 'C',
              startMilliseconds: 0,
              endMilliseconds: 1000,
            );
          case 'all no-chord':
            expect(segments, isEmpty);
        }
      });
    }
  });

  test(
    'closeOnNoChord closes a silence gap when the non-default policy opts in',
    () {
      final segments = assembler.assemble(
        frames: <ChordFrameEvidence>[
          _frame(0, 'C'),
          _frame(400, null),
          _frame(600, 'C'),
        ],
        clipDuration: _second,
        policy: const ChordSegmentationPolicy(
          minimumSegment: Duration(microseconds: 1),
          closeOnNoChord: true,
        ),
      );

      expect(segments, hasLength(2));
      _expectSegment(
        segments[0],
        label: 'C',
        startMilliseconds: 0,
        endMilliseconds: 400,
      );
      _expectSegment(
        segments[1],
        label: 'C',
        startMilliseconds: 600,
        endMilliseconds: 1000,
      );
    },
  );

  test(
    'minimum duration keeps the inclusive 200ms boundary and merges only below it',
    () {
      for (final fixture in <({int length, int expectedCount})>[
        (length: 199, expectedCount: 2),
        (length: 200, expectedCount: 3),
        (length: 201, expectedCount: 3),
      ]) {
        final segments = assembler.assemble(
          frames: <ChordFrameEvidence>[
            _frame(0, 'C'),
            _frame(400, 'G'),
            _frame(400 + fixture.length, 'Am'),
          ],
          clipDuration: const Duration(seconds: 1),
          policy: const ChordSegmentationPolicy(
            minimumSegment: Duration(milliseconds: 200),
          ),
        );

        expect(
          segments,
          hasLength(fixture.expectedCount),
          reason: '${fixture.length}ms',
        );
        expect(segments.last.end, const Duration(seconds: 1));
      }
    },
  );

  test(
    'transient merge remains opt-in and absorbs only a short middle span',
    () {
      final frames = <ChordFrameEvidence>[
        _frame(0, 'C'),
        _frame(400, 'G'),
        _frame(550, 'C'),
      ];
      final defaultSegments = assembler.assemble(
        frames: frames,
        clipDuration: _second,
      );
      final mergedSegments = assembler.assemble(
        frames: frames,
        clipDuration: _second,
        policy: const ChordSegmentationPolicy(
          mergeTransientSegments: true,
          transientMergeWindow: Duration(milliseconds: 200),
        ),
      );

      expect(defaultSegments, hasLength(3));
      expect(mergedSegments, hasLength(2));
      _expectSegment(
        mergedSegments.first,
        label: 'C',
        startMilliseconds: 0,
        endMilliseconds: 550,
      );
    },
  );

  test('derived evidence is preserved without inventing top-k values', () {
    final evidence = ChordFrameEvidence.derived(
      time: Duration.zero,
      topLabel: 'C',
      source: DecoderSource.dsp,
    );

    expect(evidence.evidenceCompleteness, EvidenceCompleteness.derived);
    expect(evidence.topK, isEmpty);
    expect(evidence.topConfidence, isNull);
    expect(evidence.noChordProbability, isNull);
  });

  test(
    'aggregates frame confidence using each frame duration as its weight',
    () {
      final segments = assembler.assemble(
        frames: <ChordFrameEvidence>[
          _frame(0, 'C', confidence: 0.2),
          _frame(250, 'C', confidence: 0.8),
          _frame(500, 'G', confidence: 0.4),
        ],
        clipDuration: _second,
      );

      expect(segments.first.confidence, 0.5);
    },
  );

  test(
    'experimental fusion retains agreement and lowers confidence on disagreement',
    () {
      final dsp = assembler.assemble(
        frames: <ChordFrameEvidence>[_frame(0, 'C', confidence: 0.8)],
        clipDuration: _second,
      );
      final agreeingMl = assembler.assemble(
        frames: <ChordFrameEvidence>[
          _frame(0, 'C', confidence: 0.7, source: DecoderSource.ml),
        ],
        clipDuration: _second,
      );
      final disagreeingMl = assembler.assemble(
        frames: <ChordFrameEvidence>[
          _frame(0, 'G', confidence: 0.6, source: DecoderSource.ml),
        ],
        clipDuration: _second,
      );

      expect(
        assembler.fuse(dsp: dsp, ml: agreeingMl, enabled: false),
        dsp,
        reason: 'flag-off stays exactly on the DSP path',
      );
      final agreement = assembler.fuse(dsp: dsp, ml: agreeingMl, enabled: true);
      expect(agreement.single.label, 'C');
      expect(agreement.single.source, DecoderSource.dsp);
      final disagreement = assembler.fuse(
        dsp: dsp,
        ml: disagreeingMl,
        enabled: true,
      );
      expect(disagreement.single.source, DecoderSource.fused);
      expect(disagreement.single.label, 'C');
      expect(disagreement.single.confidence, lessThan(dsp.single.confidence));
    },
  );
}
