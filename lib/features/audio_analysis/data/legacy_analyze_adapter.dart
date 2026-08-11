import '../../analyze/public.dart' show MlChordDiagnostics;
import '../../library/public.dart' show AnalyzedSession;
import '../public.dart';

/// V1 session metadata which has no home in the V2 document contract.
final class LegacyAnalysisMigration {
  const LegacyAnalysisMigration({
    required this.document,
    required this.title,
    required this.customTitle,
    this.diagnostics,
  });

  final AnalysisDocument document;
  final String title;
  final bool customTitle;
  final MlChordDiagnostics? diagnostics;
}

/// Maps persisted Analyze/Library V1 records into the additive V2 model.
///
/// The mapping deliberately preserves legacy timeline evidence while marking
/// every V2 measurement not present in V1 as unavailable (ADR 0221).
final class LegacyAnalyzeAdapter {
  const LegacyAnalyzeAdapter();

  static const String _migrationMessageKey = 'analysis.migration.legacy_v1';

  LegacyAnalysisMigration adapt(AnalyzedSession session) {
    final warning = AnalysisWarning(
      kind: AnalysisWarningKind.migration,
      severity: AnalysisWarningSeverity.info,
      messageKey: _migrationMessageKey,
      messageArgs: <String, String>{
        'beatsPerBar': session.result.beatsPerBar.toString(),
      },
    );
    final fingerprint = 'legacy-session:${session.id}';
    return LegacyAnalysisMigration(
      document: AnalysisDocument(
        id: session.id,
        schemaVersion: analysisDocumentSchemaVersion,
        createdAt: session.createdAt,
        mode: AnalysisMode.freePlay,
        input: AnalysisInputSummary(
          source: AnalysisInputSource.importedFile,
          duration: _duration(session.result.durationSec),
          sampleRate: 44100,
          channelCount: 1,
          fingerprint: fingerprint,
        ),
        provenance: AnalysisProvenance(
          appVersion: 'legacy-v1',
          analyzerVersion: 'legacy-v1',
          pipelineVersion: 'legacy-v1',
          stageVersions: const <String, String>{},
          dspConfigHash: 'legacy-unavailable',
          modelManifestIds: const <String>[],
          inputFingerprint: fingerprint,
          platform: 'legacy',
          featureFlagSnapshot: const <String, bool>{},
        ),
        signalQuality: SignalQualityReport(
          // These required fields cannot be reconstructed from V1.  Their
          // values are explicitly non-measurements; [measured] and [warning]
          // prevent presentation from treating them as audio evidence.
          overall: 0,
          peakDbfs: 0,
          rmsDbfs: 0,
          noiseFloorDbfs: 0,
          clippedSampleRatio: 0,
          silentRatio: 0,
          tonalness: 0,
          measured: false,
        ),
        capabilities: _capabilities(),
        timeline: AnalysisTimeline(
          duration: _duration(session.result.durationSec),
          chordSegments: <ChordSegment>[
            for (final chord in session.result.chords)
              ChordSegment(
                start: _duration(chord.startSec),
                end: _duration(chord.endSec),
                confidence: 1,
                label: chord.label,
              ),
          ],
          events: <AnalysisEvent>[
            for (final (index, strum) in session.result.strums.indexed)
              StrumEvent(
                id: 'legacy-strum-$index',
                time: _duration(strum.timeSec),
                confidence: strum.confidence,
                direction: switch (strum.direction.name) {
                  'down' => StrumDirection.down,
                  'up' => StrumDirection.up,
                  _ => throw ArgumentError.value(
                    strum.direction,
                    'strum.direction',
                    'unsupported legacy direction',
                  ),
                },
              ),
          ],
          tempoPoints: <TempoPoint>[
            TempoPoint(time: Duration.zero, bpm: session.result.bpm),
          ],
        ),
        metrics: const <AnalysisMetricResult>[],
        hotspots: const <AnalysisHotspot>[],
        insights: const <AnalysisInsight>[],
        warnings: <AnalysisWarning>[warning],
        completion: AnalysisCompletion(
          status: AnalysisCompletionStatus.complete,
        ),
      ),
      title: session.title,
      customTitle: session.customTitle,
      diagnostics: session.result.diagnostics,
    );
  }

  static Duration _duration(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );

  static List<CapabilityReport> _capabilities() => <CapabilityReport>[
    for (final capability in AnalysisCapability.values)
      switch (capability) {
        AnalysisCapability.chordTimeline ||
        AnalysisCapability.strumDirection ||
        AnalysisCapability.onsetTimeline => CapabilityReport(
          capability: capability,
          status: CapabilityStatus.available,
          confidence: 1,
        ),
        _ => CapabilityReport(
          capability: capability,
          status: CapabilityStatus.unavailable,
          confidence: 0,
          reason: CapabilityUnavailableReason.modelUnavailable,
          details: const <String, Object?>{'legacyMigration': 'true'},
        ),
      },
  ];
}
