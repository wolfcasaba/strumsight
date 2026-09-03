// Golden snapshots of the E13-R26 Analyze home, recording, and processing
// screens, at a compact portrait phone (412×915) and the same frame at
// textScaler 2.0 — the two frames the round brief §7/A9 requires. Pattern
// and sizing follow the merged
// `test/ui/goldens/e13_r25_screens_golden_test.dart` precedent: `SsDarkTheme`
// (the app's actual runtime dark theme, `strumsight_app.dart` — ADR 0466),
// not the legacy `AppTheme`.
//
// Recorded on x86_64 (ADR 0426, §0.0/B/B5) via `tools/golden-x86.sh record`
// — NOT `flutter test --update-goldens` on this (aarch64) box.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/design_system/themes/ss_dark_theme.dart';
import 'package:strumsight/features/audio_analysis/data/capture/analysis_recorder.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_summary.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_state.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_home_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_processing_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_recording_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';

const _compactPortrait = Size(412, 915);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SsDarkTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

List<AnalysisSummary> _recentAnalyses() => <AnalysisSummary>[
  AnalysisSummary(
    documentId: 'golden-1',
    title: 'C · G · Am · F',
    customTitle: false,
    createdAt: DateTime.utc(2026, 8, 20, 9, 30),
    completionStatus: 'complete',
    documentHash: 'a' * 64,
    sizeBytes: 4096,
  ),
  AnalysisSummary(
    documentId: 'golden-2',
    title: 'Free play',
    customTitle: true,
    createdAt: DateTime.utc(2026, 8, 18, 18, 5),
    completionStatus: 'degraded',
    documentHash: 'b' * 64,
    sizeBytes: 2048,
  ),
];

AnalysisRecorder _recorder() => AnalysisRecorder(
  mic: fakeMicCapture(
    owner: AudioOwner.analyzeRecorder,
    coordinator: AudioSessionCoordinator(),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('analysis home — $suffix', (tester) async {
      await _pump(
        tester,
        AnalysisHomeScreen(
          recentAnalyses: _recentAnalyses(),
          onStartRecording: () {},
          onImportFile: () {},
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r26_analysis_home_$suffix');
    });

    testWidgets('analysis recording (ready) — $suffix', (tester) async {
      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: _recorder(),
          onFinished: (_, _) {},
          onCancel: () {},
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r26_analysis_recording_$suffix');
    });

    testWidgets('analysis processing (analyzing) — $suffix', (tester) async {
      await _pump(
        tester,
        AnalysisProcessingScreen(
          state: const AnalysisAnalyzing(
            runId: 'golden-run',
            phase: AnalysisProgressPhase.computingMetrics,
            completedUnits: 3,
            totalUnits: 5,
          ),
          onCancel: () {},
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r26_analysis_processing_$suffix');
    });
  }
}
