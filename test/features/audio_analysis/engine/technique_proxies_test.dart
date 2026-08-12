import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

/// Builds `pairCount` alternating C/G segments so that the C→G transition
/// recurs exactly `pairCount` times (OD-03's `pairKey` grouping) — see
/// transition_analysis_test.dart for the derivation of this shape.
List<ChordSegment> _alternatingSegments(int pairCount) {
  final segments = <ChordSegment>[];
  for (var i = 0; i < pairCount * 2; i += 1) {
    final label = i.isEven ? 'C' : 'G';
    segments.add(
      ChordSegment(
        start: Duration(milliseconds: i * 1000),
        end: Duration(milliseconds: (i + 1) * 1000),
        confidence: 0.9,
        label: label,
      ),
    );
  }
  return segments;
}

int _idCounter = 0;

OnsetEvent _onsetAt(int ms, {double? attackStrength}) {
  _idCounter += 1;
  return OnsetEvent(
    id: 'onset-$_idCounter',
    time: Duration(milliseconds: ms),
    confidence: 0.8,
    attackStrength: attackStrength,
  );
}

ChordFrameEvidence _completeEvidenceAt(int ms, {double topConfidence = 0.9}) =>
    ChordFrameEvidence.complete(
      time: Duration(milliseconds: ms),
      topLabel: 'G',
      topConfidence: topConfidence,
      noChordProbability: 0.05,
      tonalness: 0.7,
      source: DecoderSource.dsp,
    );

ChordFrameEvidence _derivedEvidenceAt(int ms) => ChordFrameEvidence.derived(
  time: Duration(milliseconds: ms),
  topLabel: 'G',
  source: DecoderSource.dsp,
);

SilenceRegionEvent _silenceRegion(int startMs, int endMs) => SilenceRegionEvent(
  id: 'silence-$startMs',
  time: Duration(milliseconds: startMs),
  confidence: 0.7,
  end: Duration(milliseconds: endMs),
);

/// Onsets and complete evidence for every transition in [segments], tuned so
/// every proxy is computable: two close-together onsets per window (one
/// extra beyond the "expected" attack, distinct attack strengths for a
/// finite CV) and one recovering complete-evidence frame at the window start.
({List<OnsetEvent> onsets, List<ChordFrameEvidence> evidence})
_happyPathEvidence(List<ChordSegment> segments) {
  final transitions = buildChordTransitions(segments);
  final onsets = <OnsetEvent>[];
  final evidence = <ChordFrameEvidence>[];
  for (final transition in transitions) {
    final windowStart = transition.time - transitionWindowBefore;
    final t = transition.time.inMilliseconds;
    onsets.add(_onsetAt(t + 5, attackStrength: 0.5));
    onsets.add(_onsetAt(t + 20, attackStrength: 0.55));
    evidence.add(
      _completeEvidenceAt(windowStart.inMilliseconds, topConfidence: 0.9),
    );
  }
  return (onsets: onsets, evidence: evidence);
}

TechniqueProxyReport _buildReport({
  required bool flag,
  required bool lab,
  bool hasKnownTarget = true,
  bool inputClipped = false,
  bool backingTrackDominant = false,
  required List<ChordSegment> chordSegments,
  List<OnsetEvent> onsets = const <OnsetEvent>[],
  List<ChordFrameEvidence> chordFrameEvidence = const <ChordFrameEvidence>[],
  List<SilenceRegionEvent> silenceRegions = const <SilenceRegionEvent>[],
  TechniqueProxyCalculator? calculator,
}) => buildTechniqueProxyReport(
  analysisTechniqueProxiesEnabled: flag,
  labModeActive: lab,
  hasKnownTarget: hasKnownTarget,
  inputClipped: inputClipped,
  backingTrackDominant: backingTrackDominant,
  chordSegments: chordSegments,
  onsets: onsets,
  chordFrameEvidence: chordFrameEvidence,
  silenceRegions: silenceRegions,
  calculator: calculator,
);

void main() {
  group('F2 regression: buildTechniqueProxyReport is the only public entry '
      'point (raw calculator is a private implementation detail, not '
      'exported via public.dart — see technique_proxies.dart)', () {
    final segments = _alternatingSegments(4);
    final evidence = _happyPathEvidence(segments);

    test('flag OFF, Lab OFF: no available technique.* metric leaks out', () {
      final report = _buildReport(
        flag: false,
        lab: false,
        chordSegments: segments,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
      );
      expect(report.status, CapabilityStatus.notApplicable);
      expect(
        report.metrics.where((m) => m.status == CapabilityStatus.available),
        isEmpty,
      );
    });

    test('flag ON, Lab OFF: no available technique.* metric leaks out', () {
      final report = _buildReport(
        flag: true,
        lab: false,
        chordSegments: segments,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
      );
      expect(report.status, CapabilityStatus.notApplicable);
      expect(
        report.metrics.where((m) => m.status == CapabilityStatus.available),
        isEmpty,
      );
    });

    test('flag OFF, Lab ON: no available technique.* metric leaks out', () {
      final report = _buildReport(
        flag: false,
        lab: true,
        chordSegments: segments,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
      );
      expect(report.status, CapabilityStatus.notApplicable);
      expect(
        report.metrics.where((m) => m.status == CapabilityStatus.available),
        isEmpty,
      );
    });
  });

  group('Lab-gate matrix (four cells; only flag ON + Lab ON computes)', () {
    final segments = _alternatingSegments(4);
    final evidence = _happyPathEvidence(segments);

    (TechniqueProxyReport report, int calls) run({
      required bool flag,
      required bool lab,
    }) {
      var calls = 0;
      final report = _buildReport(
        flag: flag,
        lab: lab,
        chordSegments: segments,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
        calculator: () {
          calls += 1;
          return <AnalysisMetricResult>[
            for (final id in TechniqueProxyMetricIds.all)
              AnalysisMetricResult(
                id: id,
                version: 1,
                status: CapabilityStatus.available,
                confidence: 0.9,
                unit: 'ms',
                sampleCount: 1,
                evidence: const <String>[],
                value: ScalarMetricValue(0),
              ),
          ];
        },
      );
      return (report, calls);
    }

    test('flag OFF, Lab OFF: not applicable, calculator never runs', () {
      final (report, calls) = run(flag: false, lab: false);
      expect(report.status, CapabilityStatus.notApplicable);
      expect(report.metrics, isEmpty);
      expect(calls, 0);
    });

    test('flag OFF, Lab ON: not applicable, calculator never runs', () {
      final (report, calls) = run(flag: false, lab: true);
      expect(report.status, CapabilityStatus.notApplicable);
      expect(calls, 0);
    });

    test('flag ON, Lab OFF: not applicable, calculator never runs', () {
      final (report, calls) = run(flag: true, lab: false);
      expect(report.status, CapabilityStatus.notApplicable);
      expect(calls, 0);
    });

    test('flag ON, Lab ON: available, calculator runs exactly once', () {
      final (report, calls) = run(flag: true, lab: true);
      expect(report.status, CapabilityStatus.available);
      expect(report.metrics.length, 5);
      expect(calls, 1);
    });
  });

  group('confidence-gate matrix (four cells, each its own reason)', () {
    final sufficient = _alternatingSegments(4);
    final insufficient = _alternatingSegments(3);
    final evidence = _happyPathEvidence(sufficient);

    test('unknown target -> noReferenceTarget', () {
      final report = _buildReport(
        flag: true,
        lab: true,
        hasKnownTarget: false,
        chordSegments: sufficient,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
      );
      expect(report.status, CapabilityStatus.unavailable);
      expect(report.reason, CapabilityUnavailableReason.noReferenceTarget);
      expect(
        report.metrics,
        everyElement(
          predicate<AnalysisMetricResult>(
            (m) =>
                m.unavailableReason ==
                CapabilityUnavailableReason.noReferenceTarget,
          ),
        ),
      );
    });

    test('clipped input -> inputClipped', () {
      final report = _buildReport(
        flag: true,
        lab: true,
        inputClipped: true,
        chordSegments: sufficient,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
      );
      expect(report.status, CapabilityStatus.unavailable);
      expect(report.reason, CapabilityUnavailableReason.inputClipped);
    });

    test('backing-track-dominant signal -> backingTrackDominant', () {
      final report = _buildReport(
        flag: true,
        lab: true,
        backingTrackDominant: true,
        chordSegments: sufficient,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
      );
      expect(report.status, CapabilityStatus.unavailable);
      expect(report.reason, CapabilityUnavailableReason.backingTrackDominant);
    });

    test('too few repetitions -> insufficientEvents', () {
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: insufficient,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
      );
      expect(report.status, CapabilityStatus.unavailable);
      expect(report.reason, CapabilityUnavailableReason.insufficientEvents);
    });

    test('all four conditions satisfied -> available', () {
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: sufficient,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
      );
      expect(report.status, CapabilityStatus.available);
    });
  });

  group('repetition threshold (inclusive at 4, OD-03)', () {
    // python3 -c "print(3, 4, 5)" — the three cells below the, at, and above
    // the threshold, not an idealised guess (docs/LESSONS.md L13).
    final evidence3 = _happyPathEvidence(_alternatingSegments(3));
    final evidence4 = _happyPathEvidence(_alternatingSegments(4));
    final evidence5 = _happyPathEvidence(_alternatingSegments(5));

    test('3 repetitions: insufficientEvents', () {
      final segments = _alternatingSegments(3);
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: segments,
        onsets: evidence3.onsets,
        chordFrameEvidence: evidence3.evidence,
      );
      expect(report.status, CapabilityStatus.unavailable);
      expect(report.reason, CapabilityUnavailableReason.insufficientEvents);
    });

    test('4 repetitions: available (inclusive)', () {
      final segments = _alternatingSegments(4);
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: segments,
        onsets: evidence4.onsets,
        chordFrameEvidence: evidence4.evidence,
      );
      expect(report.status, CapabilityStatus.available);
    });

    test('5 repetitions: available', () {
      final segments = _alternatingSegments(5);
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: segments,
        onsets: evidence5.onsets,
        chordFrameEvidence: evidence5.evidence,
      );
      expect(report.status, CapabilityStatus.available);
    });
  });

  group('transition-window boundary threshold (inclusive, OD-02)', () {
    test('an onset at exactly +250ms still counts as an extra onset', () {
      final segments = _alternatingSegments(4);
      final evidence = _happyPathEvidence(segments);
      final transition = buildChordTransitions(segments).first;
      final boundaryOnset = _onsetAt(
        (transition.time + transitionWindowAfter).inMilliseconds,
        attackStrength: 0.6,
      );
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: segments,
        onsets: <OnsetEvent>[...evidence.onsets, boundaryOnset],
        chordFrameEvidence: evidence.evidence,
      );
      final extra = report.metrics.singleWhere(
        (m) => m.id == TechniqueProxyMetricIds.unexpectedExtraOnsets,
      );
      final baseline =
          _buildReport(
            flag: true,
            lab: true,
            chordSegments: segments,
            onsets: evidence.onsets,
            chordFrameEvidence: evidence.evidence,
          ).metrics.singleWhere(
            (m) => m.id == TechniqueProxyMetricIds.unexpectedExtraOnsets,
          );
      final extraValue = (extra.value! as ScalarMetricValue).value;
      final baselineValue = (baseline.value! as ScalarMetricValue).value;
      expect(extraValue, greaterThan(baselineValue));
    });

    test('an onset at +251ms (past the boundary) is excluded', () {
      final segments = _alternatingSegments(4);
      final evidence = _happyPathEvidence(segments);
      final transition = buildChordTransitions(segments).first;
      final pastOnset = _onsetAt(
        (transition.time + transitionWindowAfter).inMilliseconds + 1,
        attackStrength: 0.6,
      );
      final withPastOnset =
          _buildReport(
            flag: true,
            lab: true,
            chordSegments: segments,
            onsets: <OnsetEvent>[...evidence.onsets, pastOnset],
            chordFrameEvidence: evidence.evidence,
          ).metrics.singleWhere(
            (m) => m.id == TechniqueProxyMetricIds.unexpectedExtraOnsets,
          );
      final baseline =
          _buildReport(
            flag: true,
            lab: true,
            chordSegments: segments,
            onsets: evidence.onsets,
            chordFrameEvidence: evidence.evidence,
          ).metrics.singleWhere(
            (m) => m.id == TechniqueProxyMetricIds.unexpectedExtraOnsets,
          );
      final withPastValue = (withPastOnset.value! as ScalarMetricValue).value;
      final baselineValue = (baseline.value! as ScalarMetricValue).value;
      expect(withPastValue, baselineValue);
    });
  });

  group('OD-01: derived chord evidence never fabricates a collapse value', () {
    test(
      'derived-only evidence -> confidence collapse is modelUnavailable',
      () {
        final segments = _alternatingSegments(4);
        final onsets = _happyPathEvidence(segments).onsets;
        final derivedEvidence = <ChordFrameEvidence>[
          for (final transition in buildChordTransitions(segments))
            _derivedEvidenceAt(transition.time.inMilliseconds),
        ];
        final report = _buildReport(
          flag: true,
          lab: true,
          chordSegments: segments,
          onsets: onsets,
          chordFrameEvidence: derivedEvidence,
        );
        expect(report.status, CapabilityStatus.available);
        final collapse = report.metrics.singleWhere(
          (m) => m.id == TechniqueProxyMetricIds.confidenceCollapseDuration,
        );
        expect(collapse.status, CapabilityStatus.unavailable);
        expect(
          collapse.unavailableReason,
          CapabilityUnavailableReason.modelUnavailable,
        );
        expect(collapse.value, isNull);

        // The other four proxies still run.
        final others = report.metrics.where(
          (m) => m.id != TechniqueProxyMetricIds.confidenceCollapseDuration,
        );
        expect(
          others,
          everyElement(
            predicate<AnalysisMetricResult>(
              (m) => m.status == CapabilityStatus.available,
            ),
          ),
        );
      },
    );

    test('no evidence at all -> confidence collapse is modelUnavailable', () {
      final segments = _alternatingSegments(4);
      final onsets = _happyPathEvidence(segments).onsets;
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: segments,
        onsets: onsets,
      );
      final collapse = report.metrics.singleWhere(
        (m) => m.id == TechniqueProxyMetricIds.confidenceCollapseDuration,
      );
      expect(
        collapse.unavailableReason,
        CapabilityUnavailableReason.modelUnavailable,
      );
    });
  });

  group('proxy-fixture matrix (six cells; full proxy set status+value)', () {
    test('clean transition: every proxy is available', () {
      final segments = _alternatingSegments(4);
      final evidence = _happyPathEvidence(segments);
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: segments,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
      );
      expect(report.status, CapabilityStatus.available);
      expect(
        report.metrics,
        everyElement(
          predicate<AnalysisMetricResult>(
            (m) => m.status == CapabilityStatus.available,
          ),
        ),
      );
    });

    test('silence gap at the transition: sustained-note dropout is 100%', () {
      final segments = _alternatingSegments(4);
      final evidence = _happyPathEvidence(segments);
      final silenceRegions = <SilenceRegionEvent>[
        for (final transition in buildChordTransitions(segments))
          _silenceRegion(
            (transition.time + transitionWindowAfter).inMilliseconds,
            (transition.time + transitionWindowAfter).inMilliseconds + 400,
          ),
      ];
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: segments,
        onsets: evidence.onsets,
        chordFrameEvidence: evidence.evidence,
        silenceRegions: silenceRegions,
      );
      final dropout = report.metrics.singleWhere(
        (m) => m.id == TechniqueProxyMetricIds.sustainedNoteDropout,
      );
      expect(dropout.status, CapabilityStatus.available);
      expect((dropout.value! as PercentageMetricValue).value, 1.0);
    });

    test(
      'extra attack after the transition: extra-onset count is positive',
      () {
        final segments = _alternatingSegments(4);
        final evidence = _happyPathEvidence(segments);
        final transition = buildChordTransitions(segments).first;
        final extraOnset = _onsetAt(
          transition.time.inMilliseconds + 40,
          attackStrength: 0.9,
        );
        final report = _buildReport(
          flag: true,
          lab: true,
          chordSegments: segments,
          onsets: <OnsetEvent>[...evidence.onsets, extraOnset],
          chordFrameEvidence: evidence.evidence,
        );
        final extra = report.metrics.singleWhere(
          (m) => m.id == TechniqueProxyMetricIds.unexpectedExtraOnsets,
        );
        expect(extra.status, CapabilityStatus.available);
        expect((extra.value! as ScalarMetricValue).value, greaterThan(0));
      },
    );

    test('ring-out overlap between two adjacent windows does not crash and '
        'both transitions still resolve independently', () {
      final segments = <ChordSegment>[
        ChordSegment(
          start: Duration.zero,
          end: const Duration(milliseconds: 300),
          confidence: 0.9,
          label: 'C',
        ),
        ChordSegment(
          start: const Duration(milliseconds: 300),
          end: const Duration(milliseconds: 600),
          confidence: 0.9,
          label: 'G',
        ),
        ChordSegment(
          start: const Duration(milliseconds: 600),
          end: const Duration(milliseconds: 900),
          confidence: 0.9,
          label: 'C',
        ),
        ChordSegment(
          start: const Duration(milliseconds: 900),
          end: const Duration(milliseconds: 1200),
          confidence: 0.9,
          label: 'G',
        ),
        ChordSegment(
          start: const Duration(milliseconds: 1200),
          end: const Duration(milliseconds: 1500),
          confidence: 0.9,
          label: 'C',
        ),
        ChordSegment(
          start: const Duration(milliseconds: 1500),
          end: const Duration(milliseconds: 1800),
          confidence: 0.9,
          label: 'G',
        ),
        ChordSegment(
          start: const Duration(milliseconds: 1800),
          end: const Duration(milliseconds: 2100),
          confidence: 0.9,
          label: 'C',
        ),
        ChordSegment(
          start: const Duration(milliseconds: 2100),
          end: const Duration(milliseconds: 2400),
          confidence: 0.9,
          label: 'G',
        ),
      ];
      // Transitions land at 300ms intervals — well inside each other's
      // `[-150ms, +250ms]` window, so onsets shared across the overlap
      // must not be double-counted incorrectly or throw.
      final onsets = <OnsetEvent>[
        for (var t = 0; t <= 2400; t += 50) _onsetAt(t, attackStrength: 0.5),
      ];
      final evidence = <ChordFrameEvidence>[
        for (final transition in buildChordTransitions(segments))
          _completeEvidenceAt(transition.time.inMilliseconds),
      ];
      expect(
        () => _buildReport(
          flag: true,
          lab: true,
          chordSegments: segments,
          onsets: onsets,
          chordFrameEvidence: evidence,
        ),
        returnsNormally,
      );
      final report = _buildReport(
        flag: true,
        lab: true,
        chordSegments: segments,
        onsets: onsets,
        chordFrameEvidence: evidence,
      );
      expect(report.status, CapabilityStatus.available);
      final gap = report.metrics.singleWhere(
        (m) => m.id == TechniqueProxyMetricIds.chordChangeGap,
      );
      expect(gap.status, CapabilityStatus.available);
    });

    test(
      'poor-quality (clipped) input: every proxy is unavailable/inputClipped',
      () {
        final segments = _alternatingSegments(4);
        final evidence = _happyPathEvidence(segments);
        final report = _buildReport(
          flag: true,
          lab: true,
          inputClipped: true,
          chordSegments: segments,
          onsets: evidence.onsets,
          chordFrameEvidence: evidence.evidence,
        );
        expect(report.status, CapabilityStatus.unavailable);
        expect(
          report.metrics,
          everyElement(
            predicate<AnalysisMetricResult>(
              (m) =>
                  m.status == CapabilityStatus.unavailable &&
                  m.unavailableReason ==
                      CapabilityUnavailableReason.inputClipped,
            ),
          ),
        );
      },
    );

    test(
      'repetition below the minimum: every proxy is unavailable/insufficientEvents',
      () {
        final segments = _alternatingSegments(3);
        final evidence = _happyPathEvidence(segments);
        final report = _buildReport(
          flag: true,
          lab: true,
          chordSegments: segments,
          onsets: evidence.onsets,
          chordFrameEvidence: evidence.evidence,
        );
        expect(report.status, CapabilityStatus.unavailable);
        expect(
          report.metrics,
          everyElement(
            predicate<AnalysisMetricResult>(
              (m) =>
                  m.status == CapabilityStatus.unavailable &&
                  m.unavailableReason ==
                      CapabilityUnavailableReason.insufficientEvents,
            ),
          ),
        );
      },
    );
  });

  group('publication purity', () {
    test(
      'every technique-proxy metric id lives in the technique namespace',
      () {
        final segments = _alternatingSegments(4);
        final evidence = _happyPathEvidence(segments);
        final report = _buildReport(
          flag: true,
          lab: true,
          chordSegments: segments,
          onsets: evidence.onsets,
          chordFrameEvidence: evidence.evidence,
        );
        for (final metric in report.metrics) {
          expect(metric.id, startsWith('technique.'));
          expect(TechniqueProxyMetricIds.all, contains(metric.id));
        }
      },
    );
  });
}
