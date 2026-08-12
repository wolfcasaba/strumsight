import 'package:strumsight/features/audio_analysis/public.dart';

AnalysisDocument buildInsightDocument({
  List<AnalysisMetricResult>? metrics,
  List<AnalysisHotspot>? hotspots,
  List<AnalysisEvent>? events,
}) {
  final timelineEvents =
      events ??
      <AnalysisEvent>[
        OnsetEvent(
          id: 'event-1',
          time: const Duration(milliseconds: 100),
          confidence: 0.9,
        ),
        OnsetEvent(
          id: 'event-2',
          time: const Duration(milliseconds: 200),
          confidence: 0.9,
        ),
        OnsetEvent(
          id: 'event-3',
          time: const Duration(milliseconds: 300),
          confidence: 0.9,
        ),
        OnsetEvent(
          id: 'event-4',
          time: const Duration(milliseconds: 400),
          confidence: 0.9,
        ),
      ];
  return AnalysisDocument(
    id: 'insight-document',
    schemaVersion: analysisDocumentSchemaVersion,
    createdAt: DateTime.utc(2026),
    mode: AnalysisMode.practiceTarget,
    input: AnalysisInputSummary(
      source: AnalysisInputSource.microphone,
      duration: const Duration(seconds: 2),
      sampleRate: 48000,
      channelCount: 1,
      fingerprint: 'fixture',
    ),
    provenance: AnalysisProvenance(
      appVersion: 'test',
      analyzerVersion: 'test',
      pipelineVersion: 'test',
      stageVersions: const <String, String>{},
      dspConfigHash: 'test',
      modelManifestIds: const <String>[],
      inputFingerprint: 'fixture',
      platform: 'test',
      featureFlagSnapshot: const <String, bool>{},
    ),
    signalQuality: SignalQualityReport(
      overall: 0.9,
      peakDbfs: -3,
      rmsDbfs: -18,
      noiseFloorDbfs: -60,
      clippedSampleRatio: 0,
      silentRatio: 0,
      tonalness: 0.8,
    ),
    capabilities: const <CapabilityReport>[],
    timeline: AnalysisTimeline(
      duration: const Duration(seconds: 2),
      events: timelineEvents,
      chordSegments: <ChordSegment>[
        ChordSegment(
          id: 'chord-1',
          start: Duration.zero,
          end: const Duration(seconds: 1),
          confidence: 0.9,
          label: 'C',
        ),
      ],
    ),
    metrics: metrics ?? buildInsightMetrics(),
    hotspots: hotspots ?? const <AnalysisHotspot>[],
    insights: const <AnalysisInsight>[],
    warnings: const <AnalysisWarning>[],
    completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
  );
}

List<AnalysisMetricResult> buildInsightMetrics({
  double targetMean = 20,
  double targetMedian = 20,
  double targetP90 = 40,
  double targetBias = 0,
  double downUpRatio = 1,
  double clippedRatio = 0,
  CapabilityStatus timingStatus = CapabilityStatus.available,
}) => <AnalysisMetricResult>[
  metric(
    AnalysisMetricId.timingTargetMeanAbsoluteError,
    targetMean,
    status: timingStatus,
  ),
  metric(
    AnalysisMetricId.timingTargetMedianAbsoluteError,
    targetMedian,
    status: timingStatus,
  ),
  metric(
    AnalysisMetricId.timingTargetP90AbsoluteError,
    targetP90,
    status: timingStatus,
  ),
  metric(
    AnalysisMetricId.timingTargetSignedBias,
    targetBias,
    status: timingStatus,
  ),
  metric(AnalysisMetricId.dynamicsDownUpMedianRatio, downUpRatio),
  metric(AnalysisMetricId.dynamicsClippedEventRatio, clippedRatio),
];

AnalysisMetricResult metric(
  String id,
  double value, {
  CapabilityStatus status = CapabilityStatus.available,
  List<String> evidence = const <String>['event-1'],
}) => AnalysisMetricResult(
  id: id,
  version: 1,
  status: status,
  confidence: 0.9,
  value: status == CapabilityStatus.available ? ScalarMetricValue(value) : null,
  unit: 'test',
  sampleCount: 8,
  evidence: evidence,
  unavailableReason: status == CapabilityStatus.available
      ? null
      : CapabilityUnavailableReason.insufficientEvents,
);

AnalysisInsightContext buildInsightContext({
  AnalysisDocument? document,
  Duration timingTolerance = const Duration(milliseconds: 20),
  TimingInsightEvidence? timingEvidence,
  StrokeBalanceInsightEvidence? strokeBalance,
  PreviousMetricComparison? previousComparison,
}) => AnalysisInsightContext(
  document: document ?? buildInsightDocument(),
  timingTolerance: timingTolerance,
  timingEvidence: timingEvidence,
  strokeBalance: strokeBalance,
  previousComparison: previousComparison,
);
