/// Manual guitar-geometry calibration UI controller
/// (SDD Ch6 §13.3 / §17.1, E05-R11, ADR 0181).
///
/// Owns the **editor draft** state for the calibration screen: the live
/// `nutAnchor`, `bridgeAnchor`, and `neckPolygon` the user is dragging, plus
/// the precision-zoom factor for the magnifying overlay. The persisted bundle
/// is NOT touched directly — every save goes through the [VisionCalibrationRepository]
/// so the codec/envelope/versioning invariants are reused.
///
/// **Two evaluation sites (§0.0 R5)**:
///
/// 1. **Save gate** — `selfEvaluationReason` calls
///    [CalibrationValidity.evaluate] with the *draft's own*
///    `currentCamera`/`currentOrientation`/`currentZoom`. The draft equals
///    itself, so the camera/orientation/zoom/timestamp triggers are
///    structurally unreachable; only `degenerateGeometry` can fire. This is
///    what makes "Save" the unambiguous single gate (§5.1).
///
/// 2. **Recalibrate-entry staleness** — `entryEvaluationReason` calls evaluate
///    with the **persisted** profile against the **live** runtime context.
///    All five reasons can fire here. Set on load and after explicit
///    Recalibrate; reset on a successful Save.
///
/// **Geometry helpers (§0.0 R4)** — pure, exported for direct widget/
/// controller testing:
///
/// * `neckPolygonArea(...)` — signed shoelace area; zero ⇒ degenerate.
/// * `neckPolygonIsCollinear(...)` — at least one consecutive cross-product
///   near zero ⇒ degenerate; converges on the collinear special case where the
///   area may still be numerically non-zero.
///
/// **Quality score (§0.0 R3)** — single deterministic formula, lives only
/// here. The widget reads the value via the controller and never recomputes.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_coordinate_space.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';
import '../data/persistence/vision_calibration_codec.dart';
import '../data/persistence/vision_calibration_repository.dart';
import '../domain/calibration/calibration_validity.dart';
import '../domain/calibration/camera_calibration_profile.dart';
import '../domain/calibration/guitar_calibration.dart';
import '../domain/vision_setup_profile.dart';

/// Two anchors the editor exposes (SDD §13.3).
enum AnchorRole { nut, bridge }

/// How far a vertex cross-product may deviate from zero before we still
/// accept the polygon. Tighter than 1e-9 makes the collinearity detection
/// sensitive to FP noise at small geometries; looser than 1e-9 lets almost-
/// collinear shapes slip past. Keep conservative.
const double _collinearityEpsilon = 1e-9;

/// Two how far the signed shoelace area may deviate from zero before we
/// reject the polygon as "degenerate". Same reasoning as above.
const double _polygonAreaEpsilon = 1e-9;

/// How far the nut↔bridge normalised distance may exceed
/// [CalibrationValidity.minAnchorSeparation] before its contribution to the
/// quality score saturates. Beyond this, "longer neck" does not make the
/// calibration strictly better — the geometric reasoning flatlines.
const double _qualityNeckSaturation = 0.6;

/// How far the signed shoelace area may approach the "ideal neck rectangle"
/// area (anchored at nut↔bridge) before its contribution saturates. 0.5 =
/// polygon covers half the ideal rectangle.
const double _idealPolygonAreaFraction = 0.5;

/// Static context the controller is told about once at construction time:
/// the current camera preference (back/front), sensor rotation, normalised
/// zoom, and a clock. They are the runtime baseline used by the
/// "Recalibrate-entry" evaluation.
class GuitarCalibrationContext {
  const GuitarCalibrationContext({
    required this.camera,
    required this.orientation,
    required this.zoom,
    required this.setupProfile,
    required this.now,
  });

  final VisionCameraPreference camera;
  final CameraRotation orientation;
  final double zoom;
  final VisionSetupProfile setupProfile;
  final DateTime Function() now;
}

/// Immutable UI state.
final class GuitarCalibrationState {
  const GuitarCalibrationState({
    required this.nutAnchor,
    required this.bridgeAnchor,
    required this.neckPolygon,
    required this.context,
    required this.qualityScore,
    required this.selfEvaluationReason,
    required this.entryEvaluationReason,
    required this.hasPersistedRecord,
    required this.lastSavedProfile,
    required this.lastSavedGuitar,
    required this.lastSaveOutcome,
  });

  final NormalizedPoint nutAnchor;
  final NormalizedPoint bridgeAnchor;
  final List<NormalizedPoint> neckPolygon;

  /// The runtime context bound at controller construction. Immutable for the
  /// lifetime of a controller instance; a new context = new controller.
  final GuitarCalibrationContext context;

  /// `[0, 1]` deterministic score — see [GuitarCalibrationController.computeQualityScore].
  final double qualityScore;

  /// Result of evaluating the *draft against itself* (R5 / §5.1). `null` is
  /// the "valid / Save enabled" signal; non-null blocks Save.
  final CalibrationInvalidationReason? selfEvaluationReason;

  /// Result of evaluating the *persisted record against the live context*
  /// when an existing record was loaded (R5 / §0.0 R5). Drives the entry
  /// banner. `null` means the loaded record is still fresh against the
  /// current camera/orientation/zoom/now.
  final CalibrationInvalidationReason? entryEvaluationReason;

  /// True iff the controller was constructed from a previously persisted
  /// record. Drives Recalibrate visibility.
  final bool hasPersistedRecord;

  /// The persisted bundle the controller was started with (for
  /// Reset semantics: restore the original `nutAnchor`/`bridgeAnchor`/
  /// `neckPolygon` and zero out the dirty flag). `null` if the controller
  /// was created for a new calibration.
  final CameraCalibrationProfile? lastSavedProfile;
  final GuitarCalibration? lastSavedGuitar;

  /// Outcome of the most recent `saveIfValid()` call. Drives the snackbar.
  final GuitarCalibrationSaveOutcome lastSaveOutcome;

  GuitarCalibrationState copyWith({
    NormalizedPoint? nutAnchor,
    NormalizedPoint? bridgeAnchor,
    List<NormalizedPoint>? neckPolygon,
    double? qualityScore,
    CalibrationInvalidationReason? selfEvaluationReason,
    CalibrationInvalidationReason? entryEvaluationReason,
    bool clearEntryEvaluation = false,
    bool? hasPersistedRecord,
    CameraCalibrationProfile? lastSavedProfile,
    GuitarCalibration? lastSavedGuitar,
    GuitarCalibrationSaveOutcome? lastSaveOutcome,
  }) => GuitarCalibrationState(
    nutAnchor: nutAnchor ?? this.nutAnchor,
    bridgeAnchor: bridgeAnchor ?? this.bridgeAnchor,
    neckPolygon: neckPolygon ?? this.neckPolygon,
    context: context,
    qualityScore: qualityScore ?? this.qualityScore,
    selfEvaluationReason: selfEvaluationReason ?? this.selfEvaluationReason,
    entryEvaluationReason: clearEntryEvaluation
        ? null
        : entryEvaluationReason ?? this.entryEvaluationReason,
    hasPersistedRecord: hasPersistedRecord ?? this.hasPersistedRecord,
    lastSavedProfile: lastSavedProfile ?? this.lastSavedProfile,
    lastSavedGuitar: lastSavedGuitar ?? this.lastSavedGuitar,
    lastSaveOutcome: lastSaveOutcome ?? this.lastSaveOutcome,
  );

  /// `true` iff the Save button should be enabled: the self-evaluation
  /// passes (R5 §5.1).
  bool get canSave => selfEvaluationReason == null;

  /// True iff the entry-banner stale reason needs explanation; the widget
  /// renders localised text when this is non-null.
  bool get hasEntryStaleness => entryEvaluationReason != null;
}

/// Outcome of a `saveIfValid()` attempt. Distinct so the controller can
/// surface three different messages: "Saved", "Still invalid (degenerate
/// geometry)" and "Repository write failed".
enum GuitarCalibrationSaveOutcome { none, saved, blocked, writeFailed }

/// Backing document store for the calibration bundle. Lives in the
/// application folder so the controller can read it without a circular
/// import against the presentation providers.
final visionCalibrationDocumentProvider = Provider<JsonDocumentStore>((ref) {
  final store = ref.watch(keyValueStoreProvider);
  final logger = ref.watch(appLoggerProvider);
  return JsonDocumentStore(
    store: store,
    logger: logger,
    key: StorageKeys.visionCalibration,
    legacyKey: 'ss.vision.calibration.legacy',
    name: 'vision_calibration',
    bodyKey: 'data',
  );
});

/// The singleton calibration repository bound to the active preference
/// store. Tests override this with an in-memory `JsonDocumentStore`.
final visionCalibrationRepositoryProvider =
    Provider<VisionCalibrationRepository>((ref) {
      final document = ref.watch(visionCalibrationDocumentProvider);
      return VisionCalibrationRepository(
        document: document,
        codec: const VisionCalibrationCodec(),
      );
    });

/// Riverpod-bound controller. Holds the editor draft and the runtime
/// context; uses the [VisionCalibrationRepository] for persistence.
///
/// Riverpod 3.3.2 removed `FamilyNotifier` (CHANGELOG: 114). The pattern is
/// `extends Notifier<StateT>` + a constructor that captures the family arg
/// as a field; `NotifierProvider.family<...>(Notifier.new)` calls the
/// constructor for each family entry.
class GuitarCalibrationController extends Notifier<GuitarCalibrationState> {
  GuitarCalibrationController(this.context);

  /// Runtime context bound at controller construction (the family arg).
  /// Immutable for the lifetime of a controller instance; a new context
  /// = new controller (a different family entry).
  final GuitarCalibrationContext context;

  late VisionCalibrationRepository _repository;

  @override
  GuitarCalibrationState build() {
    _repository = ref.read(visionCalibrationRepositoryProvider);
    final existing = _repository.read();
    final initialPolygon = _defaultSeedPolygon();
    final nut = const NormalizedPoint(0.2, 0.2);
    final bridge = const NormalizedPoint(0.6, 0.2);
    if (existing == null) {
      return GuitarCalibrationState(
        nutAnchor: nut,
        bridgeAnchor: bridge,
        neckPolygon: initialPolygon,
        context: context,
        qualityScore: computeQualityScore(
          nutAnchor: nut,
          bridgeAnchor: bridge,
          neckPolygon: initialPolygon,
        ),
        selfEvaluationReason: _selfEvaluate(
          nut,
          bridge,
          initialPolygon,
          context,
          context.now(),
        ),
        entryEvaluationReason: null,
        hasPersistedRecord: false,
        lastSavedProfile: null,
        lastSavedGuitar: null,
        lastSaveOutcome: GuitarCalibrationSaveOutcome.none,
      );
    }
    final loadedProfile = existing.profile;
    final loadedGuitar = existing.guitar;
    return GuitarCalibrationState(
      nutAnchor: loadedGuitar.nutAnchor,
      bridgeAnchor: loadedGuitar.bridgeAnchor,
      neckPolygon: loadedGuitar.neckPolygon,
      context: context,
      qualityScore: computeQualityScore(
        nutAnchor: loadedGuitar.nutAnchor,
        bridgeAnchor: loadedGuitar.bridgeAnchor,
        neckPolygon: loadedGuitar.neckPolygon,
      ),
      // The draft *is* the persisted bundle, so self-evaluate cannot fire
      // anything other than degenerateGeometry (R5).
      selfEvaluationReason: _selfEvaluate(
        loadedGuitar.nutAnchor,
        loadedGuitar.bridgeAnchor,
        loadedGuitar.neckPolygon,
        context,
        context.now(),
      ),
      // Recalibrate-entry path (R5): saved record vs live context. All
      // five reasons can fire here.
      entryEvaluationReason: CalibrationValidity.evaluate(
        profile: loadedProfile,
        guitar: loadedGuitar,
        currentCamera: context.camera,
        currentOrientation: context.orientation,
        currentZoom: context.zoom,
        now: context.now(),
      ),
      hasPersistedRecord: true,
      lastSavedProfile: loadedProfile,
      lastSavedGuitar: loadedGuitar,
      lastSaveOutcome: GuitarCalibrationSaveOutcome.none,
    );
  }

  /// Default seed polygon: a minimal neck-shaped quad spanning the nut↔bridge
  /// axis. Two parallel lines, one above and one below the axis.
  List<NormalizedPoint> _defaultSeedPolygon() => const <NormalizedPoint>[
    NormalizedPoint(0.2, 0.18),
    NormalizedPoint(0.6, 0.18),
    NormalizedPoint(0.6, 0.34),
    NormalizedPoint(0.2, 0.34),
  ];

  /// Move the named anchor to [point]. Clamps to `[0,1]×[0,1]`.
  /// **No** snap-to-grid or auto-correction — the clamp is the only
  /// coordinate policy; downstream evaluation decides validity.
  void moveAnchor(AnchorRole role, NormalizedPoint point) {
    final clamped = NormalizedPoint(
      point.x.clamp(0.0, 1.0).toDouble(),
      point.y.clamp(0.0, 1.0).toDouble(),
    );
    final newNut = role == AnchorRole.nut ? clamped : state.nutAnchor;
    final newBridge = role == AnchorRole.bridge ? clamped : state.bridgeAnchor;
    final polygon = state.neckPolygon;
    state = state.copyWith(
      nutAnchor: newNut,
      bridgeAnchor: newBridge,
      selfEvaluationReason: _selfEvaluate(
        newNut,
        newBridge,
        polygon,
        state.context,
        state.context.now(),
      ),
      qualityScore: computeQualityScore(
        nutAnchor: newNut,
        bridgeAnchor: newBridge,
        neckPolygon: polygon,
      ),
      // Reset the previous save outcome — a draft change invalidates any
      // "saved" toast.
      lastSaveOutcome: GuitarCalibrationSaveOutcome.none,
    );
  }

  /// Move a polygon vertex. Clamps the same way as [moveAnchor].
  void movePolygonVertex(int index, NormalizedPoint point) {
    if (index < 0 || index >= state.neckPolygon.length) return;
    final clamped = NormalizedPoint(
      point.x.clamp(0.0, 1.0).toDouble(),
      point.y.clamp(0.0, 1.0).toDouble(),
    );
    final newPolygon = <NormalizedPoint>[
      for (var i = 0; i < state.neckPolygon.length; i++)
        i == index ? clamped : state.neckPolygon[i],
    ];
    state = state.copyWith(
      neckPolygon: newPolygon,
      selfEvaluationReason: _selfEvaluate(
        state.nutAnchor,
        state.bridgeAnchor,
        newPolygon,
        state.context,
        state.context.now(),
      ),
      qualityScore: computeQualityScore(
        nutAnchor: state.nutAnchor,
        bridgeAnchor: state.bridgeAnchor,
        neckPolygon: newPolygon,
      ),
      lastSaveOutcome: GuitarCalibrationSaveOutcome.none,
    );
  }

  /// Reset: restore the initial draft — for a fresh session this re-seeds
  /// the defaults; for a loaded session it restores the persisted record.
  void resetDraft() {
    final profile = state.lastSavedProfile;
    final guitar = state.lastSavedGuitar;
    if (profile == null || guitar == null) {
      final polygon = _defaultSeedPolygon();
      final nut = const NormalizedPoint(0.2, 0.2);
      final bridge = const NormalizedPoint(0.6, 0.2);
      state = state.copyWith(
        nutAnchor: nut,
        bridgeAnchor: bridge,
        neckPolygon: polygon,
        selfEvaluationReason: _selfEvaluate(
          nut,
          bridge,
          polygon,
          state.context,
          state.context.now(),
        ),
        qualityScore: computeQualityScore(
          nutAnchor: nut,
          bridgeAnchor: bridge,
          neckPolygon: polygon,
        ),
        clearEntryEvaluation: true,
        lastSaveOutcome: GuitarCalibrationSaveOutcome.none,
      );
      return;
    }
    state = state.copyWith(
      nutAnchor: guitar.nutAnchor,
      bridgeAnchor: guitar.bridgeAnchor,
      neckPolygon: guitar.neckPolygon,
      selfEvaluationReason: _selfEvaluate(
        guitar.nutAnchor,
        guitar.bridgeAnchor,
        guitar.neckPolygon,
        state.context,
        state.context.now(),
      ),
      qualityScore: computeQualityScore(
        nutAnchor: guitar.nutAnchor,
        bridgeAnchor: guitar.bridgeAnchor,
        neckPolygon: guitar.neckPolygon,
      ),
      lastSaveOutcome: GuitarCalibrationSaveOutcome.none,
    );
  }

  /// Recalibrate: invalidate the persisted record by overwriting it with
  /// the fresh seed defaults AND clear the entry staleness banner. The
  /// Recalibrate UI flow already shows a confirmation dialog (the widget
  /// layer — tilos zóna itt).
  ///
  /// Returns the outcome so the widget can branch on it.
  Future<GuitarCalibrationSaveOutcome> recalibrate() async {
    final polygon = _defaultSeedPolygon();
    final nut = const NormalizedPoint(0.2, 0.2);
    final bridge = const NormalizedPoint(0.6, 0.2);
    final profile = CameraCalibrationProfile(
      camera: state.context.camera,
      orientation: state.context.orientation,
      zoom: state.context.zoom,
      setupProfile: state.context.setupProfile,
      createdAt: state.context.now(),
      qualityScore: 0,
    );
    final guitar = GuitarCalibration(
      nutAnchor: nut,
      bridgeAnchor: bridge,
      neckPolygon: polygon,
      createdAt: state.context.now(),
    );
    try {
      await _repository.write(profile: profile, guitar: guitar);
    } on Object {
      state = state.copyWith(
        lastSaveOutcome: GuitarCalibrationSaveOutcome.writeFailed,
      );
      return GuitarCalibrationSaveOutcome.writeFailed;
    }
    state = state.copyWith(
      nutAnchor: nut,
      bridgeAnchor: bridge,
      neckPolygon: polygon,
      selfEvaluationReason: _selfEvaluate(
        nut,
        bridge,
        polygon,
        state.context,
        state.context.now(),
      ),
      qualityScore: computeQualityScore(
        nutAnchor: nut,
        bridgeAnchor: bridge,
        neckPolygon: polygon,
      ),
      hasPersistedRecord: true,
      clearEntryEvaluation: true,
      lastSavedProfile: profile,
      lastSavedGuitar: guitar,
      lastSaveOutcome: GuitarCalibrationSaveOutcome.saved,
    );
    return GuitarCalibrationSaveOutcome.saved;
  }

  /// Save the draft via the repository IF the self-evaluation passes (§5.1).
  /// Returns the outcome so the widget can render a snackbar without
  /// inspecting the repository.
  Future<GuitarCalibrationSaveOutcome> saveIfValid() async {
    if (state.selfEvaluationReason != null) {
      state = state.copyWith(
        lastSaveOutcome: GuitarCalibrationSaveOutcome.blocked,
      );
      return GuitarCalibrationSaveOutcome.blocked;
    }
    final now = state.context.now();
    final profile = CameraCalibrationProfile(
      camera: state.context.camera,
      orientation: state.context.orientation,
      zoom: state.context.zoom,
      setupProfile: state.context.setupProfile,
      createdAt: now,
      qualityScore: state.qualityScore,
    );
    final guitar = GuitarCalibration(
      nutAnchor: state.nutAnchor,
      bridgeAnchor: state.bridgeAnchor,
      neckPolygon: state.neckPolygon,
      createdAt: now,
    );
    try {
      await _repository.write(profile: profile, guitar: guitar);
    } on Object {
      state = state.copyWith(
        lastSaveOutcome: GuitarCalibrationSaveOutcome.writeFailed,
      );
      return GuitarCalibrationSaveOutcome.writeFailed;
    }
    state = state.copyWith(
      hasPersistedRecord: true,
      lastSavedProfile: profile,
      lastSavedGuitar: guitar,
      clearEntryEvaluation: true,
      entryEvaluationReason: CalibrationValidity.evaluate(
        profile: profile,
        guitar: guitar,
        currentCamera: state.context.camera,
        currentOrientation: state.context.orientation,
        currentZoom: state.context.zoom,
        now: now,
      ),
      lastSaveOutcome: GuitarCalibrationSaveOutcome.saved,
    );
    return GuitarCalibrationSaveOutcome.saved;
  }

  /// §0.0 R5 Save gate (self-comparison): draft vs itself. Only
  /// [CalibrationInvalidationReason.degenerateGeometry] can fire — the camera/
  /// orientation/zoom/timestamp triggers are structurally unreachable.
  static CalibrationInvalidationReason? _selfEvaluate(
    NormalizedPoint nut,
    NormalizedPoint bridge,
    List<NormalizedPoint> polygon,
    GuitarCalibrationContext context,
    DateTime now,
  ) {
    // Synthetic profile whose own fields match the live context exactly.
    final syntheticProfile = CameraCalibrationProfile(
      camera: context.camera,
      orientation: context.orientation,
      zoom: context.zoom,
      setupProfile: context.setupProfile,
      createdAt: now,
      qualityScore: 0,
    );
    final syntheticGuitar = GuitarCalibration(
      nutAnchor: nut,
      bridgeAnchor: bridge,
      neckPolygon: polygon,
      createdAt: now,
    );
    final reason = CalibrationValidity.evaluate(
      profile: syntheticProfile,
      guitar: syntheticGuitar,
      currentCamera: context.camera,
      currentOrientation: context.orientation,
      currentZoom: context.zoom,
      now: now,
    );
    // Only the geometric reason can survive a self-comparison (R5).
    if (reason == CalibrationInvalidationReason.degenerateGeometry) {
      return reason;
    }
    return null;
  }

  // -----------------------------------------------------------------
  // Pure helpers — exported for direct widget/controller testing.
  // -----------------------------------------------------------------

  /// Returns the unsigned area of a closed polygon via the shoelace
  /// formula. Zero (or near-zero, see [_polygonAreaEpsilon]) ⇒ degenerate.
  static double neckPolygonArea(List<NormalizedPoint> polygon) {
    if (polygon.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  /// True iff any consecutive three vertices along the polygon are
  /// effectively collinear (cross-product below [_collinearityEpsilon]).
  /// This catches the "three points on a line but numerical noise leaves a
  /// non-zero shoelace area" edge case that an area-only check misses.
  static bool neckPolygonIsCollinear(List<NormalizedPoint> polygon) {
    if (polygon.length < 3) return true;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final c = polygon[(i + 2) % polygon.length];
      final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
      if (cross.abs() <= _collinearityEpsilon) return true;
    }
    return false;
  }

  /// True iff the (nut, bridge) calibration cannot be trusted — short
  /// neck, collinear polygon, or near-zero polygon area.
  ///
  /// Bridges [CalibrationValidity._isDegenerate] (R10) with the two new
  /// geometric checks (R4) without touching the domain class.
  static bool isGeometryDegenerate({
    required NormalizedPoint nutAnchor,
    required NormalizedPoint bridgeAnchor,
    required List<NormalizedPoint> neckPolygon,
  }) {
    if (neckPolygon.length < minNeckPolygonVertices) {
      return true;
    }
    final dx = bridgeAnchor.x - nutAnchor.x;
    final dy = bridgeAnchor.y - nutAnchor.y;
    final sepSq = dx * dx + dy * dy;
    final minSepSq =
        CalibrationValidity.minAnchorSeparation *
        CalibrationValidity.minAnchorSeparation;
    if (sepSq < minSepSq) return true;
    if (neckPolygonIsCollinear(neckPolygon)) return true;
    if (neckPolygonArea(neckPolygon) <= _polygonAreaEpsilon) return true;
    return false;
  }

  /// Deterministic quality score in `[0, 1]`. Three components:
  ///
  /// 1. **Neck length margin** (45%): how far the nut↔bridge distance is
  ///    above [CalibrationValidity.minAnchorSeparation], up to
  ///    [_qualityNeckSaturation].
  /// 2. **Polygon coverage** (35%): signed polygon area as a fraction of
  ///    the "ideal" rectangular envelope between the two anchors, capped at
  ///    [_idealPolygonAreaFraction].
  /// 3. **Vertex spread** (20%): sum of consecutive vertex edge lengths
  ///    divided by the neck axis; prevents sparse / clustered polygons from
  ///    scoring artificially high.
  static double computeQualityScore({
    required NormalizedPoint nutAnchor,
    required NormalizedPoint bridgeAnchor,
    required List<NormalizedPoint> neckPolygon,
  }) {
    final dx = bridgeAnchor.x - nutAnchor.x;
    final dy = bridgeAnchor.y - nutAnchor.y;
    final neckLen = math.sqrt(dx * dx + dy * dy);
    final margin =
        ((neckLen - CalibrationValidity.minAnchorSeparation) /
                (_qualityNeckSaturation -
                    CalibrationValidity.minAnchorSeparation))
            .clamp(0.0, 1.0);

    final area = neckPolygonArea(neckPolygon);
    final perpendicularLen = neckLen > 0
        ? _polygonPerpendicularSpan(neckPolygon, nutAnchor, bridgeAnchor)
        : 0.0;
    final idealArea = neckLen * perpendicularLen;
    final coverage = idealArea <= 0
        ? 0.0
        : ((area / idealArea) / _idealPolygonAreaFraction).clamp(0.0, 1.0);

    final spread = neckLen <= 0
        ? 0.0
        : math.min(1.0, _polygonEdgeTotal(neckPolygon) / (neckLen * 4));

    final score = 0.45 * margin + 0.35 * coverage + 0.20 * spread;
    return score.clamp(0.0, 1.0).toDouble();
  }

  /// Perpendicular span of the polygon projected onto the unit-normal of
  /// the (nut, bridge) axis. Used as the "height" of an ideal rectangle
  /// that the polygon would cover if it exactly traced the neck outline.
  static double _polygonPerpendicularSpan(
    List<NormalizedPoint> polygon,
    NormalizedPoint nut,
    NormalizedPoint bridge,
  ) {
    final dx = bridge.x - nut.x;
    final dy = bridge.y - nut.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return 0;
    final nx = -dy / len;
    final ny = dx / len;
    var minP = double.infinity;
    var maxP = double.negativeInfinity;
    for (final p in polygon) {
      final proj = (p.x - nut.x) * nx + (p.y - nut.y) * ny;
      if (proj < minP) minP = proj;
      if (proj > maxP) maxP = proj;
    }
    return maxP - minP;
  }

  static double _polygonEdgeTotal(List<NormalizedPoint> polygon) {
    var total = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final ex = b.x - a.x;
      final ey = b.y - a.y;
      total += math.sqrt(ex * ex + ey * ey);
    }
    return total;
  }
}
