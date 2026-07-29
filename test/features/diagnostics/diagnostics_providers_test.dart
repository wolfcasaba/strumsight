import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/diagnostics/data/diagnostics_uploader.dart';
import 'package:strumsight/features/diagnostics/providers/diagnostics_providers.dart';

const _diagnosticResult = AnalyzeResult(
  durationSec: 1,
  bpm: 120,
  chords: [TimelineChord(label: 'C', startSec: 0, endSec: 1)],
  strums: [],
  diagnostics: MlChordDiagnostics(
    mlChords: [TimelineChord(label: 'C', startSec: 0, endSec: 1)],
    agreement: 1,
  ),
);

AppConfig _config({required bool diagnosticsEnabled}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: diagnosticsEnabled,
    labModeAvailable: diagnosticsEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'debug',
  appVersion: 'test',
);

void main() {
  test('diagnostics-disabled build never reads the uploader', () async {
    var uploaderReads = 0;
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(_config(diagnosticsEnabled: false)),
        diagnosticsConsentProvider.overrideWithValue(true),
        diagnosticsUploaderProvider.overrideWith((ref) {
          uploaderReads++;
          throw StateError('disabled diagnostics must not build an uploader');
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(diagnosticsUploadProvider.notifier).upload(
      _diagnosticResult,
      const [0.1],
      44100,
    );

    expect(uploaderReads, 0);
    expect(
      container.read(diagnosticsUploadProvider),
      DiagnosticsUploadStatus.idle,
    );
  });

  test('missing explicit consent never reads the uploader', () async {
    var uploaderReads = 0;
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(_config(diagnosticsEnabled: true)),
        diagnosticsConsentProvider.overrideWithValue(false),
        diagnosticsUploaderProvider.overrideWith((ref) {
          uploaderReads++;
          throw StateError('no-consent path must not build an uploader');
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(diagnosticsUploadProvider.notifier).upload(
      _diagnosticResult,
      const [0.1],
      44100,
    );

    expect(uploaderReads, 0);
    expect(
      container.read(diagnosticsUploadProvider),
      DiagnosticsUploadStatus.idle,
    );
  });
}
