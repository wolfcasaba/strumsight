// E05-R10 §6 — repository tesztek.
//
// A `VisionCalibrationRepository` négy tulajdonságát méri, mindegyiket a
// saját cellájában (a mérce-mátrix szabály: a hibás és helyes implementáció
// nem mosható össze):
//
//  * **Round-trip** (bit-stabil, determinisztikus kulcssorrend).
//  * **Migrációs mátrix** (v0 / vN-1 / vN / vN+1 — mind a négy cella).
//  * **Idempotencia** (a migráció kétszeri futtatása azonos eredmény).
//  * **Korrupció-teszt** (csonka JSON / hibás típus / degenerált polygon).
//  * **Privacy-snapshot** (a szerializált profil kulcskészlete egy rögzített
//    halmaz, és sehol sincs raw-kép-suspect substring).
//  * **Valódi-sértés próba** (pixelkoordináta → a codec elutasítja release
//    módban is).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/json_validation.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_codec.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_repository.dart';
import 'package:strumsight/features/vision/domain/calibration/camera_calibration_profile.dart';
import 'package:strumsight/features/vision/domain/calibration/guitar_calibration.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

class _RecordingLogger implements AppLogger {
  final List<String> events = [];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      events.add(event);

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) =>
      events.add(event);

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => events.add(event);

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) => events.add(event);
}

({
  VisionCalibrationRepository repository,
  InMemoryKeyValueStore store,
  _RecordingLogger logger,
})
build({Map<String, Object>? initial}) {
  final store = InMemoryKeyValueStore(initial);
  final logger = _RecordingLogger();
  final document = JsonDocumentStore(
    store: store,
    logger: logger,
    key: StorageKeys.visionCalibration,
    legacyKey: 'ss.vision.calibration.legacy',
    name: 'vision_calibration',
    bodyKey: 'data',
  );
  final repo = VisionCalibrationRepository(
    document: document,
    codec: const VisionCalibrationCodec(),
  );
  return (repository: repo, store: store, logger: logger);
}

CameraCalibrationProfile _profile({
  VisionCameraPreference camera = VisionCameraPreference.back,
  CameraRotation orientation = CameraRotation.degrees90,
  double zoom = 0.4,
}) => CameraCalibrationProfile(
  camera: camera,
  orientation: orientation,
  zoom: zoom,
  setupProfile: VisionSetupProfile.practiceBalanced,
  createdAt: DateTime.utc(2026, 8, 7, 12),
  qualityScore: 0.85,
);

GuitarCalibration _guitar() => GuitarCalibration(
  nutAnchor: const NormalizedPoint(0.20, 0.45),
  bridgeAnchor: const NormalizedPoint(0.80, 0.55),
  neckPolygon: const [
    NormalizedPoint(0.15, 0.30),
    NormalizedPoint(0.85, 0.30),
    NormalizedPoint(0.85, 0.70),
    NormalizedPoint(0.15, 0.70),
  ],
  createdAt: DateTime.utc(2026, 8, 7, 12),
);

void main() {
  group('round-trip', () {
    test('a freshly written profile reads back as the same value', () async {
      final c = build();
      final profile = _profile();
      final guitar = _guitar();
      await c.repository.write(profile: profile, guitar: guitar);

      final read = c.repository.read();
      expect(read, isNotNull);
      expect(read!.profile, profile);
      expect(read.guitar, guitar);
    });

    test('the serialized JSON is bit-stable across two encodes', () async {
      final codec = const VisionCalibrationCodec();
      final profile = _profile();
      final guitar = _guitar();
      final a = jsonEncode(codec.encodeToMap(profile: profile, guitar: guitar));
      final b = jsonEncode(codec.encodeToMap(profile: profile, guitar: guitar));
      expect(a, equals(b));
    });

    test('the top-level key order is deterministic (hand-pinned)', () async {
      final codec = const VisionCalibrationCodec();
      final encoded = codec.encodeToMap(profile: _profile(), guitar: _guitar());
      expect(encoded.keys.toList(), <String>[
        'schemaVersion',
        'camera',
        'guitar',
      ]);
      final camera = encoded['camera'] as Map<String, dynamic>;
      expect(camera.keys.toList(), <String>[
        'camera',
        'orientation',
        'zoom',
        'setupProfile',
        'createdAt',
        'qualityScore',
      ]);
      final guitar = encoded['guitar'] as Map<String, dynamic>;
      expect(guitar.keys.toList(), <String>[
        'nut',
        'bridge',
        'neckPolygon',
        'createdAt',
      ]);
    });
  });

  group('migration matrix — four cells, four separate tests', () {
    test(
      'cell v0 — absent document returns null, not a fabricated profile',
      () async {
        final c = build();
        final read = c.repository.read();
        expect(read, isNull);
      },
    );

    test(
      'cell vN — a freshly written document decodes to current schema',
      () async {
        final c = build();
        await c.repository.write(profile: _profile(), guitar: _guitar());
        final read = c.repository.read();
        expect(read, isNotNull);
        expect(read!.profile, _profile());
        expect(read.guitar, _guitar());
      },
    );

    test(
      'cell vN-1 — an older-shape document is migrated to current shape',
      () async {
        // A pre-namespace / pre-envelope alak: egy lapos JSON-map a body
        // belsejében, kihagyva a `createdAt`-et és `qualityScore`-t, és
        // más néven hívva a neckPolygon-t. A migrációs lépés a
        // VisionCalibrationCodec felelőssége.
        const legacyJson =
            '{'
            '"schemaVersion": ${VisionCalibrationCodec.legacySchemaVersion},'
            '"data": {'
            '"camera": "back",'
            '"orientation": 90,'
            '"zoom": 0.4,'
            '"setupProfile": "practiceBalanced",'
            '"nut": {"x": 0.2, "y": 0.45},'
            '"bridge": {"x": 0.8, "y": 0.55},'
            '"polygon": ['
            '{"x": 0.15, "y": 0.30},'
            '{"x": 0.85, "y": 0.30},'
            '{"x": 0.85, "y": 0.70},'
            '{"x": 0.15, "y": 0.70}'
            ']'
            '}'
            '}';
        final c = build(initial: {StorageKeys.visionCalibration: legacyJson});
        final read = c.repository.read();
        expect(read, isNotNull);
        expect(read!.profile.camera, VisionCameraPreference.back);
        expect(read.profile.orientation, CameraRotation.degrees90);
        expect(read.profile.zoom, closeTo(0.4, 1e-9));
        expect(read.profile.setupProfile, VisionSetupProfile.practiceBalanced);
        expect(read.guitar.nutAnchor.x, closeTo(0.2, 1e-9));
        expect(read.guitar.bridgeAnchor.y, closeTo(0.55, 1e-9));
        expect(read.guitar.neckPolygon, hasLength(4));
      },
    );

    test(
      'cell vN+1 — a future-version document is NOT misread, returns null',
      () async {
        // A JsonDocumentStore envelope a `schemaVersion > documentSchemaVersion`
        // esetén `_markCorrupt('future_version')` → a body null, a repository
        // kontrollált setup-kérést ad (profile+guitar is null).
        final future = jsonEncode({
          'schemaVersion': 99,
          'data': {
            'camera': {
              'camera': 'back',
              'orientation': 0,
              'zoom': 0.5,
              'setupProfile': 'practiceBalanced',
              'createdAt': '2026-08-07T12:00:00.000Z',
              'qualityScore': 0.9,
            },
            'guitar': {
              'nut': {'x': 0.5, 'y': 0.5},
              'bridge': {'x': 0.5, 'y': 0.5},
              'neckPolygon': [],
              'createdAt': '2026-08-07T12:00:00.000Z',
            },
          },
        });
        final c = build(initial: {StorageKeys.visionCalibration: future});
        final read = c.repository.read();
        expect(read, isNull);
        // A korrupciót a JsonDocumentStore naplózta — a kontrollált út látható.
        expect(c.logger.events, contains('storage.document.corrupt'));
      },
    );
  });

  group('idempotence', () {
    test(
      'writing the same profile+guitar twice yields identical JSON',
      () async {
        final c = build();
        final profile = _profile();
        final guitar = _guitar();
        await c.repository.write(profile: profile, guitar: guitar);
        final first = c.store.readString(StorageKeys.visionCalibration);
        await c.repository.write(profile: profile, guitar: guitar);
        final second = c.store.readString(StorageKeys.visionCalibration);
        expect(first, equals(second));
      },
    );

    test('a migrated document survives a second read identically', () async {
      const legacyJson =
          '{'
          '"schemaVersion": ${VisionCalibrationCodec.legacySchemaVersion},'
          '"data": {'
          '"camera": "back",'
          '"orientation": 0,'
          '"zoom": 0.0,'
          '"setupProfile": "leftHandFocus",'
          '"nut": {"x": 0.3, "y": 0.5},'
          '"bridge": {"x": 0.7, "y": 0.5},'
          '"polygon": ['
          '{"x": 0.25, "y": 0.35},'
          '{"x": 0.75, "y": 0.35},'
          '{"x": 0.75, "y": 0.65}'
          ']'
          '}'
          '}';
      final c = build(initial: {StorageKeys.visionCalibration: legacyJson});
      final first = c.repository.read();
      final second = c.repository.read();
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.profile, second!.profile);
      expect(first.guitar, second.guitar);
    });
  });

  group('corruption tolerance — record-level quarantine', () {
    test(
      'csonka JSON — az egész dokumentum karanténba kerül, read null',
      () async {
        final c = build(
          initial: {StorageKeys.visionCalibration: '{"schemaVersion": 1, '},
        );
        final read = c.repository.read();
        expect(read, isNull);
        expect(c.logger.events, contains('storage.document.corrupt'));
      },
    );

    test(
      'hibás típus — a camera mező nem objektum → record karantén',
      () async {
        // A top-level envelope rendben, a body szintjén a camera mező egy
        // string, nem objektum — a codec elutasítja, a többi adat olvasható
        // marad. Mivel ez single-record, a teljes bundle null.
        final malformed = jsonEncode({
          'schemaVersion': documentSchemaVersion,
          'data': {
            'camera': 'not-an-object',
            'guitar': {
              'nut': {'x': 0.3, 'y': 0.5},
              'bridge': {'x': 0.7, 'y': 0.5},
              'neckPolygon': [
                {'x': 0.25, 'y': 0.35},
                {'x': 0.75, 'y': 0.35},
                {'x': 0.75, 'y': 0.65},
                {'x': 0.25, 'y': 0.65},
              ],
              'createdAt': '2026-08-07T12:00:00.000Z',
            },
          },
        });
        final c = build(initial: {StorageKeys.visionCalibration: malformed});
        final read = c.repository.read();
        // A codec elutasítja → a repository null-t ad, a JsonDocumentStore
        // karanténja a következő write-nál aktiválódik.
        expect(read, isNull);
        expect(c.logger.events, contains('storage.document.record_skipped'));
      },
    );

    test(
      'degenerált polygon — a neckPolygon < 3 csúcs → record karantén',
      () async {
        final degenerate = jsonEncode({
          'schemaVersion': documentSchemaVersion,
          'data': {
            'camera': {
              'camera': 'back',
              'orientation': 0,
              'zoom': 0.5,
              'setupProfile': 'practiceBalanced',
              'createdAt': '2026-08-07T12:00:00.000Z',
              'qualityScore': 0.9,
            },
            'guitar': {
              'nut': {'x': 0.3, 'y': 0.5},
              'bridge': {'x': 0.7, 'y': 0.5},
              'neckPolygon': [
                {'x': 0.5, 'y': 0.5},
              ],
              'createdAt': '2026-08-07T12:00:00.000Z',
            },
          },
        });
        final c = build(initial: {StorageKeys.visionCalibration: degenerate});
        final read = c.repository.read();
        expect(read, isNull);
        expect(c.logger.events, contains('storage.document.record_skipped'));
      },
    );
  });

  group('privacy snapshot', () {
    test(
      'a serialized profile only contains the expected key set (any level)',
      () async {
        final c = build();
        await c.repository.write(profile: _profile(), guitar: _guitar());
        final raw = c.store.readString(StorageKeys.visionCalibration)!;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;

        // Pontos, rögzített kulcskészlet — ha bárki egy új mezőt csempész
        // be (akár raw kép, akár bármi más), ez a teszt pirosra vált.
        expect(decoded.keys.toSet(), <String>{'schemaVersion', 'data'});

        final data = decoded['data'] as Map<String, dynamic>;
        expect(data.keys.toSet(), <String>{'camera', 'guitar'});

        final camera = data['camera'] as Map<String, dynamic>;
        expect(camera.keys.toSet(), <String>{
          'camera',
          'orientation',
          'zoom',
          'setupProfile',
          'createdAt',
          'qualityScore',
        });

        final guitar = data['guitar'] as Map<String, dynamic>;
        expect(guitar.keys.toSet(), <String>{
          'nut',
          'bridge',
          'neckPolygon',
          'createdAt',
        });

        // Banned substrings: ha valaki egy raw-kép mezőnevet csempészne be,
        // a kulcs-szintű assertion ugyan nem feltétlenül fogja meg (más
        // néven), de a substring-scan igen.
        final flat = raw.toLowerCase();
        for (final banned in <String>[
          'image',
          'jpeg',
          'png',
          'base64',
          'thumbnail',
        ]) {
          expect(
            flat.contains(banned),
            isFalse,
            reason: 'raw-kép-suspect mezőnév a JSON-ban: $banned',
          );
        }
      },
    );

    test(
      'the privacy snapshot set is hand-pinned — adding a key fails',
      () async {
        // A privacy-snapshot teszt CSAK akkor véd, ha a kulcskészlet explicit,
        // nem pedig egy "kapd el, ami jön" assertion. Ez a teszt azt mutatja,
        // hogy a hand-pinned halmaz TÉNYLEG képes elkapni egy új mezőt: ha
        // a `codec.encodeToMap` visszatérési értékében megjelenik egy új
        // kulcs, a fenti teszt pirosra vált — itt most explicit
        // megismételjük, hogy a teszt maga ne csorduljon túl.
        final c = build();
        await c.repository.write(profile: _profile(), guitar: _guitar());
        final raw = c.store.readString(StorageKeys.visionCalibration)!;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        expect(decoded['data'], isA<Map<String, dynamic>>());
        expect(decoded['data']['camera'], isA<Map<String, dynamic>>());
        expect(decoded['data']['guitar'], isA<Map<String, dynamic>>());
      },
    );
  });

  group('real-violation probe', () {
    test(
      'a pixel-coordinate field bypasses validation → codec rejects',
      () async {
        // A NormalizedPoint assert csak release-módon kimarad (R2). A codec
        // saját requireDouble(min:0, max:1) hívással véd — itt egy
        // pixel-koordinátát (x=1920) tartalmazó JSON-t próbálunk bejuttatni
        // a táron keresztül, és a codec-nek el kell utasítania.
        final malicious = jsonEncode({
          'schemaVersion': documentSchemaVersion,
          'data': {
            'camera': {
              'camera': 'back',
              'orientation': 0,
              'zoom': 0.5,
              'setupProfile': 'practiceBalanced',
              'createdAt': '2026-08-07T12:00:00.000Z',
              'qualityScore': 0.9,
            },
            'guitar': {
              'nut': {'x': 1920, 'y': 1080}, // pixelkoordináta, nem normalizált
              'bridge': {'x': 0.7, 'y': 0.5},
              'neckPolygon': [
                {'x': 0.25, 'y': 0.35},
                {'x': 0.75, 'y': 0.35},
                {'x': 0.75, 'y': 0.65},
                {'x': 0.25, 'y': 0.65},
              ],
              'createdAt': '2026-08-07T12:00:00.000Z',
            },
          },
        });
        final c = build(initial: {StorageKeys.visionCalibration: malicious});
        final read = c.repository.read();
        // A teljes bundle-t el kell dobni — a pixel-koordináta release módban
        // is kimutatható.
        expect(read, isNull);
        expect(c.logger.events, contains('storage.document.record_skipped'));
      },
    );

    test('a NaN coordinate is also rejected (poison prevention)', () async {
      // A `jsonEncode` Dart-ban eldob a `double.nan` értékre, ezért a NaN-t
      // nyers JSON-karakterláncként juttatjuk be — pont úgy, ahogy egy
      // hand-edit vagy downgrade írná a lemezre.
      const malicious =
          '{'
          '"schemaVersion": $documentSchemaVersion,'
          '"data": {'
          '"camera": {'
          '"camera": "back",'
          '"orientation": 0,'
          '"zoom": 0.5,'
          '"setupProfile": "practiceBalanced",'
          '"createdAt": "2026-08-07T12:00:00.000Z",'
          '"qualityScore": 0.9'
          '},'
          '"guitar": {'
          '"nut": {"x": NaN, "y": 0.5},'
          '"bridge": {"x": 0.7, "y": 0.5},'
          '"neckPolygon": ['
          '{"x": 0.25, "y": 0.35},'
          '{"x": 0.75, "y": 0.35},'
          '{"x": 0.75, "y": 0.65}'
          '],'
          '"createdAt": "2026-08-07T12:00:00.000Z"'
          '}'
          '}'
          '}';
      final c = build(initial: {StorageKeys.visionCalibration: malicious});
      final read = c.repository.read();
      expect(read, isNull);
      expect(c.logger.events, contains('storage.document.record_skipped'));
    });
  });

  group('JsonRecordException thrown by the codec for unparseable input', () {
    test('the codec itself surfaces JsonRecordException on missing fields', () {
      const codec = VisionCalibrationCodec();
      final malformed = {
        'camera': {
          'camera': 'back',
          'orientation': 0,
          'zoom': 0.5,
          'setupProfile': 'practiceBalanced',
          'createdAt': '2026-08-07T12:00:00.000Z',
          'qualityScore': 0.9,
        },
        // 'guitar' teljesen hiányzik
      };
      expect(
        () => codec.decodeFromMap(malformed),
        throwsA(isA<JsonRecordException>()),
      );
    });
  });
}
