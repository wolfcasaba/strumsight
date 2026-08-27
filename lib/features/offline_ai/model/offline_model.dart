import 'package:crypto/crypto.dart';

/// A candidate on-device model asset — the bytes the device holds (already
/// downloaded, or bundled) plus the checksum the trusted release declared for
/// it. [expectedSha256] is never derived from [bytes] itself: it always comes
/// from a separate, trusted source (the release manifest / server response),
/// exactly like `lib/core/ml/vision_model_manifest.dart`'s validator — the
/// whole point of a checksum is comparing two INDEPENDENT values.
final class OfflineModelAsset {
  const OfflineModelAsset({
    required this.modelId,
    required this.version,
    required this.expectedSha256,
    required this.bytes,
  });

  final String modelId;
  final String version;
  final String expectedSha256;
  final List<int> bytes;
}

/// The real (non-mocked) SHA-256 of [bytes] — 64 lowercase hex characters,
/// same algorithm and format `vision_model_manifest.dart` uses.
String offlineModelChecksum(List<int> bytes) =>
    sha256.convert(bytes).toString();

/// The outcome of checking one [OfflineModelAsset] against its declared
/// checksum. [verified] is the ONLY gate `OfflineModelController.activate`
/// consults (§5.1, ADR 0292) — there is no override field anywhere in this
/// type or its caller.
final class OfflineModelVerification {
  const OfflineModelVerification({
    required this.verified,
    required this.actualSha256,
  });

  final bool verified;
  final String actualSha256;
}

/// Hashes [asset.bytes] for real and compares it against
/// [OfflineModelAsset.expectedSha256] (case-insensitively — the declared
/// value may be upper- or lower-case hex, the computed one is always
/// lower-case). An empty/missing declared checksum can never "accidentally"
/// verify: it is checked as a value like any other, and a real hash is never
/// empty.
OfflineModelVerification verifyOfflineModelAsset(OfflineModelAsset asset) {
  final actual = offlineModelChecksum(asset.bytes);
  final declared = asset.expectedSha256.toLowerCase();
  return OfflineModelVerification(
    verified: declared.isNotEmpty && actual == declared,
    actualSha256: actual,
  );
}

/// Where the current on-screen state of the model manager sits (§6.1 of the
/// round brief — the three mandatory activation cells):
/// - [blockedIntegrity]: below the threshold — missing/mismatched checksum.
///   No activation path exists from here (A6).
/// - [active]: at the threshold — a verified checksum from a known source.
/// - [activeWithRollback]: above the threshold — verified AND a previously
///   active, working version is available to fall back to.
enum OfflineModelPhase {
  notChecked,
  checking,
  blockedIntegrity,
  active,
  activeWithRollback,
}
