// E05-R12 — VisionModelManifest (lib/core/ml/, sibling of the audio
// `models[]` validator).
//
// A manifest az `assets/ml/model_manifest.json` dokumentum `vision_models`
// testvér-kulcsa alatt lakik (brief §0.0 R3 — NEM a meglévő `models`
// tömb sora; az audio-oldali generátor és validátor `lib/tool/ci/`
// érintetlen marad). Minden vision modellhez:
//   - modelId, version, sha256, status, path, input shape, output_schema,
//     license, minimum_device_tier, evaluation_report.
//
// A modul SZÁNDÉKOSAN nem importál a `lib/features/**` alól — az
// architecture guard `coreMustNotImportFeatures` szabálya miatt — így a
// hand-landmark-specifikus output_schema konstans itt, ebben a modulban
// él (a jövőbeli aktiváló kör bővítheti újabb modellekkel).

library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// The canonical output schema for the StrumSight hand-landmark provider.
///
/// ADR 0185 §Döntés 1 the model schema is `strumsight.hand_landmarks.v1`:
/// the provider delivers a 21-point topology addressed by
/// `HandLandmarkId` enum values (not provider indices).
const handLandmarksOutputSchema = 'strumsight.hand_landmarks.v1';

/// Activation status of a vision model asset in the manifest.
enum VisionModelStatus { active, deferred }

/// One validated entry in the `vision_models` sibling key.
final class VisionModelEntry {
  const VisionModelEntry({
    required this.modelId,
    required this.version,
    required this.path,
    required this.sha256,
    required this.status,
    required this.inputShape,
    required this.outputSchema,
    required this.licenseSpdx,
    required this.licenseName,
    required this.minimumDeviceTier,
    required this.evaluationReport,
  });

  final String modelId;
  final String version;
  final String path;
  final String sha256;
  final VisionModelStatus status;

  /// RGB-style `[width, height, channels]`. The validator does not enforce
  /// specific numbers — only positivity.
  final List<int> inputShape;
  final String outputSchema;
  final String licenseSpdx;
  final String licenseName;
  final String minimumDeviceTier;
  final String evaluationReport;
}

/// Result of reading + validating the vision-manifest entry.
final class VisionModelManifestReport {
  VisionModelManifestReport({
    required List<VisionModelEntry> entries,
    required List<String> issues,
  }) : entries = List.unmodifiable(entries),
       issues = List.unmodifiable(issues);

  final List<VisionModelEntry> entries;
  final List<String> issues;

  bool get isClean => issues.isEmpty;

  VisionModelEntry? findById(String modelId) {
    for (final entry in entries) {
      if (entry.modelId == modelId) return entry;
    }
    return null;
  }
}

/// Reads + validates the vision-manifest. The contract is split from
/// `validateVisionManifest` (which operates on an already-decoded document)
/// so tests can inject mutations without writing to disk.
abstract interface class VisionModelManifestReader {
  Future<VisionModelManifestReport> read();
}

/// Disk-backed reader that locates `assets/ml/model_manifest.json` and
/// validates its `vision_models` key.
final class FileVisionModelManifestReader implements VisionModelManifestReader {
  FileVisionModelManifestReader({Directory? projectRoot})
    : _projectRoot = projectRoot ?? Directory.current;

  final Directory _projectRoot;

  @override
  Future<VisionModelManifestReport> read() async {
    final manifestPath = File(
      '${_projectRoot.absolute.path}/assets/ml/model_manifest.json',
    );
    if (!manifestPath.existsSync()) {
      return VisionModelManifestReport(
        entries: const [],
        issues: const ['vision manifest is missing'],
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(manifestPath.readAsStringSync());
    } on FormatException catch (error) {
      return VisionModelManifestReport(
        entries: const [],
        issues: ['invalid vision manifest JSON: $error'],
      );
    }
    if (decoded is! Map<String, Object?>) {
      return VisionModelManifestReport(
        entries: const [],
        issues: const ['vision manifest root must be a JSON object'],
      );
    }
    return validateVisionManifest(
      projectRoot: _projectRoot,
      rawDocument: decoded,
    );
  }
}

/// Pure validator on an already-decoded JSON document. Exposed for tests.
VisionModelManifestReport validateVisionManifest({
  required Directory projectRoot,
  required Map<String, Object?> rawDocument,
}) {
  final issues = <String>[];
  final visionModelsRaw = rawDocument['vision_models'];

  if (visionModelsRaw is! List<Object?> || visionModelsRaw.isEmpty) {
    return VisionModelManifestReport(
      entries: const [],
      issues: ['vision_models must be a non-empty list'],
    );
  }

  final entries = <VisionModelEntry>[];
  for (var index = 0; index < visionModelsRaw.length; index++) {
    final entry = visionModelsRaw[index];
    if (entry is! Map<String, Object?>) {
      issues.add('vision_models[$index] must be a JSON object');
      continue;
    }

    final modelId = _requiredString(entry, 'model_id', index, issues);
    final version = _requiredString(entry, 'version', index, issues);
    final path = _requiredString(entry, 'path', index, issues);
    final sha256 = _requiredString(entry, 'sha256', index, issues);
    final statusRaw = _requiredString(entry, 'status', index, issues);
    final outputSchema = _requiredString(entry, 'output_schema', index, issues);
    final inputShape = _validateInputShape(entry, index, issues);
    final licenseSpdx = _validateLicenseSpdx(entry, index, issues);
    final licenseName = _validateLicenseName(entry, index, issues);
    final minimumDeviceTier = _requiredString(
      entry,
      'minimum_device_tier',
      index,
      issues,
    );
    final evaluationReport = _requiredString(
      entry,
      'evaluation_report',
      index,
      issues,
    );

    if (modelId == null ||
        version == null ||
        path == null ||
        sha256 == null ||
        statusRaw == null ||
        outputSchema == null ||
        licenseSpdx == null ||
        licenseName == null ||
        minimumDeviceTier == null ||
        evaluationReport == null ||
        inputShape == null) {
      continue;
    }

    final status = switch (statusRaw) {
      'active' => VisionModelStatus.active,
      'deferred' => VisionModelStatus.deferred,
      _ => null,
    };
    if (status == null) {
      issues.add('vision_models[$index].status must be "active" or "deferred"');
      continue;
    }

    // The output_schema is the one wire-level promise this provider
    // understands. Mismatch → init failure (brief §5.4).
    if (outputSchema != handLandmarksOutputSchema) {
      issues.add(
        'vision_models[$index].output_schema must be '
        '"$handLandmarksOutputSchema" (got "$outputSchema")',
      );
      continue;
    }

    // SHA-256 must be 64 lowercase hex chars (matches the audio validator's
    // rule so the audit surface is uniform).
    if (!_sha256Pattern.hasMatch(sha256)) {
      issues.add(
        'vision_models[$index].sha256 must be 64 lowercase hex characters',
      );
      continue;
    }

    // The asset must exist on disk and its bytes must match the checksum.
    // For `status = "deferred"` entries we still ship a 1-byte placeholder
    // so the test surface is uniform — the checksum is the place the four
    // mutation cells (brief §6) actually attack.
    final asset = File('${projectRoot.absolute.path}/$path');
    if (!asset.existsSync()) {
      issues.add('vision_models[$index] asset missing: $path');
      continue;
    }
    final actualChecksum = _sha256Hex(asset.readAsBytesSync());
    if (actualChecksum != sha256) {
      issues.add(
        'vision_models[$index] checksum mismatch for $path: '
        'expected $sha256, actual $actualChecksum',
      );
      continue;
    }

    entries.add(
      VisionModelEntry(
        modelId: modelId,
        version: version,
        path: path,
        sha256: sha256,
        status: status,
        inputShape: inputShape,
        outputSchema: outputSchema,
        licenseSpdx: licenseSpdx,
        licenseName: licenseName,
        minimumDeviceTier: minimumDeviceTier,
        evaluationReport: evaluationReport,
      ),
    );
  }

  return VisionModelManifestReport(entries: entries, issues: issues);
}

String? _requiredString(
  Map<String, Object?> entry,
  String field,
  int index,
  List<String> issues,
) {
  final value = entry[field];
  if (value is! String || value.trim().isEmpty) {
    issues.add('vision_models[$index].$field must be a non-empty string');
    return null;
  }
  return value;
}

String? _validateLicenseSpdx(
  Map<String, Object?> entry,
  int index,
  List<String> issues,
) {
  final license = entry['license'];
  if (license is! Map<String, Object?>) {
    issues.add('vision_models[$index].license must be a JSON object');
    return null;
  }
  final spdx = license['spdx'];
  if (spdx is! String || spdx.trim().isEmpty) {
    issues.add('vision_models[$index].license.spdx must be a non-empty string');
    return null;
  }
  return spdx;
}

String? _validateLicenseName(
  Map<String, Object?> entry,
  int index,
  List<String> issues,
) {
  final license = entry['license'];
  if (license is! Map<String, Object?>) return null; // already flagged
  final name = license['name'];
  if (name is! String || name.trim().isEmpty) {
    issues.add('vision_models[$index].license.name must be a non-empty string');
    return null;
  }
  return name;
}

List<int>? _validateInputShape(
  Map<String, Object?> entry,
  int index,
  List<String> issues,
) {
  final value = entry['input_shape'];
  if (value is! List<Object?> ||
      value.isEmpty ||
      value.any((dimension) => dimension is! int || dimension <= 0)) {
    issues.add('vision_models[$index].input_shape must contain positive ints');
    return null;
  }
  return List<int>.unmodifiable(value.cast<int>());
}

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

String _sha256Hex(List<int> input) {
  // Delegates to the canonical `package:crypto` SHA-256 — same algorithm
  // FIPS 180-4 mandates, used by both the audio and vision manifest
  // validators, so a single round-trip on the file bytes is enough.
  return sha256.convert(input).toString();
}
