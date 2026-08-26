// SDD Ch13 Kör 26 — Analyze home + recording Stage (ADR 0285).
//
// Covers A1 (persistent recording indicator), A2 (retention state visible,
// from the measured AudioRetentionPolicy — never a fabricated toggle), A6
// (the capacity limit is known BEFORE recording starts), and A7 (clipping
// and silence are two distinct, separate action states).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/audio/mic_capture.dart';
import 'package:strumsight/features/audio_analysis/data/capture/analysis_recorder.dart';
import 'package:strumsight/features/audio_analysis/data/capture/recording_run.dart';
import 'package:strumsight/features/audio_analysis/data/input/input_limits.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/audio_retention_policy.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_home_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_recording_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';

Future<void> _pump(WidgetTester tester, Widget home) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

AnalysisRecorder _recorder({FakeAudioCapture? capture}) => AnalysisRecorder(
  mic: fakeMicCapture(
    owner: AudioOwner.analyzeRecorder,
    coordinator: AudioSessionCoordinator(),
    capture: capture,
  ),
);

void main() {
  group('AnalysisHomeScreen', () {
    testWidgets('offers both input modes with the measured file-size limit', (
      tester,
    ) async {
      var recordTapped = false;
      var importTapped = false;
      await _pump(
        tester,
        AnalysisHomeScreen(
          recentAnalyses: const <AnalysisSummary>[],
          onStartRecording: () => recordTapped = true,
          onImportFile: () => importTapped = true,
        ),
      );

      expect(find.byKey(const Key('analysis-home-record')), findsOneWidget);
      expect(find.byKey(const Key('analysis-home-import')), findsOneWidget);
      final expectedLimit =
          InputLimits.maxFileBytes ~/ InputLimits.bytesPerMebibyte;
      expect(find.textContaining('$expectedLimit'), findsOneWidget);

      await tester.tap(find.byKey(const Key('analysis-home-record')));
      expect(recordTapped, isTrue);
      await tester.tap(find.byKey(const Key('analysis-home-import')));
      expect(importTapped, isTrue);
    });

    testWidgets('shows an empty state and lists recent analyses', (
      tester,
    ) async {
      await _pump(
        tester,
        AnalysisHomeScreen(
          recentAnalyses: const <AnalysisSummary>[],
          onStartRecording: () {},
          onImportFile: () {},
        ),
      );
      expect(
        find.byKey(const Key('analysis-home-recent-empty')),
        findsOneWidget,
      );

      final summary = AnalysisSummary(
        documentId: 'doc-1',
        title: 'C · G · Am',
        customTitle: false,
        createdAt: DateTime.utc(2026, 8, 20),
        completionStatus: 'complete',
        documentHash: 'a' * 64,
        sizeBytes: 128,
      );
      AnalysisSummary? opened;
      await _pump(
        tester,
        AnalysisHomeScreen(
          recentAnalyses: <AnalysisSummary>[summary],
          onStartRecording: () {},
          onImportFile: () {},
          onOpenAnalysis: (value) => opened = value,
        ),
      );
      expect(find.text('C · G · Am'), findsOneWidget);
      await tester.tap(find.text('C · G · Am'));
      expect(opened, summary);
    });
  });

  group('AnalysisRecordingScreen — A6 capacity limit before recording', () {
    testWidgets('states the maximum recording length before the mic starts', (
      tester,
    ) async {
      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: _recorder(),
          onFinished: (_, __) {},
          onCancel: () {},
        ),
      );

      expect(find.byKey(const Key('analysis-recording-start')), findsOneWidget);
      expect(
        find.byKey(const Key('analysis-recording-capacity-limit')),
        findsOneWidget,
      );
      expect(find.textContaining('10'), findsWidgets);
      // The mic must not be touched merely by showing the ready state.
      expect(
        find.byKey(const Key('analysis-recording-live-indicator')),
        findsNothing,
      );
    });
  });

  group('AnalysisRecordingScreen — A2 retention state', () {
    testWidgets('shows the discard notice for the default retention policy', (
      tester,
    ) async {
      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: _recorder(),
          onFinished: (_, __) {},
          onCancel: () {},
        ),
      );

      expect(
        find.byKey(const Key('analysis-recording-retention-notice')),
        findsOneWidget,
      );
      expect(
        find.text(
          AppLocalizations.of(
            _context(tester),
          ).analysisRecordingRetentionDiscarded,
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the kept notice for a keepOriginal policy', (
      tester,
    ) async {
      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: _recorder(),
          onFinished: (_, __) {},
          onCancel: () {},
          retentionPolicy: const AudioRetentionPolicy(keepOriginal: true),
        ),
      );

      expect(
        find.text(
          AppLocalizations.of(_context(tester)).analysisRecordingRetentionKept,
        ),
        findsOneWidget,
      );
    });
  });

  group('AnalysisRecordingScreen — A1 persistent recording indicator', () {
    testWidgets('stays visible for as long as the microphone is active', (
      tester,
    ) async {
      final capture = FakeAudioCapture();
      RecordingRun? finishedRun;
      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: _recorder(capture: capture),
          onFinished: (run, _) => finishedRun = run,
          onCancel: () {},
        ),
      );

      await tester.tap(find.byKey(const Key('analysis-recording-start')));
      await tester.pump();
      expect(
        find.byKey(const Key('analysis-recording-live-indicator')),
        findsOneWidget,
      );

      capture.emit(const [0.05, -0.05, 0.05]);
      await tester.pump();
      expect(
        find.byKey(const Key('analysis-recording-live-indicator')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('analysis-recording-stop')));
      await tester.pump();
      expect(finishedRun, isNotNull);
      expect(
        find.byKey(const Key('analysis-recording-live-indicator')),
        findsNothing,
      );
    });
  });

  group('AnalysisRecordingScreen — A7 clipping vs silence', () {
    testWidgets('shows a distinct clipping banner, not a silence one', (
      tester,
    ) async {
      final capture = FakeAudioCapture();
      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: _recorder(capture: capture),
          onFinished: (_, __) {},
          onCancel: () {},
        ),
      );
      await tester.tap(find.byKey(const Key('analysis-recording-start')));
      await tester.pump();

      capture.emit(const [0.999]);
      await tester.pump();

      expect(
        find.byKey(const Key('analysis-recording-clipping')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('analysis-recording-silence')), findsNothing);
    });

    testWidgets('shows a distinct silence banner, not a clipping one', (
      tester,
    ) async {
      final capture = FakeAudioCapture();
      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: _recorder(capture: capture),
          onFinished: (_, __) {},
          onCancel: () {},
        ),
      );
      await tester.tap(find.byKey(const Key('analysis-recording-start')));
      await tester.pump();

      capture.emit(const [0.0005, -0.0005]);
      await tester.pump();

      expect(
        find.byKey(const Key('analysis-recording-silence')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('analysis-recording-clipping')),
        findsNothing,
      );
    });
  });
}

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first);
