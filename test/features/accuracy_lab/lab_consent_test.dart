import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/accuracy_lab/public.dart';

void main() {
  group('LabConsent — typed export gate (ADR 0358 D1)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('lab_consent_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // The three tests below dispatch a `LabConsent` through the same
    // exhaustive switch. `LabPackageWriter.write` only accepts a
    // `LabConsentGranted` argument, so the writer call is only reachable
    // from the branch where the switch has already narrowed `consent` to
    // that type — writing `LabPackageWriter().write(consent: consent, ...)`
    // with the unnarrowed `LabConsent consent` anywhere in this file would
    // not compile ("argument type 'LabConsent' can't be assigned to the
    // parameter type 'LabConsentGranted'"). The matrix below measures the
    // actual call chain (docs/LESSONS.md L161), not an isolated predicate.
    LabPackageWriteResult? dispatch(LabConsent consent) => switch (consent) {
      LabConsentGranted granted => const LabPackageWriter().write(
        root: tempDir,
        consent: granted,
        package: _samplePackage(consentVersion: granted.consentVersion),
        pcmSamples: _samplePcm(),
      ),
      LabConsentRevoked() => null,
      LabConsentUnknown() => null,
    };

    test('granted consent reaches the writer and produces a package', () {
      final result = dispatch(const LabConsentGranted(consentVersion: 'v1'));

      expect(result, isNotNull);
      expect(result!.location.manifestFile.existsSync(), isTrue);
      expect(result.location.wavFile.existsSync(), isTrue);
      expect(result.location.annotationFile.existsSync(), isTrue);
    });

    test('revoked consent cannot reach the writer call', () {
      final result = dispatch(const LabConsentRevoked());
      expect(result, isNull);
    });

    test('unknown consent cannot reach the writer call', () {
      final result = dispatch(const LabConsentUnknown());
      expect(result, isNull);
    });
  });
}

LabCapturePackage _samplePackage({required String consentVersion}) =>
    LabCapturePackage(
      packageId: 'pkg-consent-001',
      capturedAt: DateTime.utc(2026, 9, 4, 12),
      consentVersion: consentVersion,
      device: const LabDeviceMetadata(
        modelName: 'Pixel 9',
        osVersion: 'Android 15',
        sampleRate: 44100,
        channelCount: 1,
        appVersion: '1.0.0',
      ),
      events: const [
        LabCaptureEvent(
          taskId: 'silence_room',
          family: LabTaskFamily.silence,
          startSeconds: 0,
          endSeconds: 10,
        ),
      ],
    );

List<double> _samplePcm() =>
    List<double>.generate(200, (index) => (index.isEven ? 0.1 : -0.1));
