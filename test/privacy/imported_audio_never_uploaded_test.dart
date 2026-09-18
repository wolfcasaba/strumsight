// K3/A3 — audio the user IMPORTED never reaches the diagnostics uploader.
//
// MEASURED gap this pins: `AnalyzeController._analyze` uploaded the raw PCM
// plus the ML/DSP event stream whenever Lab mode and the upload consent were
// both on. That was written for the MICROPHONE path, where the clip is the
// user's own playing. Round K3 sends whole imported songs down the same DSP —
// music the user very often does not own — so the import path is pinned OFF
// at the seam, not behind a flag a future caller could forget.
//
// Three cells:
//   1. behavioural — everything that could enable an upload is ON, and the
//      imported analysis still reaches the uploader zero times and publishes
//      a result with no diagnostics attached;
//   2. control — the same spy DOES record when the uploader is invoked, so
//      cell 1 is not green merely because the instrumentation is dead;
//   3. source guard — the import entry pins `allowDiagnostics: false`, and
//      exactly one call site opts in (the microphone take). This is the cell
//      that keeps catching the regression on a device where the ML asset is
//      present and diagnostics would otherwise be attached.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/analyze/providers/analyze_providers.dart';
import 'package:strumsight/features/diagnostics/data/diagnostics_uploader.dart';
import 'package:strumsight/features/diagnostics/model/diagnostics_session.dart';
import 'package:strumsight/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:strumsight/features/settings/providers/lab_mode_provider.dart';

import '../support/preference_store.dart';
import '../support/synth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('an imported clip never reaches the uploader, Lab mode on', () async {
    final spy = _SpyUploader();
    final container = _rig(spy);
    addTearDown(container.dispose);

    // Everything that could enable an upload is ON before the analysis runs.
    expect(container.read(labModeProvider), isTrue);
    expect(container.read(diagnosticsConsentProvider), isTrue);
    expect(container.read(appConfigProvider).flags.diagnosticsEnabled, isTrue);

    final controller = container.read(analyzeControllerProvider.notifier);
    final pcm = chordSignal(cMajorFreqs, seconds: 1.5, sampleRate: 16000);
    await controller.analyzeImported(pcm.toList(), 16000);

    final state = container.read(analyzeControllerProvider);
    expect(state.phase, AnalyzePhase.done);
    expect(state.result, isNotNull);
    expect(
      state.result!.diagnostics,
      isNull,
      reason: 'the imported path must not even compute diagnostics',
    );
    // The upload is fire-and-forget, so give it the same grace the app has.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(spy.sessions, isEmpty, reason: 'imported audio must not upload');
  });

  test('the spy records when the uploader IS invoked (control)', () async {
    final spy = _SpyUploader();
    final container = _rig(spy);
    addTearDown(container.dispose);

    const analysis = AnalyzeResult(
      durationSec: 1,
      bpm: 120,
      chords: <TimelineChord>[],
      strums: <TimelineStrum>[],
    );
    const diagnostics = MlChordDiagnostics(
      mlChords: <TimelineChord>[],
      agreement: 0.5,
    );
    final result = analysis.withDiagnostics(diagnostics);
    final notifier = container.read(diagnosticsUploadProvider.notifier);
    await notifier.upload(result, const <double>[0, 0.1, 0], 16000);

    expect(spy.sessions, hasLength(1));
  });

  test('the import entry pins the diagnostics switch off in source', () {
    const path = 'lib/features/analyze/providers/analyze_providers.dart';
    final source = File(path).readAsStringSync();

    expect(
      source,
      contains('await _analyze(pcm, sampleRate, allowDiagnostics: false);'),
      reason: 'analyzeImported must opt out at the call, not in the uploader',
    );
    expect(
      'allowDiagnostics: true'.allMatches(source).length,
      1,
      reason: 'only the microphone take may opt in',
    );
    expect(
      source,
      contains('if (labMode && result.diagnostics != null)'),
      reason: 'the upload must stay behind the Lab-mode + diagnostics gate',
    );
  });
}

ProviderContainer _rig(DiagnosticsUploader uploader) => ProviderContainer(
  overrides: <Override>[
    ...preferenceOverrides(<String, Object>{StorageKeys.labMode: true}),
    diagnosticsConsentProvider.overrideWithValue(true),
    diagnosticsUploaderProvider.overrideWithValue(uploader),
    appConfigProvider.overrideWithValue(
      AppConfig(
        environment: AppEnvironment.development,
        apiBaseUrl: AppConfig.devApiBaseUrl,
        flags: const FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: true,
          labModeAvailable: true,
        ),
        diagnosticsToken: AppConfig.devDiagnosticsToken,
        buildMode: 'test',
        appVersion: 'test',
      ),
    ),
  ],
);

/// Records every session handed to the uploader instead of sending it.
final class _SpyUploader extends DiagnosticsUploader {
  _SpyUploader() : super(client: null, diagToken: 'test-token');

  final List<DiagnosticsSession> sessions = <DiagnosticsSession>[];

  @override
  Future<DiagnosticsUploadStatus> upload(
    DiagnosticsSession session, {
    required bool consentGranted,
    String? appVersion,
    String? device,
  }) async {
    sessions.add(session);
    return DiagnosticsUploadStatus.uploaded;
  }
}
