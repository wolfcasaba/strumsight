import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/debrief/deterministic_coach.dart';
import 'package:strumsight/features/ai_tutor/application/debrief/session_debrief_builder.dart';
import 'package:strumsight/features/ai_tutor/domain/models/coaching_insight.dart';
import 'package:strumsight/features/ai_tutor/domain/models/debrief_fact.dart';

void main() {
  const builder = SessionDebriefBuilder();
  const coach = DeterministicCoach();

  test('keeps legacy bias-late as the one primary priority focus', () {
    final insight = coach.coach(
      builder.build(
        _input(
          pairedEventCount: 20,
          lateShareBasisPoints: 8000,
          wrongDirectionRateBasisPoints: 5000,
          chordAccuracyBasisPoints: 4000,
        ),
      ),
    );

    expect(insight.code, 'practice.insight.bias_late');
    expect(insight.priority, 10);
    expect(insight.evidenceRefs, equals(<String>['session.current']));
  });

  test('chooses legacy direction and chord codes in their fixed order', () {
    final direction = coach.coach(
      builder.build(
        _input(pairedEventCount: 8, wrongDirectionRateBasisPoints: 4000),
      ),
    );
    final chord = coach.coach(
      builder.build(
        _input(pairedEventCount: 8, chordAccuracyBasisPoints: 5999),
      ),
    );

    expect(direction.code, 'practice.insight.direction_error');
    expect(chord.code, 'practice.insight.chord_error');
  });

  test('uses the stable fact code as its deterministic tie break', () {
    final facts = <DebriefFact>[
      DebriefFact(
        code: 'timing.lateBias',
        value: 8000,
        provenance: DebriefFactProvenance.measuredFact,
        confidence: 8000,
        priority: 10,
        evidenceRefs: const <String>['session.current'],
      ),
      DebriefFact(
        code: 'chord.lowAccuracy',
        value: 5999,
        provenance: DebriefFactProvenance.measuredFact,
        confidence: 8000,
        priority: 10,
        evidenceRefs: const <String>['session.current'],
      ),
    ];

    expect(coach.coach(facts).code, 'practice.insight.chord_error');
    expect(coach.coach(facts.reversed).code, 'practice.insight.chord_error');
  });

  test('renders every acceptance scenario from both ARB catalogs', () {
    final english = _arb('en');
    final hungarian = _arb('hu');
    final scenarios = <CoachingInsight>[
      coach.coach(
        builder.build(_input(pairedEventCount: 20, lateShareBasisPoints: 8000)),
      ),
      coach.coach(
        builder.build(
          _input(pairedEventCount: 8, wrongDirectionRateBasisPoints: 4000),
        ),
      ),
      coach.coach(
        builder.build(
          _input(pairedEventCount: 8, chordAccuracyBasisPoints: 5999),
        ),
      ),
      coach.coach(builder.build(_input(pairedEventCount: 8))),
      coach.coach(
        builder.build(
          _input(
            pairedEventCount: 8,
            currentScoreBasisPoints: 8000,
            previousEvidenceRef: 'session.previous',
            previousComparisonKey: 'rhythm.90',
            previousScoreBasisPoints: 6000,
          ),
        ),
      ),
      coach.coach(
        builder.build(
          _input(
            pairedEventCount: 8,
            currentScoreBasisPoints: 8000,
            previousEvidenceRef: 'session.previous',
            previousComparisonKey: 'rhythm.120',
            previousScoreBasisPoints: 6000,
          ),
        ),
      ),
    ];

    for (final insight in scenarios) {
      final en = coach.localize(insight: insight, lookup: _lookup(english));
      final hu = coach.localize(insight: insight, lookup: _lookup(hungarian));

      expect(en.title, isNotEmpty);
      expect(en.explanation, isNotEmpty);
      expect(en.action, isNotEmpty);
      expect(hu.title, isNotEmpty);
      expect(hu.explanation, isNotEmpty);
      expect(hu.action, isNotEmpty);
    }
  });

  test(
    'uses explicit uncertainty text for low evidence without a zero claim',
    () {
      final insight = coach.coach(
        builder.build(_input(pairedEventCount: 7, lateShareBasisPoints: 8000)),
      );
      final english = coach.localize(
        insight: insight,
        lookup: _lookup(_arb('en')),
      );
      final hungarian = coach.localize(
        insight: insight,
        lookup: _lookup(_arb('hu')),
      );

      expect(insight.uncertainty, CoachingUncertainty.lowEvidence);
      expect(english.uncertaintyText, isNotEmpty);
      expect(hungarian.uncertaintyText, isNotEmpty);
      expect(english.explanation, isNot(contains('0%')));
      expect(hungarian.explanation, isNot(contains('0%')));
    },
  );

  test(
    'grounding invariant rejects an insight after evidence refs are dropped',
    () {
      final groundedInsights = <CoachingInsight>[
        coach.coach(
          builder.build(
            _input(pairedEventCount: 20, lateShareBasisPoints: 8000),
          ),
        ),
        coach.coach(
          builder.build(
            _input(pairedEventCount: 8, wrongDirectionRateBasisPoints: 4000),
          ),
        ),
        coach.coach(
          builder.build(
            _input(pairedEventCount: 8, chordAccuracyBasisPoints: 5999),
          ),
        ),
      ];

      for (final insight in groundedInsights) {
        expect(insight.evidenceRefs, isNotEmpty);
      }
      expect(
        () => CoachingInsight(
          code: 'practice.insight.bias_late',
          titleLocalizationKey: 'aiTutorCoachLateBiasTitle',
          explanationLocalizationKey: 'aiTutorCoachLateBiasExplanation',
          evidenceRefs: const <String>[],
          priority: 10,
          suggestedActionTemplate: 'aiTutorCoachActionRhythmOnly',
          uncertainty: CoachingUncertainty.none,
          hasConflictingEvidence: false,
        ),
        throwsArgumentError,
      );
    },
  );

  test('localized coaching never claims a visual or camera diagnosis', () {
    final english = _arb('en');
    final hungarian = _arb('hu');
    final texts = <String>[
      for (final entry in english.entries)
        if (entry.key.startsWith('aiTutorCoach')) entry.value,
      for (final entry in hungarian.entries)
        if (entry.key.startsWith('aiTutorCoach')) entry.value,
    ];

    expect(
      texts.join(' ').toLowerCase(),
      isNot(
        matches(
          RegExp(
            r'camera|visual|finger|hand|fret|kamera|vizuális|ujj|kéz|bund',
          ),
        ),
      ),
    );
  });
}

Map<String, String> _arb(String locale) {
  final decoded =
      jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, Object?>;
  return <String, String>{
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.key: entry.value! as String,
  };
}

String Function(String) _lookup(Map<String, String> values) =>
    (key) => values[key]!;

SessionDebriefInput _input({
  required int pairedEventCount,
  int? timingBiasMilliseconds,
  int? lateShareBasisPoints,
  int? wrongDirectionRateBasisPoints,
  int? chordAccuracyBasisPoints,
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
  currentScoreBasisPoints: currentScoreBasisPoints,
  previousEvidenceRef: previousEvidenceRef,
  previousComparisonKey: previousComparisonKey,
  previousScoreBasisPoints: previousScoreBasisPoints,
);
