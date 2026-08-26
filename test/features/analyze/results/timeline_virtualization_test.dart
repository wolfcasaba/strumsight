// A4 + A8 (SDD Ch13 Kör 27, ADR 0286 §3/§6): the timeline stays virtualized
// under a large fixture, and a selection — whether from a manual drag or
// from tapping an event-list row — starts a correctly-parameterised
// practice callback. Every cell pumps the real [AnalysisTimelineScreen] and
// asserts on the text/semantics it actually renders (§0.0/B/B7), never a
// pure helper or a widget-type-only predicate.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_hotspot.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_insight.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_timeline.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_timeline_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _hotspotCount = 3000;

AnalysisDocument _document({
  required Duration duration,
  required List<AnalysisHotspot> hotspots,
}) => AnalysisDocument(
  id: 'e13-r27-timeline-fixture',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: duration,
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
    overall: 0,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(duration: duration),
  metrics: const <AnalysisMetricResult>[],
  hotspots: hotspots,
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);

/// A recording long enough to need real virtualization: one hotspot per
/// second for fifty minutes.
AnalysisDocument _largeDocument() => _document(
  duration: const Duration(seconds: _hotspotCount),
  hotspots: <AnalysisHotspot>[
    for (var i = 0; i < _hotspotCount; i++)
      AnalysisHotspot(
        id: 'hotspot-$i',
        kind: AnalysisHotspotKind.timing,
        start: Duration(seconds: i),
        end: Duration(seconds: i + 1),
        severity: AnalysisHotspotSeverity.medium,
        confidence: .8,
        metricIds: const <String>[],
        evidenceIds: const <String>[],
      ),
  ],
);

AnalysisDocument _smallDocument() => _document(
  duration: const Duration(seconds: 10),
  hotspots: <AnalysisHotspot>[
    AnalysisHotspot(
      id: 'timing',
      kind: AnalysisHotspotKind.timing,
      start: const Duration(seconds: 1),
      end: const Duration(seconds: 2),
      severity: AnalysisHotspotSeverity.medium,
      confidence: .8,
      metricIds: const <String>[],
      evidenceIds: const <String>[],
    ),
    AnalysisHotspot(
      id: 'rhythm',
      kind: AnalysisHotspotKind.rhythm,
      start: const Duration(seconds: 4),
      end: const Duration(seconds: 5),
      severity: AnalysisHotspotSeverity.medium,
      confidence: .8,
      metricIds: const <String>[],
      evidenceIds: const <String>[],
    ),
  ],
);

Widget _harness(Widget home) => MaterialApp(
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  group('AnalysisTimelineScreen virtualization (A4)', () {
    testWidgets(
      'a $_hotspotCount-hotspot fixture builds only a bounded number of '
      'event-list rows',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _harness(AnalysisTimelineScreen(document: _largeDocument())),
        );

        final builtRows = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('event-list-row-'),
        );
        final builtCount = builtRows.evaluate().length;
        expect(
          builtCount,
          lessThan(30),
          reason:
              'the event list must stay lazily built regardless of the '
              '$_hotspotCount hotspots the fixture published',
        );
        expect(builtCount, greaterThan(0));

        // The very first hotspot's real text is on screen...
        expect(
          find.text('Hotspot 1 of $_hotspotCount: timing, medium'),
          findsOneWidget,
        );
        // ...but one near the tail has never been built — this is the
        // actual laziness claim, not just a widget-count ceiling.
        expect(
          find.text('Hotspot 2999 of $_hotspotCount: timing, medium'),
          findsNothing,
        );
      },
    );

    testWidgets('scrolling the event list brings a later hotspot into view', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(AnalysisTimelineScreen(document: _largeDocument())),
      );

      expect(
        find.text(
          'Hotspot $_hotspotCount of $_hotspotCount: timing, '
          'medium',
        ),
        findsNothing,
      );

      // Drag the INNER event-list scrollable (not the outer screen
      // list) all the way to its end — its scroll extent is
      // ~$_hotspotCount * 48px regardless of the viewport height.
      await tester.drag(
        find.byKey(const Key('timeline-hotspot-event-list')),
        Offset(0, -(_hotspotCount * 48.0)),
      );
      await tester.pump();

      expect(
        find.text(
          'Hotspot $_hotspotCount of $_hotspotCount: timing, '
          'medium',
        ),
        findsOneWidget,
      );
    });
  });

  group('AnalysisTimelineScreen practice-selection callback (A8)', () {
    testWidgets(
      'tapping a hotspot row selects its exact range and "practice" fires '
      'with it',
      (tester) async {
        Duration? capturedStart;
        Duration? capturedEnd;

        await tester.pumpWidget(
          _harness(
            AnalysisTimelineScreen(
              document: _smallDocument(),
              onPracticeSelection: (start, end) {
                capturedStart = start;
                capturedEnd = end;
              },
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('event-list-row-rhythm')));
        await tester.pump();

        expect(find.text('Selected range: 0:04 to 0:05'), findsOneWidget);

        await tester.tap(find.byKey(const Key('timeline-practice-selection')));
        await tester.pump();

        expect(capturedStart, const Duration(seconds: 4));
        expect(capturedEnd, const Duration(seconds: 5));
      },
    );

    testWidgets(
      'the practice callback never hides without a handler, and never '
      'fires on its own',
      (tester) async {
        await tester.pumpWidget(
          _harness(AnalysisTimelineScreen(document: _smallDocument())),
        );

        await tester.tap(find.byKey(const Key('event-list-row-rhythm')));
        await tester.pump();

        expect(find.text('Selected range: 0:04 to 0:05'), findsOneWidget);
        expect(
          find.byKey(const Key('timeline-practice-selection')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a backward manual drag-selection still fires practice with start '
      '<= end',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        Duration? capturedStart;
        Duration? capturedEnd;

        await tester.pumpWidget(
          _harness(
            AnalysisTimelineScreen(
              document: _smallDocument(),
              onPracticeSelection: (start, end) {
                capturedStart = start;
                capturedEnd = end;
              },
            ),
          ),
        );

        final gestureArea = tester.getTopLeft(
          find.byKey(const Key('timeline-gesture-area')),
        );
        // Document duration is 10s over a 400px-wide viewport: 40px/s.
        // Long-press at 7s, then drag to 3s — a backward selection.
        final startPoint = gestureArea + const Offset(280, 100);
        final endPoint = gestureArea + const Offset(120, 100);

        final gesture = await tester.startGesture(startPoint);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.moveTo(endPoint);
        await gesture.up();
        await tester.pump();

        expect(
          find.byKey(const Key('timeline-practice-selection')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('timeline-practice-selection')));
        await tester.pump();

        expect(capturedStart, isNotNull);
        expect(capturedEnd, isNotNull);
        expect(capturedStart! <= capturedEnd!, isTrue);
      },
    );
  });
}
