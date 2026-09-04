import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/accuracy_lab/public.dart';

void main() {
  group('LabPackageWriter — write/checksum/delete (ADR 0358 D3/D4)', () {
    late Directory tempDir;
    const writer = LabPackageWriter();

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('lab_package_writer_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('write produces a WAV, an annotation and a manifest on disk', () {
      final result = writer.write(
        root: tempDir,
        consent: const LabConsentGranted(consentVersion: 'v1'),
        package: _samplePackage(),
        pcmSamples: _samplePcm(),
      );

      expect(result.location.wavFile.existsSync(), isTrue);
      expect(result.location.annotationFile.existsSync(), isTrue);
      expect(result.location.manifestFile.existsSync(), isTrue);

      final wavBytes = result.location.wavFile.readAsBytesSync();
      expect(ascii.decode(wavBytes.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wavBytes.sublist(8, 12)), 'WAVE');
    });

    test('the manifest checksum matches an independently computed SHA-256', () {
      final result = writer.write(
        root: tempDir,
        consent: const LabConsentGranted(consentVersion: 'v1'),
        package: _samplePackage(),
        pcmSamples: _samplePcm(),
      );

      final wavBytes = result.location.wavFile.readAsBytesSync();
      final independentSha256 = sha256.convert(wavBytes).toString();
      expect(result.audioSha256, independentSha256);

      final manifest =
          jsonDecode(result.location.manifestFile.readAsStringSync())
              as Map<String, Object?>;
      expect(manifest['audioSha256'], independentSha256);
      expect(manifest['packageId'], 'pkg-writer-001');
      expect(manifest['schemaVersion'], labCapturePackageSchemaVersion);
    });

    test('writing the same input twice yields byte-identical manifests', () {
      final first = writer.write(
        root: tempDir,
        consent: const LabConsentGranted(consentVersion: 'v1'),
        package: _samplePackage(),
        pcmSamples: _samplePcm(),
      );
      final secondRoot = Directory.systemTemp.createTempSync(
        'lab_package_writer_test_2_',
      );
      addTearDown(() {
        if (secondRoot.existsSync()) secondRoot.deleteSync(recursive: true);
      });
      final second = writer.write(
        root: secondRoot,
        consent: const LabConsentGranted(consentVersion: 'v1'),
        package: _samplePackage(),
        pcmSamples: _samplePcm(),
      );

      expect(
        first.location.manifestFile.readAsStringSync(),
        second.location.manifestFile.readAsStringSync(),
      );
      expect(first.audioSha256, second.audioSha256);
    });

    test('status is present after write and missing after delete', () {
      writer.write(
        root: tempDir,
        consent: const LabConsentGranted(consentVersion: 'v1'),
        package: _samplePackage(),
        pcmSamples: _samplePcm(),
      );

      expect(
        writer.status(root: tempDir, packageId: 'pkg-writer-001'),
        LabPackageStatus.present,
      );

      writer.delete(root: tempDir, packageId: 'pkg-writer-001');

      final location = writer.locate(
        root: tempDir,
        packageId: 'pkg-writer-001',
      );
      expect(location.wavFile.existsSync(), isFalse);
      expect(location.annotationFile.existsSync(), isFalse);
      expect(location.manifestFile.existsSync(), isFalse);
      expect(location.directory.existsSync(), isFalse);
      expect(
        writer.status(root: tempDir, packageId: 'pkg-writer-001'),
        LabPackageStatus.missing,
      );
    });

    test('status is missing for a package that was never written', () {
      expect(
        writer.status(root: tempDir, packageId: 'never-written'),
        LabPackageStatus.missing,
      );
    });

    test('deleting a package that was never written is a no-op', () {
      expect(
        () => writer.delete(root: tempDir, packageId: 'never-written'),
        returnsNormally,
      );
    });

    test('the manifest consentVersion reflects the actual consent grant, even '
        'when package.consentVersion disagrees', () {
      final result = writer.write(
        root: tempDir,
        consent: const LabConsentGranted(consentVersion: 'consent-v2-2026'),
        package: _samplePackage(consentVersion: 'v1-stale'),
        pcmSamples: _samplePcm(),
      );

      final manifest =
          jsonDecode(result.location.manifestFile.readAsStringSync())
              as Map<String, Object?>;
      expect(manifest['consentVersion'], 'consent-v2-2026');
    });
  });

  group('LabPackageWriter — packageId path-traversal rejection (MAJOR-1)', () {
    late Directory tempDir;
    const writer = LabPackageWriter();

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'lab_package_writer_traversal_test_',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('locate rejects a packageId containing ".."', () {
      expect(
        () => writer.locate(root: tempDir, packageId: '../OUTSIDE_VICTIM'),
        throwsA(isA<LabPackageIdException>()),
      );
    });

    test('locate rejects an empty packageId', () {
      expect(
        () => writer.locate(root: tempDir, packageId: ''),
        throwsA(isA<LabPackageIdException>()),
      );
    });

    test('locate rejects a packageId containing a path separator', () {
      expect(
        () => writer.locate(root: tempDir, packageId: 'a/b'),
        throwsA(isA<LabPackageIdException>()),
      );
    });

    test('write rejects a ".." packageId and leaves the sibling directory '
        'untouched', () {
      final victimDir = Directory.systemTemp.createTempSync(
        'lab_writer_victim_',
      );
      final victimName = victimDir.path.split(Platform.pathSeparator).last;
      final victimFile = File('${victimDir.path}/precious.txt')
        ..writeAsStringSync('precious');
      addTearDown(() {
        if (victimDir.existsSync()) victimDir.deleteSync(recursive: true);
      });

      expect(
        () => writer.write(
          root: tempDir,
          consent: const LabConsentGranted(consentVersion: 'v1'),
          package: _samplePackage(packageId: '../$victimName'),
          pcmSamples: _samplePcm(),
        ),
        throwsA(isA<LabPackageIdException>()),
      );

      expect(victimDir.existsSync(), isTrue);
      expect(victimFile.existsSync(), isTrue);
      expect(victimFile.readAsStringSync(), 'precious');
    });

    test('status rejects a traversal packageId', () {
      expect(
        () => writer.status(root: tempDir, packageId: '../OUTSIDE_VICTIM'),
        throwsA(isA<LabPackageIdException>()),
      );
    });

    test('delete rejects an empty packageId and leaves the root directory '
        'and its existing packages untouched', () {
      writer.write(
        root: tempDir,
        consent: const LabConsentGranted(consentVersion: 'v1'),
        package: _samplePackage(),
        pcmSamples: _samplePcm(),
      );

      expect(
        () => writer.delete(root: tempDir, packageId: ''),
        throwsA(isA<LabPackageIdException>()),
      );

      expect(tempDir.existsSync(), isTrue);
      expect(
        writer.status(root: tempDir, packageId: 'pkg-writer-001'),
        LabPackageStatus.present,
      );
    });

    test('delete rejects a ".." packageId', () {
      expect(
        () => writer.delete(root: tempDir, packageId: '../OUTSIDE_VICTIM'),
        throwsA(isA<LabPackageIdException>()),
      );
    });
  });
}

LabCapturePackage _samplePackage({
  String packageId = 'pkg-writer-001',
  String consentVersion = 'v1',
}) => LabCapturePackage(
  packageId: packageId,
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
    LabCaptureEvent(
      taskId: 'chord_e_major_open',
      family: LabTaskFamily.singleChord,
      startSeconds: 10,
      endSeconds: 16,
    ),
  ],
);

List<double> _samplePcm() =>
    List<double>.generate(200, (index) => (index.isEven ? 0.1 : -0.1));
