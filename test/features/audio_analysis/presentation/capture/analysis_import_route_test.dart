// R26 (audit MI4) — the "Import file" CTA, measured through the REAL router.
//
// Before this round the CTA opened nothing: it showed an honest "not
// available yet" snackbar because no import flow existed anywhere in `lib/`.
// The cells below drive the shipped route tree with a FAKE picker (no
// platform channel, no filesystem) and measure the three things a user can
// experience: the file is analysed, the file cannot be decoded, or the
// chooser was dismissed.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_isolate_runner.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/audio_analysis/data/input/analysis_audio_file_picker.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_summary.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_home_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_processing_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../../support/fake_audio.dart';
import '../../../../support/fake_engines.dart';
import '../../../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

/// 48 kHz mono, 250 ms — exactly the shortest clip the input boundary
/// accepts, so the fixture stays small without being rejected as too short.
const _sampleRate = 48000;
const _frames = 12000;

/// The shipped development shell with Audio Analysis V2 on — the only build
/// in which the capture routes exist at all.
const _testConfig = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    adaptiveShellEnabled: true,
    audioAnalysisV2Enabled: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Future<List<AnalysisSummary>> _noAnalyses(Ref ref) async =>
    const <AnalysisSummary>[];

final class _Rig {
  const _Rig(this.router, this.runner);

  final GoRouter router;
  final _PendingRunner runner;
}

Future<_Rig> _openAnalysisHome(
  WidgetTester tester, {
  PickedAudioFile? picked,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final runner = _PendingRunner();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(wakelock: FakeScreenWakelock()),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      analysisRecentSummariesProvider.overrideWith(_noAnalyses),
      analysisAudioFilePickerProvider.overrideWithValue(_FakePicker(picked)),
      // The run is deliberately never completed: these cells measure the
      // DOOR (picker → pipeline → processing route), and a completed run
      // would drag the persistence path — a separate subject — into it.
      analysisV2RunnerProvider.overrideWithValue(runner),
      appConfigProvider.overrideWithValue(_testConfig),
    ],
  );
  final router = container.read(routerProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await liveEngine.dispose();
    await tunerEngine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.go(AppRoutes.analysisCapture);
  await tester.pumpAndSettle();
  expect(find.byType(AnalysisHomeScreen), findsOneWidget);
  return _Rig(router, runner);
}

/// Taps the import CTA and lets the async picker → decoder → navigation hop
/// finish.
///
/// Deliberately NOT `pumpAndSettle`: a started run renders an indeterminate
/// `LinearProgressIndicator`, whose animation never settles, and a snackbar
/// runs its own entrance animation. Fixed pumps end where a real user's first
/// glance ends.
Future<void> _tapImport(WidgetTester tester) async {
  final target = find.byKey(const Key('analysis-home-import'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('a picked WAV starts the SAME run a recording starts, and the '
      'processing screen opens on top of the home screen', (tester) async {
    final rig = await _openAnalysisHome(
      tester,
      picked: PickedAudioFile(displayName: 'imported-take.wav', bytes: _wav()),
    );

    await _tapImport(tester);

    expect(find.byType(AnalysisProcessingScreen), findsOneWidget);
    final request = rig.runner.request;
    expect(request, isNotNull);
    // The pipeline receives the decoded file as ordinary validated PCM —
    // the only thing that says "import" is the input's own enum plus the
    // display name the document keeps as `input.sourceName`.
    final audio = request!.audio.input;
    expect(audio.source, AnalysisInputSource.importedFile);
    expect(audio.sourceDisplayName?.value, 'imported-take.wav');
    expect(audio.sampleRate, _sampleRate);
    expect(audio.samples, hasLength(_frames));
    expect(request.seed.mode, AnalysisMode.importedRecording);

    // R17 — the way back survives: the processing screen was PUSHED, so the
    // home screen is still underneath. A `go` would have replaced the stack
    // and stranded the user on a screen with no back.
    expect(rig.router.canPop(), isTrue);
    rig.router.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AnalysisProcessingScreen), findsNothing);
    expect(find.byType(AnalysisHomeScreen), findsOneWidget);
  });

  testWidgets('a container this build cannot decode is NAMED, and no run '
      'starts', (tester) async {
    final rig = await _openAnalysisHome(
      tester,
      picked: PickedAudioFile(
        displayName: 'take.mp3',
        bytes: Uint8List.fromList(<int>[0, 1, 2, 3]),
      ),
    );

    await _tapImport(tester);

    expect(find.text(l10n.analysisImportUnsupportedFormat), findsOneWidget);
    expect(find.byType(AnalysisProcessingScreen), findsNothing);
    expect(find.byType(AnalysisHomeScreen), findsOneWidget);
    expect(rig.runner.request, isNull);
  });

  testWidgets('a dismissed picker says nothing — it is not a failure', (
    tester,
  ) async {
    final rig = await _openAnalysisHome(tester);

    await _tapImport(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AnalysisProcessingScreen), findsNothing);
    expect(find.byType(AnalysisHomeScreen), findsOneWidget);
    expect(rig.runner.request, isNull);
  });
}

final class _FakePicker implements AnalysisAudioFilePicker {
  const _FakePicker(this._file);

  final PickedAudioFile? _file;

  @override
  Future<PickedAudioFile?> pickAnalysisAudioFile() async => _file;
}

/// A runner whose run never finishes. It records the request so the cells can
/// prove WHAT reached the pipeline.
final class _PendingRunner implements AnalysisRunner {
  AnalysisRunRequest? request;

  @override
  AnalysisRunHandle start(AnalysisRunRequest input) {
    request = input;
    return _PendingRun();
  }
}

final class _PendingRun implements AnalysisRunHandle {
  final _progress = StreamController<AnalysisProgressEvent>.broadcast();

  @override
  String get runId => 'pending-run';

  @override
  Stream<AnalysisProgressEvent> get progress => _progress.stream;

  @override
  Future<AnalysisRunResult> get result => Completer<AnalysisRunResult>().future;

  @override
  Future<void> cancel() async {
    await _progress.close();
  }
}

/// A real 16-bit mono RIFF/WAVE buffer — the shape a phone recorder writes.
Uint8List _wav() {
  final dataLength = _frames * 2;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, 36 + dataLength, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, _sampleRate, Endian.little);
  data.setUint32(28, _sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, dataLength, Endian.little);
  for (var offset = 44; offset < bytes.length; offset += 2) {
    data.setInt16(offset, 8192, Endian.little);
  }
  return bytes;
}
