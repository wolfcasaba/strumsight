// E14-R27 (ADR 0539): the chord-engine comparison, pure half.
//
// What these cells prove:
//   * the comparison refuses an incomplete grid (a missing run) and a
//     mismatched input hash — two engines scored on different bytes are not
//     a comparison;
//   * consecutive same-label spans are merged before scoring, so an engine
//     that re-emits its chord every hop is not punished for it;
//   * the report's decision is the CONSTANT `NEEDS-MEASUREMENT`; nothing in
//     this file ranks the engines.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/chord_engine_comparison.dart';

void main() {
  final fixture = ChordComparisonFixture(
    fixtureId: 'c-then-am',
    inputSha256: 'hash-1',
    durationSec: 3,
    expected: <ChordTimelineSegment>[
      ChordTimelineSegment(label: 'C', startSec: 0, endSec: 1.5),
      ChordTimelineSegment(label: 'Am', startSec: 1.5, endSec: 3),
    ],
  );

  ChordEngineRun runFor(String engineId, List<ChordTimelineSegment> segments) =>
      ChordEngineRun(
        engineId: engineId,
        fixtureId: fixture.fixtureId,
        inputSha256: 'hash-1',
        segments: segments,
      );

  test('a perfect and a shifted engine are BOTH scored, and no winner is '
      'declared', () {
    final report = compareChordEngines(
      fixtures: <ChordComparisonFixture>[fixture],
      runs: <ChordEngineRun>[
        runFor('engine-a', <ChordTimelineSegment>[
          ChordTimelineSegment(label: 'C', startSec: 0, endSec: 1.5),
          ChordTimelineSegment(label: 'Am', startSec: 1.5, endSec: 3),
        ]),
        runFor('engine-b', <ChordTimelineSegment>[
          ChordTimelineSegment(label: 'C', startSec: 0, endSec: 2),
          ChordTimelineSegment(label: 'G', startSec: 2, endSec: 3),
        ]),
      ],
    );

    expect(report.engineIds, <String>['engine-a', 'engine-b']);
    expect(report.metricsByEngine.keys, hasLength(2));
    expect(report.decision, 'NEEDS-MEASUREMENT');
    expect(
      report.metricsByEngine['engine-a']!.chordWeightedAccuracy.value,
      1,
    );
    // engine-b is scored too — the report says what it measured, and stops
    // there.
    expect(
      report.metricsByEngine['engine-b']!.chordWeightedAccuracy.value,
      isNotNull,
    );
  });

  test('consecutive same-label spans are merged before scoring', () {
    final report = compareChordEngines(
      fixtures: <ChordComparisonFixture>[fixture],
      runs: <ChordEngineRun>[
        runFor('hop-emitter', <ChordTimelineSegment>[
          ChordTimelineSegment(label: 'C', startSec: 0, endSec: 0.5),
          ChordTimelineSegment(label: 'C', startSec: 0.5, endSec: 1),
          ChordTimelineSegment(label: 'C', startSec: 1, endSec: 1.5),
          ChordTimelineSegment(label: 'Am', startSec: 1.5, endSec: 3),
        ]),
      ],
    );

    expect(
      report.metricsByEngine['hop-emitter']!.chordWeightedAccuracy.value,
      1,
    );
  });

  test('a missing run for one fixture is a typed failure, not a smaller '
      'comparison', () {
    expect(
      () => compareChordEngines(
        fixtures: <ChordComparisonFixture>[
          fixture,
          ChordComparisonFixture(
            fixtureId: 'second',
            inputSha256: 'hash-2',
            durationSec: 1,
            expected: <ChordTimelineSegment>[
              ChordTimelineSegment(label: 'C', startSec: 0, endSec: 1),
            ],
          ),
        ],
        runs: <ChordEngineRun>[runFor('engine-a', const [])],
      ),
      throwsA(
        isA<ChordComparisonException>().having(
          (e) => e.kind,
          'kind',
          ChordComparisonErrorKind.incompleteCoverage,
        ),
      ),
    );
  });

  test('a mismatched input hash is a typed failure', () {
    expect(
      () => compareChordEngines(
        fixtures: <ChordComparisonFixture>[fixture],
        runs: <ChordEngineRun>[
          ChordEngineRun(
            engineId: 'engine-a',
            fixtureId: fixture.fixtureId,
            inputSha256: 'a-different-hash',
            segments: const <ChordTimelineSegment>[],
          ),
        ],
      ),
      throwsA(
        isA<ChordComparisonException>().having(
          (e) => e.kind,
          'kind',
          ChordComparisonErrorKind.inputHashMismatch,
        ),
      ),
    );
  });

  test('two runs of the same engine on the same fixture are a typed '
      'failure', () {
    expect(
      () => compareChordEngines(
        fixtures: <ChordComparisonFixture>[fixture],
        runs: <ChordEngineRun>[
          runFor('engine-a', const []),
          runFor('engine-a', const []),
        ],
      ),
      throwsA(
        isA<ChordComparisonException>().having(
          (e) => e.kind,
          'kind',
          ChordComparisonErrorKind.duplicateRun,
        ),
      ),
    );
  });

  test('the rendered table names every engine, every declared metric and '
      'the decision, and says which metrics it omits', () {
    final report = compareChordEngines(
      fixtures: <ChordComparisonFixture>[fixture],
      runs: <ChordEngineRun>[
        runFor('engine-a', <ChordTimelineSegment>[
          ChordTimelineSegment(label: 'C', startSec: 0, endSec: 3),
        ]),
        runFor('engine-b', <ChordTimelineSegment>[
          ChordTimelineSegment(label: 'Am', startSec: 0, endSec: 3),
        ]),
      ],
    );

    final markdown = report.renderMarkdown();

    expect(markdown, contains('NEEDS-MEASUREMENT'));
    expect(markdown, contains('engine-a'));
    expect(markdown, contains('engine-b'));
    expect(markdown, contains('hash-1'));
    for (final metricPath in chordComparisonMetricPaths) {
      expect(markdown, contains(metricPath));
    }
    expect(markdown, contains('omitted on purpose'));
    // Deterministic: the same report renders identically twice.
    expect(report.renderMarkdown(), markdown);
  });
}
