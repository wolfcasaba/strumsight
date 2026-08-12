import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import '../../../fixtures/analysis/insights/insight_fixtures.dart';

void main() {
  final rules = <String, AnalysisInsightRule>{
    for (final rule in buildInitialInsightRules()) rule.id: rule,
  };

  EvidenceBackedAnalysisInsight? evaluate(
    String id,
    AnalysisInsightContext context,
  ) => rules[id]!.evaluate(context);

  group('initial insight rules — trigger and non-trigger matrix', () {
    test('rush bias triggers at -20 ms and not above the boundary', () {
      expect(
        evaluate(
          'timing.rush_bias',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(targetBias: -20),
            ),
          ),
        ),
        isNotNull,
      );
      expect(
        evaluate(
          'timing.rush_bias',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(targetBias: -19.9),
            ),
          ),
        ),
        isNull,
      );
      expect(
        evaluate(
          'timing.rush_bias',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(targetBias: -20.1),
            ),
          ),
        ),
        isNotNull,
      );
    });

    test('rush bias does not use unrelated document evidence', () {
      expect(
        evaluate(
          'timing.rush_bias',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: <AnalysisMetricResult>[
                ...buildInsightMetrics().where(
                  (metric) =>
                      metric.id != AnalysisMetricId.timingTargetSignedBias,
                ),
                metric(
                  AnalysisMetricId.timingTargetSignedBias,
                  -20,
                  evidence: const <String>[],
                ),
              ],
            ),
          ),
        ),
        isNull,
      );
    });

    test('drag bias triggers at 20 ms and not below the boundary', () {
      expect(
        evaluate(
          'timing.drag_bias',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(targetBias: 20),
            ),
          ),
        ),
        isNotNull,
      );
      expect(
        evaluate(
          'timing.drag_bias',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(targetBias: 19.9),
            ),
          ),
        ),
        isNull,
      );
      expect(
        evaluate(
          'timing.drag_bias',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(targetBias: 20.1),
            ),
          ),
        ),
        isNotNull,
      );
    });

    test('large timing outliers use the inclusive p90 threshold triple', () {
      for (final entry in <double, bool>{
        59.9: false,
        60.0: true,
        60.1: true,
      }.entries) {
        final result = evaluate(
          'timing.large_outliers',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(
                targetMedian: 20,
                targetP90: entry.key,
              ),
            ),
          ),
        );
        expect(result != null, entry.value, reason: 'p90=${entry.key}');
      }
    });

    test(
      'large timing outliers do not trigger when the median exceeds tolerance',
      () {
        expect(
          evaluate(
            'timing.large_outliers',
            buildInsightContext(
              document: buildInsightDocument(
                metrics: buildInsightMetrics(
                  targetMedian: 20.1,
                  targetP90: 100,
                ),
              ),
            ),
          ),
          isNull,
        );
      },
    );

    test(
      'second-half drift uses inclusive threshold and minimum matched pairs',
      () {
        for (final entry in <double, bool>{
          29.9: false,
          30.0: true,
          30.1: true,
        }.entries) {
          final result = evaluate(
            'timing.second_half_drift',
            buildInsightContext(
              timingEvidence: TimingInsightEvidence(
                firstHalfMeanAbsoluteErrorMs: 20,
                secondHalfMeanAbsoluteErrorMs: entry.key,
                firstHalfMatchedEventIds: const <String>[
                  'event-1',
                  'event-2',
                  'event-3',
                  'event-4',
                ],
                secondHalfMatchedEventIds: const <String>[
                  'event-1',
                  'event-2',
                  'event-3',
                  'event-4',
                ],
              ),
            ),
          );
          expect(
            result != null,
            entry.value,
            reason: 'secondHalf=${entry.key}',
          );
        }
        expect(
          evaluate(
            'timing.second_half_drift',
            buildInsightContext(
              timingEvidence: TimingInsightEvidence(
                firstHalfMeanAbsoluteErrorMs: 20,
                secondHalfMeanAbsoluteErrorMs: 30,
                firstHalfMatchedEventIds: const <String>[
                  'event-1',
                  'event-2',
                  'event-3',
                  'event-4',
                ],
                secondHalfMatchedEventIds: const <String>[
                  'event-1',
                  'event-2',
                  'event-3',
                ],
              ),
            ),
          ),
          isNull,
        );
      },
    );

    test('weak upstroke uses the inclusive 1.2 target multiplier', () {
      final evidence = StrokeBalanceInsightEvidence(
        targetDownUpMedianRatio: 1,
        upstrokeEventIds: const <String>['event-1'],
      );
      expect(
        evaluate(
          'dynamics.weak_upstroke',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(downUpRatio: 1.20),
            ),
            strokeBalance: evidence,
          ),
        ),
        isNotNull,
      );
      expect(
        evaluate(
          'dynamics.weak_upstroke',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(downUpRatio: 1.19),
            ),
            strokeBalance: evidence,
          ),
        ),
        isNull,
      );
      expect(
        evaluate(
          'dynamics.weak_upstroke',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(downUpRatio: 1.21),
            ),
            strokeBalance: evidence,
          ),
        ),
        isNotNull,
      );
    });

    test('chord transition hotspot needs a publishable harmony hotspot', () {
      final hotspot = AnalysisHotspot(
        id: 'hotspot-1',
        kind: AnalysisHotspotKind.harmony,
        start: Duration.zero,
        end: const Duration(milliseconds: 500),
        severity: AnalysisHotspotSeverity.high,
        confidence: 0.9,
        metricIds: const <String>[
          AnalysisMetricId.timingTargetMeanAbsoluteError,
        ],
        evidenceIds: const <String>['event-1'],
      );
      expect(
        evaluate(
          'harmony.chord_transition_hotspot',
          buildInsightContext(
            document: buildInsightDocument(
              hotspots: <AnalysisHotspot>[hotspot],
            ),
          ),
        ),
        isNotNull,
      );
      expect(
        evaluate('harmony.chord_transition_hotspot', buildInsightContext()),
        isNull,
      );
    });

    test('low signal quality uses the inclusive 0.05 clipping boundary', () {
      for (final entry in <double, bool>{0.049: false, 0.05: true}.entries) {
        final result = evaluate(
          'quality.low_signal',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(clippedRatio: entry.key),
            ),
          ),
        );
        expect(result != null, entry.value, reason: 'ratio=${entry.key}');
      }
    });

    test('low signal quality triggers from the real dynamics-gate output', () {
      final events = <StrumEvent>[
        for (var index = 0; index < 20; index++)
          StrumEvent(
            id: 'dynamics-event-$index',
            time: Duration(milliseconds: index * 100),
            confidence: 0.9,
            direction: StrumDirection.down,
            sampleIndex: index * 100,
            attackStrength: 1,
            localRms: 0.1,
          ),
      ];
      final samples = List<double>.filled(1921, 0.1)..[0] = 1;
      final dynamics = buildDynamicsMetrics(
        audio: PreprocessedAudio(
          originalSamples: samples,
          canonicalSamples: samples,
          sampleRate: 1000,
          originalChannelCount: 1,
          normalizationGain: 1,
          preprocessingVersion: 'insight-rule-test',
        ),
        events: events,
        signalQuality: SignalQualityReport(
          overall: 0.9,
          peakDbfs: -3,
          rmsDbfs: -18,
          noiseFloorDbfs: -60,
          clippedSampleRatio: 0,
          silentRatio: 0,
          tonalness: 0.8,
        ),
      );
      final clipped = dynamics.metrics.firstWhere(
        (metric) => metric.id == AnalysisMetricId.dynamicsClippedEventRatio,
      );

      expect(dynamics.gateStatus, CapabilityStatus.degraded);
      expect((clipped.value as PercentageMetricValue).value, 0.05);
      expect(
        evaluate(
          'quality.low_signal',
          buildInsightContext(
            document: buildInsightDocument(
              events: events,
              metrics: dynamics.metrics,
            ),
          ),
        ),
        isNotNull,
      );

      final unavailableEvents = <StrumEvent>[
        for (var index = 0; index < 50; index++)
          StrumEvent(
            id: 'unavailable-dynamics-event-$index',
            time: Duration(milliseconds: index * 30),
            confidence: 0.9,
            direction: StrumDirection.down,
            sampleIndex: index * 30,
            attackStrength: 1,
            localRms: 0.1,
          ),
      ];
      final unavailableSamples = List<double>.filled(1500, 0.1)
        ..[0] = 1
        ..[30] = 1
        ..[60] = 1;
      final unavailableDynamics = buildDynamicsMetrics(
        audio: PreprocessedAudio(
          originalSamples: unavailableSamples,
          canonicalSamples: unavailableSamples,
          sampleRate: 1000,
          originalChannelCount: 1,
          normalizationGain: 1,
          preprocessingVersion: 'insight-rule-test',
        ),
        events: unavailableEvents,
        signalQuality: SignalQualityReport(
          overall: 0.9,
          peakDbfs: -3,
          rmsDbfs: -18,
          noiseFloorDbfs: -60,
          clippedSampleRatio: 0,
          silentRatio: 0,
          tonalness: 0.8,
        ),
      );
      expect(unavailableDynamics.gateStatus, CapabilityStatus.unavailable);
      expect(
        evaluate(
          'quality.low_signal',
          buildInsightContext(
            document: buildInsightDocument(
              events: unavailableEvents,
              metrics: unavailableDynamics.metrics,
            ),
          ),
        ),
        isNull,
      );
    });

    test('compatible improvement needs a supplied meaningful comparison', () {
      const id = AnalysisMetricId.timingTargetMeanAbsoluteError;
      final comparison = PreviousMetricComparison(
        metricId: id,
        previousValue: 40,
        currentValue: 20,
        minimumMeaningfulDelta: 10,
        higherIsBetter: false,
        evidenceIds: const <String>['event-1'],
      );
      expect(
        evaluate(
          'comparison.compatible_improvement',
          buildInsightContext(previousComparison: comparison),
        ),
        isNotNull,
      );
      expect(
        evaluate(
          'comparison.compatible_improvement',
          buildInsightContext(
            previousComparison: PreviousMetricComparison(
              metricId: id,
              previousValue: 40,
              currentValue: 35,
              minimumMeaningfulDelta: 10,
              higherIsBetter: false,
              evidenceIds: const <String>['event-1'],
            ),
          ),
        ),
        isNull,
      );
    });

    test('insufficient data requires unavailable timing facts', () {
      expect(
        evaluate(
          'data.insufficient',
          buildInsightContext(
            document: buildInsightDocument(
              metrics: buildInsightMetrics(
                timingStatus: CapabilityStatus.unavailable,
              ),
            ),
          ),
        ),
        isNotNull,
      );
      expect(evaluate('data.insufficient', buildInsightContext()), isNull);
    });
  });

  test('unavailable timing inputs produce only the insufficient-data rule', () {
    final context = buildInsightContext(
      document: buildInsightDocument(
        metrics: buildInsightMetrics(
          timingStatus: CapabilityStatus.unavailable,
        ),
      ),
    );
    final triggered = buildInitialInsightRules()
        .map((rule) => rule.evaluate(context))
        .whereType<EvidenceBackedAnalysisInsight>()
        .toList();
    expect(triggered, hasLength(1));
    expect(triggered.single.ruleId, 'data.insufficient');
  });

  test('rule code contains no localized prose or localization import', () {
    final source = File(
      'lib/features/audio_analysis/engine/insights/insight_rules.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('AppLocalizations')));
    expect(source.codeUnits.any((code) => code > 127), isFalse);
  });

  test('every rule message key and placeholder is available in both ARBs', () {
    final en = File('lib/l10n/app_en.arb').readAsStringSync();
    final hu = File('lib/l10n/app_hu.arb').readAsStringSync();
    final contexts = <String, AnalysisInsightContext>{
      'timing.rush_bias': buildInsightContext(
        document: buildInsightDocument(
          metrics: buildInsightMetrics(targetBias: -30),
        ),
      ),
      'timing.drag_bias': buildInsightContext(
        document: buildInsightDocument(
          metrics: buildInsightMetrics(targetBias: 30),
        ),
      ),
      'timing.large_outliers': buildInsightContext(
        document: buildInsightDocument(
          metrics: buildInsightMetrics(targetMedian: 20, targetP90: 60),
        ),
      ),
      'timing.second_half_drift': buildInsightContext(
        timingEvidence: TimingInsightEvidence(
          firstHalfMeanAbsoluteErrorMs: 20,
          secondHalfMeanAbsoluteErrorMs: 30,
          firstHalfMatchedEventIds: const <String>[
            'event-1',
            'event-2',
            'event-3',
            'event-4',
          ],
          secondHalfMatchedEventIds: const <String>[
            'event-1',
            'event-2',
            'event-3',
            'event-4',
          ],
        ),
      ),
      'dynamics.weak_upstroke': buildInsightContext(
        document: buildInsightDocument(
          metrics: buildInsightMetrics(downUpRatio: 1.2),
        ),
        strokeBalance: StrokeBalanceInsightEvidence(
          targetDownUpMedianRatio: 1,
          upstrokeEventIds: const <String>['event-1'],
        ),
      ),
      'harmony.chord_transition_hotspot': buildInsightContext(
        document: buildInsightDocument(
          hotspots: <AnalysisHotspot>[
            AnalysisHotspot(
              id: 'hotspot-1',
              kind: AnalysisHotspotKind.harmony,
              start: Duration.zero,
              end: const Duration(milliseconds: 500),
              severity: AnalysisHotspotSeverity.high,
              confidence: 0.9,
              metricIds: const <String>[
                AnalysisMetricId.timingTargetMeanAbsoluteError,
              ],
              evidenceIds: const <String>['event-1'],
            ),
          ],
        ),
      ),
      'quality.low_signal': buildInsightContext(
        document: buildInsightDocument(
          metrics: buildInsightMetrics(clippedRatio: 0.05),
        ),
      ),
      'comparison.compatible_improvement': buildInsightContext(
        previousComparison: PreviousMetricComparison(
          metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
          previousValue: 40,
          currentValue: 20,
          minimumMeaningfulDelta: 10,
          higherIsBetter: false,
          evidenceIds: const <String>['event-1'],
        ),
      ),
      'data.insufficient': buildInsightContext(
        document: buildInsightDocument(
          metrics: buildInsightMetrics(
            timingStatus: CapabilityStatus.unavailable,
          ),
        ),
      ),
    };
    for (final rule in buildInitialInsightRules()) {
      final insight = rule.evaluate(contexts[rule.id]!);
      expect(insight, isNotNull, reason: rule.id);
      final resolvedInsight = insight!;
      expect(en, contains('"${resolvedInsight.messageKey}"'));
      expect(hu, contains('"${resolvedInsight.messageKey}"'));
      for (final key in resolvedInsight.messageArgs.keys) {
        expect(en, contains('"$key"'));
        expect(hu, contains('"$key"'));
      }
    }
  });

  test('recommended action remains exhaustively sealed', () {
    String name(RecommendedAnalysisAction action) => switch (action) {
      PracticeHotspotAction() => 'practice',
      RepeatSlowerAction() => 'slower',
      CalibrateInputAction() => 'calibrate',
      CompareWithPreviousAction() => 'compare',
      OpenChordTransitionExerciseAction() => 'chord',
      AskTutorAction() => 'tutor',
    };
    expect(name(const CalibrateInputAction()), 'calibrate');
  });
}
