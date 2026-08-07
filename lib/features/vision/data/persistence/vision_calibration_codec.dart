/// Deterministic, framework-independent JSON codec for the vision
/// calibration bundle (SDD Ch6 §13.3, E05-R10).
///
/// The codec is the single boundary between the in-memory domain model and
/// any persisted representation. Three design rules are enforced here:
///
/// 1. **Byte-identical determinism.** Two consecutive encodes of the same
///    input produce the same bytes — the canonical key order is fixed in
///    [_encodeBundle], and every sub-object follows the same pattern.
///    Round-trip tests rely on this for hash-based equality.
/// 2. **Normalised-space anchors.** Every persisted coordinate runs through
///    `requireDouble(min: 0, max: 1)` — the release-build assert-only
///    `NormalizedPoint` guard would let a pixel coordinate through (R2);
///    this is the codec's own second line of defence. The privacy-snapshot
///    test additionally pins the top-level key set so a raw-image field
///    cannot sneak in (ADR 0183).
/// 3. **Versioned envelope with forward-compatibility.** The codec owns the
///    calibration-shape version ([currentSchemaVersion]); the document
///    envelope ([documentSchemaVersion]) is owned by
///    `JsonDocumentStore._decodeEnvelope`. A version above the envelope's
///    bound is quarantined before the codec is invoked (R3, "future version"
///    cell); a version below is migrated in [decodeFromMap] via
///    [_migrateToCurrent].
///
/// Legacy schema support: a previous flat shape (one map without nested
/// `camera` / `guitar` keys, no `createdAt` / `qualityScore`) is migrated
/// on decode (R3 — "previous version" cell). The shape was implicit; the
/// new shape is documented and pinned by the privacy-snapshot test.
library;

import 'dart:convert';

import '../../../../core/camera/camera_coordinate_space.dart';
import '../../../../core/foundation/json_validation.dart';
import '../../domain/calibration/camera_calibration_profile.dart';
import '../../domain/calibration/guitar_calibration.dart';
import '../../domain/vision_setup_profile.dart';

/// A bundle of `(CameraCalibrationProfile, GuitarCalibration)`.
typedef VisionCalibrationBundle = ({
  CameraCalibrationProfile profile,
  GuitarCalibration guitar,
});

/// The current schema version of the **calibration shape** (the body inside
/// the document envelope). The envelope's `schemaVersion` is owned by
/// `JsonDocumentStore.documentSchemaVersion` and is separate from this one.
const int calibrationShapeSchemaVersion = 1;

/// The previous calibration shape, kept here so the codec can migrate
/// records written by an earlier E05 baseline. The shape is documented in
/// the legacy-matrix test.
const int calibrationShapeLegacySchemaVersion = 0;

/// The codec's public surface.
final class VisionCalibrationCodec {
  const VisionCalibrationCodec();

  /// Current schema version of the calibration shape — pinned by tests.
  static const int currentSchemaVersion = calibrationShapeSchemaVersion;

  /// Legacy schema version this codec still reads (for migration).
  static const int legacySchemaVersion = calibrationShapeLegacySchemaVersion;

  // ---------------------------------------------------------------------------
  // Encode
  // ---------------------------------------------------------------------------

  /// Encodes [profile] + [guitar] to a deterministic JSON-ready map.
  ///
  /// The returned map is freshly allocated and the key order is fixed
  /// (see [_encodeBundle]).
  Map<String, dynamic> encodeToMap({
    required CameraCalibrationProfile profile,
    required GuitarCalibration guitar,
  }) => _encodeBundle(
    schemaVersion: currentSchemaVersion,
    profile: profile,
    guitar: guitar,
  );

  /// Encodes to a UTF-8 JSON byte sequence.
  List<int> encode({
    required CameraCalibrationProfile profile,
    required GuitarCalibration guitar,
  }) => utf8.encode(jsonEncode(encodeToMap(profile: profile, guitar: guitar)));

  // ---------------------------------------------------------------------------
  // Decode
  // ---------------------------------------------------------------------------

  /// Decode [json] (the envelope body — the value under the `data` /
  /// `items` key) to a [VisionCalibrationBundle].
  ///
  /// Throws a [JsonRecordException] (via `requireX` helpers) on any
  /// validation failure. The repository layer catches this and lets the
  /// `JsonDocumentStore` quarantine the record.
  VisionCalibrationBundle decodeFromMap(Object? json) {
    final map = requireObject(json);
    final shapeVersion = _readShapeVersion(map);
    final normalised = _migrateToCurrent(map, shapeVersion);
    return _decodeBundle(normalised);
  }

  // ---------------------------------------------------------------------------
  // Implementation
  // ---------------------------------------------------------------------------

  static int _readShapeVersion(Map<String, dynamic> json) {
    final raw = json['schemaVersion'];
    if (raw == null) return legacySchemaVersion;
    if (raw is! int) {
      throw JsonRecordException(
        RecordDecodeReason.notANumber,
        field: 'schemaVersion',
      );
    }
    return raw;
  }

  Map<String, dynamic> _migrateToCurrent(
    Map<String, dynamic> json,
    int shapeVersion,
  ) {
    if (shapeVersion == currentSchemaVersion) return json;
    if (shapeVersion == legacySchemaVersion) return _migrateFromLegacy(json);
    throw JsonRecordException(
      RecordDecodeReason.unknownEnum,
      field: 'schemaVersion',
    );
  }

  /// The legacy shape is a flat map at the top level of the envelope body:
  /// top-level `camera` (string), `orientation` (int), `zoom` (double),
  /// `setupProfile` (string), `nut`/`bridge` (point objects) and
  /// `polygon` (list). No `createdAt`, no `qualityScore`.
  Map<String, dynamic> _migrateFromLegacy(Map<String, dynamic> legacy) {
    final camera = _legacyCamera(legacy);
    final guitar = _legacyGuitar(legacy);
    return _encodeBundle(
      schemaVersion: currentSchemaVersion,
      profile: camera,
      guitar: guitar,
    );
  }

  CameraCalibrationProfile _legacyCamera(Map<String, dynamic> legacy) {
    final camera = _readLegacyString(legacy, 'camera');
    final orientation = _readOrientation(legacy);
    final zoom = requireDouble(legacy, 'zoom', min: 0, max: 1);
    final setupName = _readLegacyString(legacy, 'setupProfile');
    final profile = VisionSetupProfile.values.firstWhere(
      (p) => p.storageValue == setupName,
      orElse: () => VisionSetupProfile.practiceBalanced,
    );
    return CameraCalibrationProfile(
      camera: camera == VisionCameraPreference.front.storageValue
          ? VisionCameraPreference.front
          : VisionCameraPreference.back,
      orientation: orientation,
      zoom: zoom,
      setupProfile: profile,
      createdAt: DateTime.utc(1970, 1, 1), // legacy: unknown epoch sentinel
      qualityScore: 0.0,
    );
  }

  GuitarCalibration _legacyGuitar(Map<String, dynamic> legacy) {
    final nut = _legacyPoint(legacy, 'nut');
    final bridge = _legacyPoint(legacy, 'bridge');
    final polygonRaw = legacy['polygon'];
    if (polygonRaw is! List) {
      throw JsonRecordException(RecordDecodeReason.notAList, field: 'polygon');
    }
    final polygon = <NormalizedPoint>[
      for (final entry in polygonRaw)
        if (entry is Map<String, dynamic>)
          NormalizedPoint(
            requireDouble(entry, 'x', min: 0, max: 1),
            requireDouble(entry, 'y', min: 0, max: 1),
          )
        else
          throw JsonRecordException(
            RecordDecodeReason.notAnObject,
            field: 'polygon',
          ),
    ];
    if (polygon.length < 3 || polygon.length > 8) {
      throw JsonRecordException(
        RecordDecodeReason.outOfRange,
        field: 'polygon',
      );
    }
    return GuitarCalibration(
      nutAnchor: nut,
      bridgeAnchor: bridge,
      neckPolygon: polygon,
      createdAt: DateTime.utc(1970, 1, 1),
    );
  }

  NormalizedPoint _legacyPoint(Map<String, dynamic> json, String field) {
    final raw = json[field];
    if (raw is! Map<String, dynamic>) {
      throw JsonRecordException(RecordDecodeReason.notAnObject, field: field);
    }
    return NormalizedPoint(
      requireDouble(raw, 'x', min: 0, max: 1),
      requireDouble(raw, 'y', min: 0, max: 1),
    );
  }

  String _readLegacyString(Map<String, dynamic> json, String field) {
    final raw = json[field];
    if (raw is! String) {
      throw JsonRecordException(RecordDecodeReason.notAString, field: field);
    }
    return raw;
  }

  // ---------------------------------------------------------------------------
  // Bundle encoding (deterministic key order)
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _encodeBundle({
    required int schemaVersion,
    required CameraCalibrationProfile profile,
    required GuitarCalibration guitar,
  }) => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'camera': _encodeProfile(profile),
    'guitar': _encodeGuitar(guitar),
  };

  static Map<String, dynamic> _encodeProfile(CameraCalibrationProfile p) =>
      <String, dynamic>{
        'camera': p.camera.storageValue,
        'orientation': p.orientation.degrees,
        'zoom': p.zoom,
        'setupProfile': p.setupProfile.storageValue,
        'createdAt': p.createdAt.toUtc().toIso8601String(),
        'qualityScore': p.qualityScore,
      };

  static Map<String, dynamic> _encodeGuitar(
    GuitarCalibration g,
  ) => <String, dynamic>{
    'nut': <String, dynamic>{'x': g.nutAnchor.x, 'y': g.nutAnchor.y},
    'bridge': <String, dynamic>{'x': g.bridgeAnchor.x, 'y': g.bridgeAnchor.y},
    'neckPolygon': <Map<String, dynamic>>[
      for (final p in g.neckPolygon) <String, dynamic>{'x': p.x, 'y': p.y},
    ],
    'createdAt': g.createdAt.toUtc().toIso8601String(),
  };

  // ---------------------------------------------------------------------------
  // Bundle decoding (current schema only — legacy is migrated first)
  // ---------------------------------------------------------------------------

  VisionCalibrationBundle _decodeBundle(Map<String, dynamic> json) {
    final cameraRaw = json['camera'];
    final guitarRaw = json['guitar'];
    if (cameraRaw is! Map<String, dynamic>) {
      throw JsonRecordException(
        RecordDecodeReason.notAnObject,
        field: 'camera',
      );
    }
    if (guitarRaw is! Map<String, dynamic>) {
      throw JsonRecordException(
        RecordDecodeReason.notAnObject,
        field: 'guitar',
      );
    }
    return (
      profile: _decodeProfile(cameraRaw),
      guitar: _decodeGuitar(guitarRaw),
    );
  }

  CameraCalibrationProfile _decodeProfile(Map<String, dynamic> json) {
    final cameraName = requireString(json, 'camera');
    final camera = cameraName == VisionCameraPreference.front.storageValue
        ? VisionCameraPreference.front
        : VisionCameraPreference.back;
    final orientation = _readOrientation(json);
    final zoom = requireDouble(json, 'zoom', min: 0, max: 1);
    final setupName = requireString(json, 'setupProfile');
    final setupProfile = VisionSetupProfile.values.firstWhere(
      (p) => p.storageValue == setupName,
      orElse: () => VisionSetupProfile.practiceBalanced,
    );
    return CameraCalibrationProfile(
      camera: camera,
      orientation: orientation,
      zoom: zoom,
      setupProfile: setupProfile,
      createdAt: requireDateTime(json, 'createdAt'),
      qualityScore: requireDouble(json, 'qualityScore', min: 0, max: 1),
    );
  }

  GuitarCalibration _decodeGuitar(Map<String, dynamic> json) {
    final nut = _decodePoint(json, 'nut');
    final bridge = _decodePoint(json, 'bridge');
    final polygonRaw = json['neckPolygon'];
    if (polygonRaw is! List) {
      throw JsonRecordException(
        RecordDecodeReason.notAList,
        field: 'neckPolygon',
      );
    }
    final polygon = <NormalizedPoint>[
      for (final entry in polygonRaw)
        if (entry is Map<String, dynamic>)
          NormalizedPoint(
            requireDouble(entry, 'x', min: 0, max: 1),
            requireDouble(entry, 'y', min: 0, max: 1),
          )
        else
          throw JsonRecordException(
            RecordDecodeReason.notAnObject,
            field: 'neckPolygon',
          ),
    ];
    if (polygon.length < 3 || polygon.length > 8) {
      throw JsonRecordException(
        RecordDecodeReason.outOfRange,
        field: 'neckPolygon',
      );
    }
    return GuitarCalibration(
      nutAnchor: nut,
      bridgeAnchor: bridge,
      neckPolygon: polygon,
      createdAt: requireDateTime(json, 'createdAt'),
    );
  }

  NormalizedPoint _decodePoint(Map<String, dynamic> json, String field) {
    final raw = json[field];
    if (raw is! Map<String, dynamic>) {
      throw JsonRecordException(RecordDecodeReason.notAnObject, field: field);
    }
    return NormalizedPoint(
      requireDouble(raw, 'x', min: 0, max: 1),
      requireDouble(raw, 'y', min: 0, max: 1),
    );
  }

  /// Reads one of the four rotations supported by [CameraRotation].
  ///
  /// The explicit membership check is intentionally before
  /// [CameraRotation.fromDegrees]: that factory throws [ArgumentError], which
  /// is an [Error] and would bypass the repository's record-quarantine path.
  CameraRotation _readOrientation(Map<String, dynamic> json) {
    final degrees = requireInt(json, 'orientation', min: 0, max: 359);
    switch (degrees) {
      case 0:
      case 90:
      case 180:
      case 270:
        return CameraRotation.fromDegrees(degrees);
    }
    throw JsonRecordException(
      RecordDecodeReason.unknownEnum,
      field: 'orientation',
    );
  }
}
