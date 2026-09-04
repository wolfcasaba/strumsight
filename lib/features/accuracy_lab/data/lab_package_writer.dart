import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/lab_capture_package.dart';
import '../domain/lab_consent.dart';

/// Whether a previously-written package is still on disk.
enum LabPackageStatus { present, missing }

/// Only letters, digits, `_` and `-` — no `.`, no `/`, no `\`, never empty.
/// `packageId` values reach [LabPackageWriter] both freshly-generated and
/// round-tripped through [LabCapturePackage.fromJson] (an untrusted-manifest
/// path), so [LabPackageWriter.locate] rejects anything outside this shape
/// before it is ever interpolated into a filesystem path — an id like
/// `"../OUTSIDE_VICTIM"` or `""` never reaches [Directory].
final RegExp labPackageIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// Thrown by [LabPackageWriter.locate] (and therefore by [LabPackageWriter.
/// write], [LabPackageWriter.status] and [LabPackageWriter.delete], which
/// all resolve their path through it) when `packageId` does not match
/// [labPackageIdPattern] — a path-traversal or path-separator id is a typed
/// failure, never a silent write/delete outside the intended root.
final class LabPackageIdException implements Exception {
  const LabPackageIdException(this.packageId);

  final String packageId;

  @override
  String toString() =>
      'LabPackageIdException: "$packageId" is not a valid Lab package id '
      '(expected to match ${labPackageIdPattern.pattern})';
}

/// The three files one [LabCapturePackage] writes to disk, all under the
/// same `<root>/<packageId>/` directory.
final class LabPackageLocation {
  const LabPackageLocation({
    required this.directory,
    required this.wavFile,
    required this.annotationFile,
    required this.manifestFile,
  });

  final Directory directory;
  final File wavFile;
  final File annotationFile;
  final File manifestFile;
}

/// What [LabPackageWriter.write] produced.
final class LabPackageWriteResult {
  const LabPackageWriteResult({
    required this.location,
    required this.audioSha256,
  });

  final LabPackageLocation location;

  /// SHA-256 of the written WAV bytes, hex-encoded.
  final String audioSha256;
}

/// Writes, locates and deletes on-device Lab capture packages. Never opens
/// a network or plugin channel (ADR 0358 D7): the destination is whatever
/// [Directory] the caller passes in, so callers own where the bytes live
/// and tests can point it at a temp directory.
final class LabPackageWriter {
  const LabPackageWriter();

  LabPackageLocation locate({
    required Directory root,
    required String packageId,
  }) {
    if (!labPackageIdPattern.hasMatch(packageId)) {
      throw LabPackageIdException(packageId);
    }
    final directory = Directory('${root.path}/$packageId');
    return LabPackageLocation(
      directory: directory,
      wavFile: File('${directory.path}/capture.wav'),
      annotationFile: File('${directory.path}/annotation.json'),
      manifestFile: File('${directory.path}/manifest.json'),
    );
  }

  /// Writes the WAV, the annotation and the manifest for [package] under
  /// [root]. The [consent] parameter's type is the export gate (ADR 0358
  /// D1): only a [LabConsentGranted] value can be constructed from an
  /// actual grant, so there is no overload — and no `?? false` — that lets
  /// a revoked or unknown consent reach this call.
  LabPackageWriteResult write({
    required Directory root,
    required LabConsentGranted consent,
    required LabCapturePackage package,
    required List<double> pcmSamples,
  }) {
    final location = locate(root: root, packageId: package.packageId);
    location.directory.createSync(recursive: true);

    final wavBytes = _encodeWav(
      pcmSamples: pcmSamples,
      sampleRate: package.device.sampleRate,
    );
    location.wavFile.writeAsBytesSync(wavBytes, flush: true);
    final audioSha256 = sha256.convert(wavBytes).toString();

    final annotationJson = canonicalJsonEncode(<String, Object?>{
      'schemaVersion': labCapturePackageSchemaVersion,
      'packageId': package.packageId,
      'events': [for (final event in package.events) event.toJson()],
    });
    location.annotationFile.writeAsStringSync(annotationJson, flush: true);

    // The manifest's consentVersion is read from the actual `consent` grant,
    // not from `package.toJson()`'s self-reported field — `consent` is the
    // only value this call can prove was actually granted, so it overrides
    // whatever the caller put in `package.consentVersion` (ADR 0358 D1).
    final manifestJson = canonicalJsonEncode(<String, Object?>{
      ...package.toJson(),
      'consentVersion': consent.consentVersion,
      'audioSha256': audioSha256,
    });
    location.manifestFile.writeAsStringSync(manifestJson, flush: true);

    return LabPackageWriteResult(location: location, audioSha256: audioSha256);
  }

  /// Whether every file of the package identified by [packageId] is still
  /// present under [root]. Backed by `existsSync()` on the actual files, not
  /// an in-memory flag (ADR 0358 D4).
  LabPackageStatus status({
    required Directory root,
    required String packageId,
  }) {
    final location = locate(root: root, packageId: packageId);
    final present =
        location.wavFile.existsSync() &&
        location.annotationFile.existsSync() &&
        location.manifestFile.existsSync();
    return present ? LabPackageStatus.present : LabPackageStatus.missing;
  }

  /// Removes the package directory identified by [packageId] from disk, if
  /// present. After this call the WAV, the annotation and the manifest are
  /// all gone — [status] then reports [LabPackageStatus.missing].
  void delete({required Directory root, required String packageId}) {
    final location = locate(root: root, packageId: packageId);
    if (location.directory.existsSync()) {
      location.directory.deleteSync(recursive: true);
    }
  }

  /// Wraps 16-bit mono PCM in a minimal RIFF/WAVE container. Written here
  /// rather than reused from an existing codec: no feature barrel exports
  /// one (ADR 0358 D8), and this feature does not extend a foreign barrel.
  Uint8List _encodeWav({
    required List<double> pcmSamples,
    required int sampleRate,
  }) {
    final sampleCount = pcmSamples.length;
    const headerLength = 44;
    final dataLength = sampleCount * 2;
    final out = ByteData(headerLength + dataLength);

    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        out.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    out.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little); // PCM
    out.setUint16(22, 1, Endian.little); // mono
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * 2, Endian.little);
    out.setUint16(32, 2, Endian.little);
    out.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    out.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < sampleCount; i++) {
      final clamped = pcmSamples[i].clamp(-1.0, 1.0);
      out.setInt16(
        headerLength + i * 2,
        (clamped * 32767).round(),
        Endian.little,
      );
    }
    return out.buffer.asUint8List();
  }
}
