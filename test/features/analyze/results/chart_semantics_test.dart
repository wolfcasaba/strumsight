// A5 (SDD Ch13 Kör 27, ADR 0286 §3/ADR 0282): every timeline lane carries a
// textual trend/extremes summary, and the hotspot list is a navigable event
// list alternative to the canvas. Every cell pumps the REAL
// [AnalysisTimelineScreen] and asserts on the rendered TEXT inside the
// correct lane card (§0.0/B/B7) — never a pure helper or a widget-type-only
// predicate.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_hotspot.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_insight.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_segment.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_timeline.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_timeline_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// A 100s document whose chord segments cluster early (3 of 4 before the
/// 50s midpoint), whose onset/strum events cluster late (3 of 4 after it),
/// and whose single beat has no meaningful trend at all.
AnalysisDocument _document() => AnalysisDocument(
  id: 'chart-semantics-fixture',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 100),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'f',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'x',
    modelManifestIds: const <String>[],
    inputFingerprint: 'f',
    platform: 'test',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: 0.7,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0,
  ),
  capabilities: <CapabilityReport>[
    CapabilityReport(
      capability: AnalysisCapability.chordTimeline,
      status: CapabilityStatus.available,
      confidence: .8,
    ),
    CapabilityReport(
      capability: AnalysisCapability.beatGrid,
      status: CapabilityStatus.available,
      confidence: .8,
    ),
    CapabilityReport(
      capability: AnalysisCapability.onsetTimeline,
      status: CapabilityStatus.available,
      confidence: .8,
    ),
  ],
  timeline: AnalysisTimeline(
    duration: const Duration(seconds: 100),
    chordSegments: <ChordSegment>[
      ChordSegment(
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 6),
        confidence: .8,
        label: 'C',
      ),
      ChordSegment(
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 11),
        confidence: .8,
        label: 'G',
      ),
      ChordSegment(
        start: const Duration(seconds: 15),
        end: const Duration(seconds: 16),
        confidence: .8,
        label: 'Am',
      ),
      ChordSegment(
        start: const Duration(seconds: 90),
        end: const Duration(seconds: 91),
        confidence: .8,
        label: 'F',
      ),
    ],
    beats: <BeatEvent>[
      BeatEvent(
        id: 'b1',
        time: const Duration(seconds: 10),
        confidence: .8,
        beatIndex: 0,
      ),
    ],
    events: <AnalysisEvent>[
      OnsetEvent(id: 'o1', time: const Duration(seconds: 10), confidence: .8),
      OnsetEvent(id: 'o2', time: const Duration(seconds: 60), confidence: .8),
      OnsetEvent(id: 'o3', time: const Duration(seconds: 70), confidence: .8),
      OnsetEvent(id: 'o4', time: const Duration(seconds: 80), confidence: .8),
    ],
  ),
  metrics: const <AnalysisMetricResult>[],
  hotspots: <AnalysisHotspot>[
    AnalysisHotspot(
      id: 'h1',
      kind: AnalysisHotspotKind.timing,
      start: const Duration(seconds: 20),
      end: const Duration(seconds: 21),
      severity: AnalysisHotspotSeverity.medium,
      confidence: .8,
      metricIds: const <String>[],
      evidenceIds: const <String>[],
    ),
  ],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);

Widget _harness({Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: AnalysisTimelineScreen(document: _document()),
);

Finder _withinLane(String kind, Finder matching) => find.descendant(
  of: find.byKey(Key('timeline-lane-$kind')),
  matching: matching,
);

void main() {
  group('A5 — every lane has a text summary (trend + extremes)', () {
    testWidgets('a lane whose evidence clusters early states that trend, with '
        'extremes', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(
        _withinLane(
          'chord',
          find.text('Concentrated in the first half of this view'),
        ),
        findsOneWidget,
      );
      expect(
        _withinLane('chord', find.text('First at 0:05, last at 1:30')),
        findsOneWidget,
      );
    });

    testWidgets('a lane whose evidence clusters late states that trend, with '
        'extremes', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(
        _withinLane(
          'onset',
          find.text('Concentrated in the second half of this view'),
        ),
        findsOneWidget,
      );
      expect(
        _withinLane('onset', find.text('First at 0:10, last at 1:20')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a lane with fewer than two points states "not enough", never a '
      'fabricated trend or extremes',
      (tester) async {
        await tester.pumpWidget(_harness());
        await tester.pumpAndSettle();

        expect(
          _withinLane(
            'beatBar',
            find.text('Not enough events to show a trend'),
          ),
          findsOneWidget,
        );
        expect(
          _withinLane('beatBar', find.textContaining('First at')),
          findsNothing,
        );
      },
    );

    testWidgets('the trend sentence is translated in Hungarian too', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(locale: const Locale('hu')));
      await tester.pumpAndSettle();

      expect(
        _withinLane('chord', find.text('A nézet első felében torlódik')),
        findsOneWidget,
      );
    });
  });

  group('A5 — the hotspot list is a navigable event-list alternative', () {
    testWidgets(
      'the hotspot event renders as real, findable row text — not just a '
      'canvas mark',
      (tester) async {
        await tester.pumpWidget(_harness());
        await tester.pumpAndSettle();

        expect(find.text('Hotspot 1 of 1: timing, medium'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping the event-list row updates the on-screen selection text',
      (tester) async {
        await tester.pumpWidget(_harness());
        await tester.pumpAndSettle();

        expect(find.textContaining('Selected range'), findsNothing);

        await tester.tap(find.byKey(const Key('event-list-row-h1')));
        await tester.pump();

        expect(find.text('Selected range: 0:20 to 0:21'), findsOneWidget);
      },
    );
  });
}
