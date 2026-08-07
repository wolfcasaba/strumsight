/// Verziózott repository a vision calibration bundle számára
/// (SDD Ch6 §13.3, E05-R10, ADR 0181, ADR 0183).
///
/// A repository a `JsonDocumentStore` envelope mintát követi
/// (R3): a **document-szintű** karantén a top-level envelope-on fut
/// (jövőbeli verzió → kontrollált setup-kérés, nem néma félreolvasás).
///
/// A **record-szintű karantén** (R4) a codec-en belül fut: ha a codec
/// `JsonRecordException`-t dob, a `JsonDocumentStore.logger.warning`
/// `storage.document.record_skipped` üzenettel naplóz, a többi rekord
/// olvasható marad. Mivel a bundle egyetlen rekord, a karantén az egész
/// bundle-t érinti — ez a meglévő `JsonObjectStore` minta, NEM új,
/// bájt-megőrző per-record quarantine-kulcs.
///
/// **A migráció idempotens** (R5): a kódolás determinisztikus, a
/// `JsonDocumentStore.write` megegyező inputra azonos bájtot ír ki; a
/// migráció (R3 vN-1 cella) a codec-en belül, dekódoláskor fut —
/// minden olvasás ugyanazt az eredményt adja.
///
/// **Privacy by default** (R5.3 / ADR 0183): a profile és a gitár is csak
/// normalizált pontokat és abstract azonosítókat hordoz — a
/// privacy-snapshot teszt a kulcskészletet PIN-eli, így egy raw-kép mező
/// nem csúszhat be észrevétlenül.
///
/// **Soha nem ad vissza „majdnem jó" profilt** (R5.2): ha a tár sérült
/// vagy üres, a `read` `null`-t ad, és a UI új kalibrációt kér.
library;

import '../../../../core/storage/json_document_store.dart';
import '../../domain/calibration/camera_calibration_profile.dart';
import '../../domain/calibration/guitar_calibration.dart';
import 'vision_calibration_codec.dart';

/// Bundle: a paired `(profile, guitar)` calibration record.
typedef VisionCalibrationRecord = ({
  CameraCalibrationProfile profile,
  GuitarCalibration guitar,
});

/// Persistence façade for the calibration bundle.
final class VisionCalibrationRepository {
  const VisionCalibrationRepository({
    required this.document,
    required this.codec,
  });

  /// Document envelope: owns the read/write/legacy/quarantine machinery
  /// (R3, R4 — both patterns already live in `JsonDocumentStore`).
  final JsonDocumentStore document;

  /// Pure codec: deterministic encode, validated decode, in-place
  /// migration from the legacy shape (R3 vN-1 cell).
  final VisionCalibrationCodec codec;

  /// Read the persisted bundle, or `null` if no calibration exists / it is
  /// corrupt / its version is newer than this build understands.
  VisionCalibrationRecord? read() {
    final body = document.readBody();
    if (body == null) return null;
    try {
      final bundle = codec.decodeFromMap(body);
      return (profile: bundle.profile, guitar: bundle.guitar);
    } on Exception catch (e) {
      document.logger.warning(
        'storage.document.record_skipped',
        error: e,
        fields: {'document': document.name, 'reason': 'invalid'},
      );
      return null;
    }
  }

  /// Persist [profile] + [guitar]. The next read yields the same record.
  Future<void> write({
    required CameraCalibrationProfile profile,
    required GuitarCalibration guitar,
  }) async {
    final encoded = codec.encodeToMap(profile: profile, guitar: guitar);
    await document.write(encoded);
  }
}
