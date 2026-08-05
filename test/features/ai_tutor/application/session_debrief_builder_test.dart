import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/debrief/session_debrief_builder.dart';
import 'package:strumsight/features/ai_tutor/domain/models/debrief_fact.dart';

void main() {
  const builder = SessionDebriefBuilder();

  test('preserves the documented bias-late coaching fixture facts', () {
    final facts = builder.build(
      _input(
        pairedEventCount: 20,
        lateShareBasisPoints: 8000,
        stableTempoBpm: 90,
      ),
    );

    expect(
      facts.map((fact) => fact.code),
      equals(<String>[
        'timing.lateBias',
        'practice.firstEvidence',
        'speed.stableAtBpm',
      ]),
    );
    final lateBias = _fact(facts, 'timing.lateBias');
    expect(lateBias.value, 8000);
    expect(lateBias.provenance, DebriefFactProvenance.measuredFact);
    expect(lateBias.evidenceRefs, equals(<String>['session.current']));
  });

  test(
    'uses the legacy paired-evidence threshold below at and above the bar',
    () {
      final below = builder.build(
        _input(pairedEventCount: 7, lateShareBasisPoints: 8000),
      );
      final at = builder.build(
        _input(pairedEventCount: 8, lateShareBasisPoints: 8000),
      );
      final above = builder.build(
        _input(pairedEventCount: 9, lateShareBasisPoints: 8000),
      );

      expect(below.map((fact) => fact.code), contains('practice.lowEvidence'));
      expect(
        below.map((fact) => fact.code),
        isNot(contains('timing.lateBias')),
      );
      expect(at.map((fact) => fact.code), contains('timing.lateBias'));
      expect(above.map((fact) => fact.code), contains('timing.lateBias'));
    },
  );

  test('keeps a first session separate from an improvement trend', () {
    final firstFacts = builder.build(_input(pairedEventCount: 8));
    final improvementFacts = builder.build(
      _input(
        pairedEventCount: 8,
        currentScoreBasisPoints: 8000,
        previousEvidenceRef: 'session.previous',
        previousComparisonKey: 'rhythm.90',
        previousScoreBasisPoints: 6000,
      ),
    );

    expect(
      firstFacts.map((fact) => fact.code),
      contains('practice.firstEvidence'),
    );
    expect(
      improvementFacts.map((fact) => fact.code),
      contains('practice.improvedFromPrevious'),
    );
    expect(
      improvementFacts.map((fact) => fact.code),
      isNot(contains('practice.firstEvidence')),
    );
    final improvement = _fact(
      improvementFacts,
      'practice.improvedFromPrevious',
    );
    expect(improvement.provenance, DebriefFactProvenance.computedTrend);
    expect(improvement.evidenceRefs, <String>[
      'session.current',
      'session.previous',
    ]);
    expect(improvement.comparableEvidenceGroupCount, 2);
  });

  test(
    'marks a prior non-comparable session without emitting an improvement',
    () {
      final facts = builder.build(
        _input(
          pairedEventCount: 8,
          currentScoreBasisPoints: 8000,
          previousEvidenceRef: 'session.previous',
          previousComparisonKey: 'rhythm.120',
          previousScoreBasisPoints: 6000,
        ),
      );

      expect(
        facts.map((fact) => fact.code),
        contains('practice.notComparableToPrevious'),
      );
      expect(
        facts.map((fact) => fact.code),
        isNot(contains('practice.improvedFromPrevious')),
      );
    },
  );

  test('produces direction chord consistency and stable-tempo facts', () {
    final facts = builder.build(
      _input(
        pairedEventCount: 8,
        wrongDirectionRateBasisPoints: 4000,
        chordAccuracyBasisPoints: 5999,
        sectionConsistencyBasisPoints: 6999,
        stableTempoBpm: 90,
      ),
    );

    expect(
      facts.map((fact) => fact.code),
      containsAll(<String>[
        'strum.wrongDirectionRate',
        'chord.lowAccuracy',
        'section.inconsistent',
        'speed.stableAtBpm',
      ]),
    );
  });

  test('rejects ungrounded facts and trends with fewer than two groups', () {
    expect(
      () => DebriefFact(
        code: 'timing.lateBias',
        value: 8000,
        provenance: DebriefFactProvenance.measuredFact,
        confidence: 8000,
        priority: 10,
        evidenceRefs: const <String>[],
      ),
      throwsArgumentError,
    );
    expect(
      () => DebriefFact(
        code: 'practice.improvedFromPrevious',
        value: 2000,
        provenance: DebriefFactProvenance.computedTrend,
        confidence: 4000,
        priority: 60,
        evidenceRefs: const <String>['session.current'],
        comparableEvidenceGroupCount: 1,
      ),
      throwsArgumentError,
    );
  });

  test('keeps facts and priority order stable for repeated input', () {
    final input = _input(
      pairedEventCount: 20,
      lateShareBasisPoints: 8000,
      wrongDirectionRateBasisPoints: 4000,
      chordAccuracyBasisPoints: 5999,
    );

    final first = builder.build(input);
    final repeated = builder.build(input);

    expect(
      first.map((fact) => fact.code),
      equals(repeated.map((fact) => fact.code)),
    );
    expect(
      first.map((fact) => fact.priority),
      orderedEquals(<int>[10, 20, 30, 70]),
    );
  });

  test('does not import a Practice feature implementation contract', () {
    final source = File(
      'lib/features/ai_tutor/application/debrief/session_debrief_builder.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('features/practice')));
  });
}

SessionDebriefInput _input({
  required int pairedEventCount,
  int? timingBiasMilliseconds,
  int? lateShareBasisPoints,
  int? wrongDirectionRateBasisPoints,
  int? chordAccuracyBasisPoints,
  int? sectionConsistencyBasisPoints,
  int? stableTempoBpm,
  int? currentScoreBasisPoints,
  String? previousEvidenceRef,
  String? previousComparisonKey,
  int? previousScoreBasisPoints,
}) => SessionDebriefInput(
  sessionEvidenceRef: 'session.current',
  comparisonKey: 'rhythm.90',
  pairedEventCount: pairedEventCount,
  timingBiasMilliseconds:
      timingBiasMilliseconds ?? (lateShareBasisPoints == null ? null : 30),
  lateShareBasisPoints: lateShareBasisPoints,
  wrongDirectionRateBasisPoints: wrongDirectionRateBasisPoints,
  chordAccuracyBasisPoints: chordAccuracyBasisPoints,
  sectionConsistencyBasisPoints: sectionConsistencyBasisPoints,
  stableTempoBpm: stableTempoBpm,
  currentScoreBasisPoints: currentScoreBasisPoints,
  previousEvidenceRef: previousEvidenceRef,
  previousComparisonKey: previousComparisonKey,
  previousScoreBasisPoints: previousScoreBasisPoints,
);

DebriefFact _fact(Iterable<DebriefFact> facts, String code) =>
    facts.singleWhere((fact) => fact.code == code);
