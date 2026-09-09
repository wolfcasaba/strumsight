// E14-R40 capture wiring (ADR 0542 D7) — an opt-in Lab capture carries the
// field-study tag, and carries NOTHING when any gate is closed.
//
// RED before this change: `DiagnosticsSession` had no `fieldSessionTag`, so
// the tag PKG-D built had no capture-site consumer at all.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/telemetry/public.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/diagnostics/data/diagnostics_uploader.dart';
import 'package:strumsight/features/diagnostics/model/diagnostics_session.dart';
import 'package:strumsight/features/diagnostics/providers/diagnostics_providers.dart';

const _result = AnalyzeResult(
  durationSec: 1,
  bpm: 120,
  chords: [TimelineChord(label: 'C', startSec: 0, endSec: 1)],
  strums: [],
  diagnostics: MlChordDiagnostics(
    mlChords: [TimelineChord(label: 'C', startSec: 0, endSec: 1)],
    agreement: 1,
  ),
);

DiagnosticsSession _session({FieldSessionTag? tag}) => DiagnosticsSession(
  sessionId: 's1',
  appVersion: 'test',
  device: 'linux',
  startedAt: '2026-09-09T00:00:00.000Z',
  events: const [],
  surface: 'live',
  fieldSessionTag: tag,
);

/// Captures the session the notifier builds instead of sending it anywhere.
class _CapturingUploader extends DiagnosticsUploader {
  _CapturingUploader() : super(client: null, diagToken: '');

  DiagnosticsSession? captured;

  @override
  Future<DiagnosticsUploadStatus> upload(
    DiagnosticsSession session, {
    required bool consentGranted,
    String? appVersion,
    String? device,
  }) async {
    captured = session;
    return DiagnosticsUploadStatus.uploaded;
  }
}

AppConfig _config({required bool taggingEnabled}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: true,
    labModeAvailable: true,
    recognitionFieldSessionTaggingEnabled: taggingEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'debug',
  appVersion: 'test',
);

void main() {
  group('DiagnosticsSession carries the tag verbatim or not at all', () {
    test('an untagged session emits no field keys', () {
      final json = _session().toJson();
      for (final key in FieldSessionTag.headerKeys) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
    });

    test('a tagged session emits exactly the tag header keys', () {
      final pseudonym = TelemetryPseudonymId.restore(
        highBits: 1,
        lowBits: 2,
        issuedOnDay: 3,
      )!;
      final json = _session(
        tag: FieldSessionTag(
          cohort: FieldStudyCohort.ch14InternalAlpha,
          task: FieldStudyTask.chordChanges,
          pseudonym: pseudonym,
        ),
      ).toJson();

      expect(json['fieldCohort'], 'ch14InternalAlpha');
      expect(json['fieldTask'], 'chordChanges');
      expect(json['fieldPseudonymId'], pseudonym.value);
      expect(
        json.keys.toSet().intersection(FieldSessionTag.headerKeys),
        FieldSessionTag.headerKeys,
      );
      // The tag adds ONLY its three keys — no participant name, no handset.
      expect(json.keys.length, 7 + FieldSessionTag.headerKeys.length);
    });
  });

  group('the capture site resolves the tag through the settings layer', () {
    test(
      'flag off + not enrolled → the uploaded session is untagged',
      () async {
        final uploader = _CapturingUploader();
        final container = ProviderContainer(
          overrides: [
            appConfigProvider.overrideWithValue(
              _config(taggingEnabled: false),
            ),
            diagnosticsConsentProvider.overrideWithValue(true),
            diagnosticsUploaderProvider.overrideWithValue(uploader),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(diagnosticsUploadProvider.notifier)
            .upload(_result, const [0.1], 44100, surface: 'live');

        expect(uploader.captured, isNotNull);
        expect(uploader.captured!.fieldSessionTag, isNull);
        expect(
          uploader.captured!.toJson().containsKey('fieldPseudonymId'),
          isFalse,
          reason: 'a capture must never invent a study identifier',
        );
      },
    );

    test('every closed gate on its own yields no tag', () {
      final pseudonym = TelemetryPseudonymId.restore(
        highBits: 9,
        lowBits: 8,
        issuedOnDay: 7,
      )!;
      FieldSessionTag? resolve({
        required bool flag,
        required bool enrolled,
        TelemetryPseudonymId? id,
      }) => FieldSessionTag.resolve(
        fieldSessionTaggingEnabled: flag,
        enrolled: enrolled,
        cohort: FieldStudyCohort.ch14InternalAlpha,
        task: FieldStudyTask.freePlay,
        pseudonym: id,
      );

      expect(resolve(flag: false, enrolled: true, id: pseudonym), isNull);
      expect(resolve(flag: true, enrolled: false, id: pseudonym), isNull);
      expect(resolve(flag: true, enrolled: true), isNull);
      expect(
        resolve(flag: true, enrolled: true, id: pseudonym),
        isNotNull,
        reason: 'all three open is the ONLY tagged shape',
      );
    });
  });
}
