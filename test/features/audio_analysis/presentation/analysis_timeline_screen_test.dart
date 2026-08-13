import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_hotspot.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_timeline.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_timeline_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/timeline_viewport.dart';
import 'package:strumsight/features/audio_analysis/presentation/widgets/timeline_lane.dart';
import 'package:strumsight/features/audio_analysis/presentation/widgets/timeline_ruler.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'keeps degraded lane visible and explains unavailable pitch lane',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          _document(<CapabilityReport>[
            _capability(
              AnalysisCapability.chordTimeline,
              CapabilityStatus.degraded,
            ),
            _capability(
              AnalysisCapability.monophonicPitch,
              CapabilityStatus.unavailable,
            ),
          ]),
        ),
      );

      expect(find.byKey(const Key('timeline-lane-chord')), findsOneWidget);
      expect(find.text('Limited confidence'), findsOneWidget);
      expect(
        find.byKey(const Key('timeline-unavailable-pitch')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Chord')), findsWidgets);
    },
  );

  testWidgets('processes only the visible window plus one-window buffer', (
    tester,
  ) async {
    final items = List<TimelineLaneItem>.generate(
      5000,
      (index) => TimelineLaneItem.point(Duration(milliseconds: index * 10)),
    );
    final viewport = TimelineViewport(
      duration: const Duration(seconds: 50),
      logicalWidth: 400,
      start: const Duration(seconds: 20),
      end: const Duration(milliseconds: 20500),
    );
    final visible = TimelineLane.visibleItemsFor(items, viewport);
    expect(visible.length, lessThanOrEqualTo(100));

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineLane(
          kind: TimelineLaneKind.onset,
          title: 'Onsets',
          summary: 'visible onsets',
          viewport: viewport,
          items: items,
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets(
    'shows every published evidence lane while waveform is unavailable',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          _document(<CapabilityReport>[
            _capability(
              AnalysisCapability.chordTimeline,
              CapabilityStatus.available,
            ),
            _capability(
              AnalysisCapability.beatGrid,
              CapabilityStatus.available,
            ),
            _capability(
              AnalysisCapability.onsetTimeline,
              CapabilityStatus.available,
            ),
            _capability(
              AnalysisCapability.timingAccuracy,
              CapabilityStatus.available,
            ),
            _capability(
              AnalysisCapability.dynamicConsistency,
              CapabilityStatus.available,
            ),
            _capability(
              AnalysisCapability.monophonicPitch,
              CapabilityStatus.available,
            ),
            _capability(
              AnalysisCapability.targetAlignment,
              CapabilityStatus.available,
            ),
          ]),
        ),
      );

      expect(
        find.byKey(const Key('timeline-unavailable-waveform')),
        findsOneWidget,
      );
      for (final kind in <TimelineLaneKind>[
        TimelineLaneKind.chord,
        TimelineLaneKind.beatBar,
        TimelineLaneKind.onset,
        TimelineLaneKind.timing,
        TimelineLaneKind.dynamics,
        TimelineLaneKind.pitch,
        TimelineLaneKind.hotspot,
      ]) {
        expect(find.byKey(Key('timeline-lane-${kind.name}')), findsOneWidget);
      }
    },
  );

  test('ruler uses a wider interval for long clips', () {
    final short = TimelineRuler.labelsFor(
      TimelineViewport.full(
        duration: const Duration(seconds: 5),
        logicalWidth: 320,
      ),
    );
    final long = TimelineRuler.labelsFor(
      TimelineViewport.full(
        duration: const Duration(seconds: 300),
        logicalWidth: 320,
      ),
    );
    expect(short.interval, isNot(long.interval));
    expect(short.positions, orderedEquals(short.positions.toSet().toList()));
  });

  test('presentation never reads raw PCM or input data paths', () {
    final sources = Directory('lib/features/audio_analysis/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(sources, isNot(contains('data/input/')));
    expect(sources, isNot(contains('pcmSamples')));
  });
}

Widget _harness(AnalysisDocument document) => MaterialApp(
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: AnalysisTimelineScreen(document: document),
);

AnalysisDocument _document(List<CapabilityReport> capabilities) =>
    AnalysisDocument(
      id: 'timeline',
      schemaVersion: analysisDocumentSchemaVersion,
      createdAt: DateTime.utc(2026),
      mode: AnalysisMode.freePlay,
      input: AnalysisInputSummary(
        source: AnalysisInputSource.microphone,
        duration: const Duration(seconds: 50),
        sampleRate: 48000,
        channelCount: 1,
        fingerprint: 'f',
      ),
      provenance: AnalysisProvenance(
        appVersion: '1',
        analyzerVersion: '1',
        pipelineVersion: '1',
        stageVersions: const {},
        dspConfigHash: 'x',
        modelManifestIds: const [],
        inputFingerprint: 'f',
        platform: 'test',
        featureFlagSnapshot: const {},
      ),
      signalQuality: SignalQualityReport(
        overall: 0,
        peakDbfs: -3,
        rmsDbfs: -18,
        noiseFloorDbfs: -60,
        clippedSampleRatio: 0,
        silentRatio: 0,
        tonalness: 0,
      ),
      capabilities: capabilities,
      timeline: AnalysisTimeline(duration: const Duration(seconds: 50)),
      metrics: const [],
      hotspots: <AnalysisHotspot>[],
      insights: const [],
      warnings: const <AnalysisWarning>[],
      completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
    );

CapabilityReport _capability(
  AnalysisCapability capability,
  CapabilityStatus status,
) => CapabilityReport(
  capability: capability,
  status: status,
  confidence: .5,
  reason: status == CapabilityStatus.unavailable
      ? CapabilityUnavailableReason.insufficientEvents
      : null,
);
