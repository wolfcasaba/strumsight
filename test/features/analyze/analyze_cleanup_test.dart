// SDD Ch13 Kör 26 — A5: no orphan microphone or in-flight recording on any
// exit path (ADR 0285 §5.4). The V2 recording path never writes a temp file
// (§0.0/B6 — memory-only sample buffer), so "no orphan" here is measured as
// "the shared AudioSessionCoordinator lease is released and the recorder no
// longer reports an active run" on every error, cancel, and dispose path.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/audio_analysis/data/capture/analysis_recorder.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_recording_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';

Future<void> _pump(WidgetTester tester, Widget home) => tester.pumpWidget(
  MaterialApp(
    theme: SsLightTheme.data(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

void main() {
  group('AnalysisRecordingScreen — A5 no orphan microphone', () {
    testWidgets('permission denied never acquires the shared lease', (
      tester,
    ) async {
      final coordinator = AudioSessionCoordinator();
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          coordinator: coordinator,
          permissions: FakeMicrophonePermissionGateway(
            state: MicrophonePermissionState.denied,
          ),
        ),
      );

      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: recorder,
          onFinished: (_, _) {},
          onCancel: () {},
        ),
      );
      await tester.tap(find.byKey(const Key('analysis-recording-start')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('analysis-recording-permission-retry')),
        findsOneWidget,
      );
      expect(coordinator.activeOwner, isNull);
      expect(recorder.isRecording, isFalse);
    });

    testWidgets('an engine failure mid-start releases the lease it took', (
      tester,
    ) async {
      final coordinator = AudioSessionCoordinator();
      final capture = FakeAudioCapture(failWith: Exception('engine down'));
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          coordinator: coordinator,
          capture: capture,
        ),
      );

      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: recorder,
          onFinished: (_, _) {},
          onCancel: () {},
        ),
      );
      await tester.tap(find.byKey(const Key('analysis-recording-start')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('analysis-recording-error-title')),
        findsOneWidget,
      );
      // §0.0.A/R12 — the error state is a real design-system component.
      expect(find.byType(SsFailureState), findsOneWidget);
      expect(coordinator.activeOwner, isNull);
      expect(recorder.isRecording, isFalse);
    });

    testWidgets('cancelling mid-recording releases the lease', (tester) async {
      final coordinator = AudioSessionCoordinator();
      final capture = FakeAudioCapture();
      final recorder = AnalysisRecorder(
        mic: fakeMicCapture(
          owner: AudioOwner.analyzeRecorder,
          coordinator: coordinator,
          capture: capture,
        ),
      );
      var cancelled = false;

      await _pump(
        tester,
        AnalysisRecordingScreen(
          recorder: recorder,
          onFinished: (_, _) {},
          onCancel: () => cancelled = true,
        ),
      );
      await tester.tap(find.byKey(const Key('analysis-recording-start')));
      await tester.pumpAndSettle();
      capture.emit(const [0.1, -0.1]);
      await tester.pump();
      expect(coordinator.activeOwner, AudioOwner.analyzeRecorder);

      await tester.tap(find.byKey(const Key('analysis-recording-cancel')));
      await tester.pump();

      expect(cancelled, isTrue);
      expect(coordinator.activeOwner, isNull);
      expect(recorder.isRecording, isFalse);
    });

    testWidgets(
      'leaving the screen mid-recording without a button tap still releases the lease',
      (tester) async {
        final coordinator = AudioSessionCoordinator();
        final capture = FakeAudioCapture();
        final recorder = AnalysisRecorder(
          mic: fakeMicCapture(
            owner: AudioOwner.analyzeRecorder,
            coordinator: coordinator,
            capture: capture,
          ),
        );

        await _pump(
          tester,
          AnalysisRecordingScreen(
            recorder: recorder,
            onFinished: (_, _) {},
            onCancel: () {},
          ),
        );
        await tester.tap(find.byKey(const Key('analysis-recording-start')));
        await tester.pumpAndSettle();
        capture.emit(const [0.1, -0.1]);
        await tester.pump();
        expect(coordinator.activeOwner, AudioOwner.analyzeRecorder);

        // Simulate a back-navigation / host swap that unmounts the Stage
        // without the user ever tapping stop or cancel.
        await _pump(tester, const SizedBox.shrink());
        await tester.pump();

        expect(coordinator.activeOwner, isNull);
        expect(recorder.isRecording, isFalse);
      },
    );

    testWidgets(
      'the maximum-duration auto-stop leaves no lease and no active run',
      (tester) async {
        final coordinator = AudioSessionCoordinator();
        final capture = FakeAudioCapture(sampleRate: 10);
        final recorder = AnalysisRecorder(
          mic: fakeMicCapture(
            owner: AudioOwner.analyzeRecorder,
            coordinator: coordinator,
            capture: capture,
          ),
          maximumDuration: const Duration(seconds: 1),
        );

        await _pump(
          tester,
          AnalysisRecordingScreen(
            recorder: recorder,
            onFinished: (_, _) {},
            onCancel: () {},
            maximumDuration: const Duration(seconds: 1),
          ),
        );
        await tester.tap(find.byKey(const Key('analysis-recording-start')));
        await tester.pumpAndSettle();

        // sampleRate=10, maxDuration=1s -> exactly 10 samples fill the run.
        capture.emit(List<double>.filled(10, 0.05));
        await tester.pumpAndSettle();

        expect(coordinator.activeOwner, isNull);
        expect(recorder.isRecording, isFalse);
        expect(
          find.byKey(const Key('analysis-recording-live-indicator')),
          findsNothing,
        );
      },
    );
  });
}
