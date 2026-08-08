import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/application/feedback_policy_engine.dart';
import 'package:strumsight/features/vision/domain/evidence/evidence_provenance.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_evidence.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_observation.dart';
import 'package:strumsight/features/vision/domain/feedback/cue_budget.dart';
import 'package:strumsight/features/vision/domain/feedback/feedback_policy.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_definition.dart';
import 'package:strumsight/features/vision/domain/sync/sync_quality.dart';

void main() {
  group('FeedbackPolicyEngine', () {
    test('uses separate positive and negative confidence thresholds', () {
      final cases = <({InsightCode code, double confidence, bool emits})>[
        (code: InsightCode.frettingStable, confidence: 0.69, emits: false),
        (code: InsightCode.frettingStable, confidence: 0.70, emits: true),
        (code: InsightCode.frettingStable, confidence: 0.71, emits: true),
        (code: InsightCode.frettingFocus, confidence: 0.84, emits: false),
        (code: InsightCode.frettingFocus, confidence: 0.85, emits: true),
        (code: InsightCode.frettingFocus, confidence: 0.86, emits: true),
      ];

      for (final item in cases) {
        final decision = _engine().evaluate(<FeedbackCandidate>[
          _candidate(code: item.code, confidence: item.confidence),
        ]);
        expect(
          decision.insights.isNotEmpty,
          item.emits,
          reason: '${item.code.name} at ${item.confidence}',
        );
      }
    });

    test('prefers setup evidence over a simultaneous technical cue', () {
      final decision = _engine().evaluate(<FeedbackCandidate>[
        _candidate(
          code: InsightCode.frettingFocus,
          confidence: 0.9,
          id: 'technical',
        ),
        _candidate(
          code: InsightCode.setupNotObservable,
          state: ObservationState.notObservable,
          id: 'setup',
        ),
      ]);

      expect(decision.realtimeCue!.code, InsightCode.setupNotObservable);
      expect(decision.insights, hasLength(2));
    });

    test('selects an equal-priority candidate deterministically', () {
      final candidates = <FeedbackCandidate>[
        _candidate(
          code: InsightCode.frettingStable,
          confidence: 0.9,
          id: 'fretting',
        ),
        _candidate(
          code: InsightCode.frettingFocus,
          confidence: 0.9,
          id: 'focus',
        ),
      ];

      final first = _engine().evaluate(candidates).realtimeCue;
      final second = _engine().evaluate(candidates.reversed).realtimeCue;

      expect(first, second);
      expect(first!.code, InsightCode.frettingStable);
    });

    test(
      'uses confidence before direction to break equal-priority choices',
      () {
        final decision = _engine().evaluate(<FeedbackCandidate>[
          _candidate(
            code: InsightCode.frettingStable,
            confidence: 0.9,
            id: 'stable',
          ),
          _candidate(
            code: InsightCode.frettingFocus,
            confidence: 0.91,
            id: 'focus',
          ),
        ]);

        expect(decision.realtimeCue!.code, InsightCode.frettingFocus);
      },
    );

    test('only emits an improvement for valid comparable windows', () {
      final current = _candidate(
        code: InsightCode.frettingImproved,
        comparisonEvidence: _evidence(id: 'previous'),
        comparisonPracticeId: 'practice-1',
        comparisonCapabilityLevel: 'tracked',
      );
      final mismatchedPractice = _candidate(
        code: InsightCode.frettingImproved,
        comparisonEvidence: _evidence(id: 'previous'),
        comparisonPracticeId: 'practice-2',
        comparisonCapabilityLevel: 'tracked',
      );

      expect(
        _engine().evaluate(<FeedbackCandidate>[current]).insights,
        hasLength(1),
      );
      expect(
        _engine().evaluate(<FeedbackCandidate>[mismatchedPractice]).insights,
        isEmpty,
      );
    });

    test('rejects improvement with unobservable comparison evidence', () {
      final decision = _engine().evaluate(<FeedbackCandidate>[
        _candidate(
          code: InsightCode.frettingImproved,
          comparisonEvidence: _evidence(
            id: 'previous',
            state: ObservationState.notObservable,
          ),
          comparisonPracticeId: 'practice-1',
          comparisonCapabilityLevel: 'tracked',
        ),
      ]);

      expect(decision.insights, isEmpty);
    });

    test('rejects improvement with low-confidence comparison evidence', () {
      final decision = _engine().evaluate(<FeedbackCandidate>[
        _candidate(
          code: InsightCode.frettingImproved,
          comparisonEvidence: _evidence(id: 'previous', confidence: 0.01),
          comparisonPracticeId: 'practice-1',
          comparisonCapabilityLevel: 'tracked',
        ),
      ]);

      expect(decision.insights, isEmpty);
    });

    test('rejects a comparison window that is not strictly earlier', () {
      final decision = _engine().evaluate(<FeedbackCandidate>[
        _candidate(
          code: InsightCode.frettingImproved,
          comparisonEvidence: _evidence(
            id: 'previous',
            startUs: 1000000,
            endUs: 1500000,
          ),
          comparisonPracticeId: 'practice-1',
          comparisonCapabilityLevel: 'tracked',
        ),
      ]);

      expect(decision.insights, isEmpty);
    });

    test('rejects a comparison evidence with the primary evidence id', () {
      final decision = _engine().evaluate(<FeedbackCandidate>[
        _candidate(
          code: InsightCode.frettingImproved,
          id: 'same-window',
          comparisonEvidence: _evidence(id: 'same-window'),
          comparisonPracticeId: 'practice-1',
          comparisonCapabilityLevel: 'tracked',
        ),
      ]);

      expect(decision.insights, isEmpty);
    });

    test(
      'rejects a technical insight below its output confidence threshold',
      () {
        final decision = _engine().evaluate(<FeedbackCandidate>[
          _candidate(
            code: InsightCode.frettingFocus,
            confidence: 0.95,
            comparisonEvidence: _evidence(id: 'earlier', confidence: 0.02),
          ),
        ]);

        expect(decision.insights, isEmpty);
      },
    );

    test(
      'emits only insights at or above their policy confidence threshold',
      () {
        final decision = _engine().evaluate(<FeedbackCandidate>[
          _candidate(code: InsightCode.frettingStable),
          _candidate(code: InsightCode.frettingFocus, confidence: 0.9),
          _candidate(
            code: InsightCode.frettingImproved,
            comparisonEvidence: _evidence(id: 'earlier'),
            comparisonPracticeId: 'practice-1',
            comparisonCapabilityLevel: 'tracked',
          ),
        ]);

        for (final insight in decision.insights) {
          expect(
            insight.confidence,
            greaterThanOrEqualTo(
              FeedbackPolicies.catalog[insight.code]!.confidenceThreshold,
            ),
          );
        }
      },
    );

    test(
      'accepts directly constructed experimental evidence without fusion',
      () {
        final decision = _engine().evaluate(<FeedbackCandidate>[
          _candidate(
            code: InsightCode.experimentalObservation,
            state: ObservationState.experimental,
          ),
        ]);

        expect(
          decision.insights.single.code,
          InsightCode.experimentalObservation,
        );
      },
    );

    test(
      'keeps setup priority during its cooldown with an advancing clock',
      () {
        final candidates = <FeedbackCandidate>[
          _candidate(code: InsightCode.frettingFocus, confidence: 0.9, id: 'b'),
          _candidate(
            code: InsightCode.setupNotObservable,
            state: ObservationState.notObservable,
            id: 'a',
          ),
          _candidate(code: InsightCode.frettingStable, id: 'c'),
        ];

        var now = DateTime.utc(2026, 8, 8, 12);
        final engine = _engine(now: () => now);
        final first = engine.evaluate(candidates);
        now = now.add(const Duration(milliseconds: 500));
        final second = engine.evaluate(candidates);

        expect(second.insights, first.insights);
        expect(second.realtimeCue!.code, InsightCode.setupNotObservable);
        expect(first.realtimeCue!.code, InsightCode.setupNotObservable);
      },
    );
  });
}

FeedbackPolicyEngine _engine({DateTime Function()? now}) =>
    FeedbackPolicyEngine(
      cueBudget: CueBudget(now: now ?? () => DateTime.utc(2026, 8, 8, 12)),
    );

FeedbackCandidate _candidate({
  required InsightCode code,
  double confidence = 0.9,
  ObservationState state = ObservationState.observed,
  String id = 'evidence',
  VisionEvidence? comparisonEvidence,
  String? comparisonPracticeId,
  String? comparisonCapabilityLevel,
  int startUs = 1000000,
  int endUs = 1500000,
}) => FeedbackCandidate(
  code: code,
  evidence: _evidence(
    id: id,
    confidence: confidence,
    state: state,
    startUs: startUs,
    endUs: endUs,
  ),
  practiceId: 'practice-1',
  capabilityLevel: 'tracked',
  comparisonEvidence: comparisonEvidence,
  comparisonPracticeId: comparisonPracticeId,
  comparisonCapabilityLevel: comparisonCapabilityLevel,
);

VisionEvidence _evidence({
  required String id,
  double confidence = 0.9,
  ObservationState state = ObservationState.observed,
  int startUs = 0,
  int endUs = 500000,
}) {
  final metric = EvidenceMetric.fretting(FrettingMetricId.wristDeviationProxy);
  return VisionEvidence(
    id: id,
    metric: metric,
    value: state == ObservationState.notObservable ? null : 0.5,
    confidence: confidence,
    observationState: state,
    provenance: EvidenceProvenance(
      metricId: metric.id,
      window: EvidenceWindow(startUs: startUs, endUs: endUs),
      modelVersion: 'test-model',
      geometrySource: GeometrySource.tracked,
      syncQuality: SyncQuality.excellent,
      thresholdsVersion: 'fusion-test-v1',
      qualityThresholdsVersion: 'quality-test-v1',
    ),
  );
}
