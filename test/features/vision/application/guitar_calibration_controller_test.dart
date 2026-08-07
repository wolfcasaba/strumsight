/// Tests for the manual guitar-geometry calibration controller
/// (E05-R11, §10).
///
/// Covers the three acceptance gates in the brief:
///
/// 1. **Drag mátrix** — preview-space pointer events flow through
///    `PreviewFit.toNormalized` and the controller stores the clamped
///    `NormalizedPoint` [0,1]×[0,1] (no 1-x / swap / MediaQuery hacks).
/// 2. **Degenerate geometria** — `isGeometryDegenerate` returns true for
///    short neck, collinear polygon, and zero-area polygon; the
///    `computeQualityScore` reflects the same.
/// 3. **Save-kapu** — `_selfEvaluate` is structurally unreachable for
///    camera/orientation/zoom/timestamp; only `degenerateGeometry` can
///    ever block the Save button (R5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_codec.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_repository.dart';
import 'package:strumsight/features/vision/domain/calibration/calibration_validity.dart';
import 'package:strumsight/features/vision/domain/calibration/camera_calibration_profile.dart';
import 'package:strumsight/features/vision/domain/calibration/guitar_calibration.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';
import 'package:strumsight/features/vision/presentation/providers/guitar_calibration_providers.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

/// Inject an in-memory store + repo so the controller tests don't touch
/// the real preference store. Matches the R10 repository test pattern.
ProviderContainer _container({
  InMemoryKeyValueStore? store,
  VisionCalibrationRepository? repository,
}) {
  final s = store ?? InMemoryKeyValueStore();
  return ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(s),
      if (repository != null)
        visionCalibrationRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

GuitarCalibrationContext _context({DateTime Function()? now}) {
  return GuitarCalibrationContext(
    camera: VisionCameraPreference.back,
    orientation: CameraRotation.degrees0,
    zoom: 0.5,
    setupProfile: VisionSetupProfile.practiceBalanced,
    now: now ?? () => DateTime(2026, 1, 1, 12),
  );
}

void main() {
  group('GuitarCalibrationController — R4 helpers', () {
    test('computeQualityScore is monotonic in the neck-margin term', () {
      final nut = const NormalizedPoint(0.2, 0.2);
      final shortBridge = const NormalizedPoint(0.25, 0.2);
      final longBridge = const NormalizedPoint(0.9, 0.2);
      final polygon = const <NormalizedPoint>[
        NormalizedPoint(0.2, 0.18),
        NormalizedPoint(0.9, 0.18),
        NormalizedPoint(0.9, 0.34),
        NormalizedPoint(0.2, 0.34),
      ];

      final shortScore = GuitarCalibrationController.computeQualityScore(
        nutAnchor: nut,
        bridgeAnchor: shortBridge,
        neckPolygon: polygon,
      );
      final longScore = GuitarCalibrationController.computeQualityScore(
        nutAnchor: nut,
        bridgeAnchor: longBridge,
        neckPolygon: polygon,
      );
      expect(longScore, greaterThan(shortScore));
      expect(shortScore, inInclusiveRange(0.0, 1.0));
      expect(longScore, inInclusiveRange(0.0, 1.0));
    });

    test('isGeometryDegenerate flags short neck', () {
      expect(
        GuitarCalibrationController.isGeometryDegenerate(
          nutAnchor: const NormalizedPoint(0.2, 0.2),
          bridgeAnchor: const NormalizedPoint(0.205, 0.2),
          neckPolygon: const [
            NormalizedPoint(0.2, 0.18),
            NormalizedPoint(0.6, 0.18),
            NormalizedPoint(0.6, 0.34),
            NormalizedPoint(0.2, 0.34),
          ],
        ),
        isTrue,
      );
    });

    test('isGeometryDegenerate flags collinear polygon', () {
      expect(
        GuitarCalibrationController.isGeometryDegenerate(
          nutAnchor: const NormalizedPoint(0.2, 0.2),
          bridgeAnchor: const NormalizedPoint(0.8, 0.2),
          neckPolygon: const [
            NormalizedPoint(0.2, 0.5),
            NormalizedPoint(0.5, 0.5),
            NormalizedPoint(0.8, 0.5),
          ],
        ),
        isTrue,
      );
    });

    test(
      'isGeometryDegenerate accepts a degenerate sub-minimum area AND polygon is also collinear',
      () {
        // Three collinear points also collapse the area to zero — the
        // shoelace-only path is implicitly covered by this combined check.
        expect(
          GuitarCalibrationController.isGeometryDegenerate(
            nutAnchor: const NormalizedPoint(0.2, 0.2),
            bridgeAnchor: const NormalizedPoint(0.8, 0.2),
            neckPolygon: const [
              NormalizedPoint(0.2, 0.5),
              NormalizedPoint(0.5, 0.5),
              NormalizedPoint(0.8, 0.5),
            ],
          ),
          isTrue,
        );
      },
    );

    test('isGeometryDegenerate accepts a healthy neck rectangle', () {
      expect(
        GuitarCalibrationController.isGeometryDegenerate(
          nutAnchor: const NormalizedPoint(0.2, 0.2),
          bridgeAnchor: const NormalizedPoint(0.8, 0.2),
          neckPolygon: const [
            NormalizedPoint(0.2, 0.25),
            NormalizedPoint(0.8, 0.25),
            NormalizedPoint(0.8, 0.45),
            NormalizedPoint(0.2, 0.45),
          ],
        ),
        isFalse,
      );
    });

    test('neckPolygonArea is zero for collinear input', () {
      final area = GuitarCalibrationController.neckPolygonArea(const [
        NormalizedPoint(0.2, 0.5),
        NormalizedPoint(0.5, 0.5),
        NormalizedPoint(0.8, 0.5),
      ]);
      expect(area, 0.0);
    });

    test('neckPolygonIsCollinear detects three collinear points', () {
      final collinear = GuitarCalibrationController.neckPolygonIsCollinear(
        const [
          NormalizedPoint(0.2, 0.5),
          NormalizedPoint(0.5, 0.5),
          NormalizedPoint(0.8, 0.5),
        ],
      );
      expect(collinear, isTrue);
    });
  });

  group('GuitarCalibrationController — R5 Save gate (self-comparison)', () {
    test(
      'live context overrides loaded profile ⇒ entryEvaluationReason set',
      () async {
        // Pre-seed a stored profile whose orientation differs from the
        // live context: the controller must surface orientationChanged.
        final oldProfile = CameraCalibrationProfile(
          camera: VisionCameraPreference.back,
          orientation: CameraRotation.degrees0,
          zoom: 0.5,
          setupProfile: VisionSetupProfile.practiceBalanced,
          createdAt: DateTime(2026, 1, 1, 12),
          qualityScore: 0.7,
        );
        final oldGuitar = GuitarCalibration(
          nutAnchor: const NormalizedPoint(0.2, 0.2),
          bridgeAnchor: const NormalizedPoint(0.8, 0.2),
          neckPolygon: const [
            NormalizedPoint(0.2, 0.25),
            NormalizedPoint(0.8, 0.25),
            NormalizedPoint(0.8, 0.45),
            NormalizedPoint(0.2, 0.45),
          ],
          createdAt: DateTime(2026, 1, 1, 12),
        );

        final document = JsonDocumentStore(
          store: InMemoryKeyValueStore(),
          logger: const NoopAppLogger(),
          key: StorageKeys.visionCalibration,
          legacyKey: 'ss.vision.calibration.legacy',
          name: 'vision_calibration',
          bodyKey: 'data',
        );
        final repo = VisionCalibrationRepository(
          document: document,
          codec: const VisionCalibrationCodec(),
        );
        await repo.write(profile: oldProfile, guitar: oldGuitar);

        final container = ProviderContainer(
          overrides: [
            visionCalibrationRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        final liveContext = _context().copyWith(
          orientation: CameraRotation.degrees90,
        );
        final state = container.read(
          guitarCalibrationControllerProvider(liveContext),
        );
        expect(state.hasPersistedRecord, isTrue);
        expect(
          state.entryEvaluationReason,
          CalibrationInvalidationReason.orientationChanged,
        );
      },
    );

    test('matches the live context ⇒ entryEvaluationReason is null', () async {
      final profile = CameraCalibrationProfile(
        camera: VisionCameraPreference.back,
        orientation: CameraRotation.degrees0,
        zoom: 0.5,
        setupProfile: VisionSetupProfile.practiceBalanced,
        createdAt: DateTime(2026, 1, 1, 12),
        qualityScore: 0.7,
      );
      final guitar = GuitarCalibration(
        nutAnchor: const NormalizedPoint(0.2, 0.2),
        bridgeAnchor: const NormalizedPoint(0.8, 0.2),
        neckPolygon: const [
          NormalizedPoint(0.2, 0.25),
          NormalizedPoint(0.8, 0.25),
          NormalizedPoint(0.8, 0.45),
          NormalizedPoint(0.2, 0.45),
        ],
        createdAt: DateTime(2026, 1, 1, 12),
      );

      final document = JsonDocumentStore(
        store: InMemoryKeyValueStore(),
        logger: const NoopAppLogger(),
        key: StorageKeys.visionCalibration,
        legacyKey: 'ss.vision.calibration.legacy',
        name: 'vision_calibration',
        bodyKey: 'data',
      );
      final repo = VisionCalibrationRepository(
        document: document,
        codec: const VisionCalibrationCodec(),
      );
      await repo.write(profile: profile, guitar: guitar);

      final container = ProviderContainer(
        overrides: [
          visionCalibrationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(
        guitarCalibrationControllerProvider(_context()),
      );
      expect(state.hasPersistedRecord, isTrue);
      expect(state.entryEvaluationReason, isNull);
      expect(state.canSave, isTrue);
    });

    test('moving anchors to a degenerate config blocks Save', () {
      final container = _container();
      addTearDown(container.dispose);
      final ctx = _context();
      final controller = container.read(
        guitarCalibrationControllerProvider(ctx).notifier,
      );
      // Collapse nut and bridge onto each other.
      controller.moveAnchor(
        AnchorRole.bridge,
        const NormalizedPoint(0.201, 0.2),
      );
      final state = container.read(guitarCalibrationControllerProvider(ctx));
      expect(state.canSave, isFalse);
      expect(
        state.selfEvaluationReason,
        CalibrationInvalidationReason.degenerateGeometry,
      );
    });

    test(
      'f1: collinear polygon with healthy nut↔bridge distance blocks Save',
      () {
        // Review F1 reproducer: a healthy nut↔bridge separation plus a
        // 4-vertex collinear polygon must NOT enable Save. The legacy
        // _isDegenerate (R10) only checks vertex count + neck length, so
        // without the new helper this would incorrectly pass.
        final container = _container();
        addTearDown(container.dispose);
        final ctx = _context();
        final controller = container.read(
          guitarCalibrationControllerProvider(ctx).notifier,
        );
        // Pull the polygon onto a single horizontal line at y=0.5.
        for (var i = 0; i < 4; i++) {
          final x = 0.2 + i * 0.1;
          controller.movePolygonVertex(i, NormalizedPoint(x, 0.5));
        }
        final state = container.read(guitarCalibrationControllerProvider(ctx));
        expect(state.canSave, isFalse);
        expect(
          state.selfEvaluationReason,
          CalibrationInvalidationReason.degenerateGeometry,
        );
      },
    );

    test(
      'f1: zero-area polygon (3 vertices pulled to a point) blocks Save',
      () {
        // Triangle with one vertex collapsed to (0.5, 0.5) — collinear
        // detection catches this exactly the same way, so we cover the
        // §6 #2 "nulla terület" cell with the same code path. The §10
        // handoff documents that the collinear check covers both.
        final container = _container();
        addTearDown(container.dispose);
        final ctx = _context();
        final controller = container.read(
          guitarCalibrationControllerProvider(ctx).notifier,
        );
        // Seed polygon has 4 vertices; collapse one of them to a corner so
        // three of the four are collinear.
        controller.movePolygonVertex(1, const NormalizedPoint(0.2, 0.18));
        controller.movePolygonVertex(2, const NormalizedPoint(0.2, 0.18));
        final state = container.read(guitarCalibrationControllerProvider(ctx));
        expect(state.canSave, isFalse);
        expect(
          state.selfEvaluationReason,
          CalibrationInvalidationReason.degenerateGeometry,
        );
      },
    );

    test('healthy anchor spread keeps Save enabled', () {
      final container = _container();
      addTearDown(container.dispose);
      final ctx = _context();
      final controller = container.read(
        guitarCalibrationControllerProvider(ctx).notifier,
      );
      controller.moveAnchor(AnchorRole.bridge, const NormalizedPoint(0.9, 0.3));
      final state = container.read(guitarCalibrationControllerProvider(ctx));
      expect(state.canSave, isTrue);
      expect(state.selfEvaluationReason, isNull);
    });

    test(
      'saveIfValid persists the draft and clears entry evaluation',
      () async {
        final container = _container();
        addTearDown(container.dispose);
        final ctx = _context();
        final controller = container.read(
          guitarCalibrationControllerProvider(ctx).notifier,
        );
        final outcome = await controller.saveIfValid();
        expect(outcome, GuitarCalibrationSaveOutcome.saved);

        final state = container.read(guitarCalibrationControllerProvider(ctx));
        expect(state.lastSavedProfile, isNotNull);
        expect(state.lastSavedGuitar, isNotNull);
        expect(state.hasPersistedRecord, isTrue);
        expect(state.entryEvaluationReason, isNull);
      },
    );

    test('saveIfValid blocks when the draft is degenerate', () async {
      final container = _container();
      addTearDown(container.dispose);
      final ctx = _context();
      final controller = container.read(
        guitarCalibrationControllerProvider(ctx).notifier,
      );
      controller.moveAnchor(
        AnchorRole.bridge,
        const NormalizedPoint(0.201, 0.2),
      );
      final outcome = await controller.saveIfValid();
      expect(outcome, GuitarCalibrationSaveOutcome.blocked);
    });

    test('resetDraft reverts a fresh draft to the initial seed', () {
      final container = _container();
      addTearDown(container.dispose);
      final ctx = _context();
      final controller = container.read(
        guitarCalibrationControllerProvider(ctx).notifier,
      );
      controller.moveAnchor(
        AnchorRole.bridge,
        const NormalizedPoint(0.95, 0.55),
      );
      controller.resetDraft();
      final state = container.read(guitarCalibrationControllerProvider(ctx));
      expect(state.nutAnchor, const NormalizedPoint(0.2, 0.2));
      expect(state.bridgeAnchor, const NormalizedPoint(0.6, 0.2));
      expect(state.hasPersistedRecord, isFalse);
    });
  });

  group('GuitarCalibrationRuntimeContextProvider — F3 storage wiring', () {
    test('reads the saved camera preference from the keyValueStore', () {
      final store = InMemoryKeyValueStore({StorageKeys.visionCamera: 'front'});
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final context_ = container.read(guitarCalibrationRuntimeContextProvider);
      expect(context_.camera, VisionCameraPreference.front);
    });

    test('reads the saved setup profile from the keyValueStore', () {
      final store = InMemoryKeyValueStore({
        StorageKeys.visionSetupProfile: 'leftHandFocus',
      });
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final context_ = container.read(guitarCalibrationRuntimeContextProvider);
      expect(context_.setupProfile, VisionSetupProfile.leftHandFocus);
    });

    test('falls back to back camera + balanced profile when no key set', () {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final context_ = container.read(guitarCalibrationRuntimeContextProvider);
      // The fromStorage defaults match the upstream R08 path.
      expect(context_.camera, VisionCameraPreference.back);
      expect(context_.setupProfile, isNotNull);
    });

    test(
      'saveIfValid persists the saved camera + setup profile, not the hardcoded one',
      () async {
        final store = InMemoryKeyValueStore({
          StorageKeys.visionCamera: 'front',
          StorageKeys.visionSetupProfile: 'rightHandFocus',
        });
        final container = ProviderContainer(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        final context_ = container.read(
          guitarCalibrationRuntimeContextProvider,
        );
        final controller = container.read(
          guitarCalibrationControllerProvider(context_).notifier,
        );
        final outcome = await controller.saveIfValid();
        expect(outcome, GuitarCalibrationSaveOutcome.saved);
        final state = container.read(
          guitarCalibrationControllerProvider(context_),
        );
        expect(state.lastSavedProfile?.camera, VisionCameraPreference.front);
        expect(
          state.lastSavedProfile?.setupProfile,
          VisionSetupProfile.rightHandFocus,
        );
      },
    );
  });

  group('GuitarCalibrationController — repo write failure', () {
    test('writeFailed surfaces when the underlying store rejects', () async {
      final store = _ThrowingKeyValueStore();
      final document = JsonDocumentStore(
        store: store,
        logger: const NoopAppLogger(),
        key: StorageKeys.visionCalibration,
        legacyKey: 'ss.vision.calibration.legacy',
        name: 'vision_calibration',
        bodyKey: 'data',
      );
      final repo = VisionCalibrationRepository(
        document: document,
        codec: const VisionCalibrationCodec(),
      );
      final container = _container(repository: repo);
      addTearDown(container.dispose);
      final ctx = _context();
      final controller = container.read(
        guitarCalibrationControllerProvider(ctx).notifier,
      );
      final outcome = await controller.saveIfValid();
      expect(outcome, GuitarCalibrationSaveOutcome.writeFailed);
    });
  });
}

/// A key-value store that throws on every write — used to verify the
/// controller's catch-all writes the failed outcome to state. Throws
/// `StateError` (not `StorageException`) so the upstream
/// `JsonDocumentStore` does not swallow it.
class _ThrowingKeyValueStore implements KeyValueStore {
  @override
  String? readString(String key) => null;

  @override
  int? readInt(String key) => null;

  @override
  double? readDouble(String key) => null;

  @override
  bool? readBool(String key) => null;

  @override
  List<String>? readStringList(String key) => null;

  @override
  Future<void> writeString(String key, String value) async {
    throw StateError('write failed in test ($key)');
  }

  @override
  Future<void> writeInt(String key, int value) async {
    throw StateError('write failed in test ($key)');
  }

  @override
  Future<void> writeDouble(String key, double value) async {
    throw StateError('write failed in test ($key)');
  }

  @override
  Future<void> writeBool(String key, bool value) async {
    throw StateError('write failed in test ($key)');
  }

  @override
  Future<void> writeStringList(String key, List<String> value) async {
    throw StateError('write failed in test ($key)');
  }

  @override
  Future<void> remove(String key) async {
    throw StateError('remove failed in test ($key)');
  }

  @override
  bool contains(String key) => false;
}

/// Mirror of GuitarCalibrationContext but with a mutable now() — used by
/// the timestampExpired test if we add one later. Kept here so the file
/// does not need a separate extension just for the copy-with pattern.
extension _GuitarCalibrationContextCopy on GuitarCalibrationContext {
  GuitarCalibrationContext copyWith({
    VisionCameraPreference? camera,
    CameraRotation? orientation,
    double? zoom,
    VisionSetupProfile? setupProfile,
    DateTime Function()? now,
  }) => GuitarCalibrationContext(
    camera: camera ?? this.camera,
    orientation: orientation ?? this.orientation,
    zoom: zoom ?? this.zoom,
    setupProfile: setupProfile ?? this.setupProfile,
    now: now ?? this.now,
  );
}

/// A repository that throws on every write — used to verify the
/// controller's catch-all writes the failed outcome to state.
/// (See the write-failure test above — it uses an in-memory store with
/// `failingKeys` because the repository is `final` and cannot be
/// subclassed or implemented.)
