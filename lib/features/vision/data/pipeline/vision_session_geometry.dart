/// The geometry a running Vision session works in (E09-R28a).
///
/// R10/R11 persist a manual [GuitarCalibration]; until this round nothing read
/// it back at session time, so every guitar-relative capability was
/// structurally unreachable and the session reported `tracking` regardless of
/// whether a calibration existed at all. This type resolves the persisted
/// bundle once per session start and is honest when there is nothing to
/// resolve: no calibration, or a stale one, means `lost` — not a guessed
/// region of interest.
library;

import 'dart:math' as math;

import '../../../../core/camera/camera_coordinate_space.dart';
import '../../application/calibration_loss_machine.dart';
import '../../domain/calibration/calibration_validity.dart';
import '../../domain/calibration/guitar_calibration.dart';
import '../../domain/evidence/evidence_provenance.dart';
import '../../domain/vision_setup_profile.dart';
import '../persistence/vision_calibration_repository.dart';

/// Runtime facts the persisted calibration is judged against.
///
/// It mirrors the fields `CalibrationValidity.evaluate` compares, so the
/// session evaluates a bundle against exactly what the editor saved it with.
final class VisionGeometryContext {
  const VisionGeometryContext({
    required this.camera,
    required this.orientation,
    required this.zoom,
    required this.now,
  });

  final VisionCameraPreference camera;
  final CameraRotation orientation;
  final double zoom;
  final DateTime now;
}

/// The resolved manual geometry for one session.
final class VisionSessionGeometry {
  const VisionSessionGeometry._({
    required this.state,
    required this.source,
    required this.roi,
    required this.invalidationReason,
  });

  /// Nothing usable on disk: the session says so instead of guessing.
  const VisionSessionGeometry.uncalibrated()
    : state = CalibrationLossState.lost,
      source = GeometrySource.manual,
      roi = null,
      invalidationReason = null;

  /// Reads [record] and decides whether the session can work in guitar space.
  factory VisionSessionGeometry.resolve({
    required VisionCalibrationRecord? record,
    required VisionGeometryContext context,
    double dilation = defaultRoiDilation,
  }) {
    if (record == null) return const VisionSessionGeometry.uncalibrated();
    final reason = CalibrationValidity.evaluate(
      profile: record.profile,
      guitar: record.guitar,
      currentCamera: context.camera,
      currentOrientation: context.orientation,
      currentZoom: context.zoom,
      now: context.now,
    );
    if (reason != null) {
      return VisionSessionGeometry._(
        state: CalibrationLossState.lost,
        source: GeometrySource.manual,
        roi: null,
        invalidationReason: reason,
      );
    }
    return VisionSessionGeometry._(
      // ADR 0181: the manual anchors are the production geometry source, so a
      // valid bundle is `tracking` from `manual` — no tracker has run yet and
      // none may promote the source to `tracked`.
      state: CalibrationLossState.tracking,
      source: GeometrySource.manual,
      roi: _roiFor(record.guitar, dilation),
      invalidationReason: null,
    );
  }

  /// How far the neck bounding box is grown to become the region of interest.
  ///
  /// The calibration polygon hugs the neck; a fretting hand sits beside and
  /// above it, so the raw box crops the very thing the region exists to hold.
  /// 1.6 is a starting value, not a measurement — it is recorded in
  /// `docs/vision/e09-r28a-pipeline-facts.md` so a later round can retune it
  /// against real frames instead of rediscovering it.
  static const double defaultRoiDilation = 1.6;

  /// Whether guitar-relative work is possible at all this session.
  final CalibrationLossState state;

  /// Provenance recorded with every evidence window of this session.
  final GeometrySource source;

  /// The dilated neck region in non-mirrored normalized frame space, or
  /// `null` when there is no trustworthy calibration.
  final NormalizedRect? roi;

  /// Why a persisted bundle was rejected, when one was.
  final CalibrationInvalidationReason? invalidationReason;

  /// True when the session may use guitar-relative capabilities.
  bool get isCalibrated => state != CalibrationLossState.lost;

  static NormalizedRect _roiFor(GuitarCalibration guitar, double dilation) {
    var left = guitar.nutAnchor.x;
    var right = left;
    var top = guitar.nutAnchor.y;
    var bottom = top;
    for (final point in <NormalizedPoint>[
      guitar.bridgeAnchor,
      ...guitar.neckPolygon,
    ]) {
      left = math.min(left, point.x);
      right = math.max(right, point.x);
      top = math.min(top, point.y);
      bottom = math.max(bottom, point.y);
    }
    final centerX = (left + right) / 2;
    final centerY = (top + bottom) / 2;
    final halfWidth = (right - left) / 2 * dilation;
    final halfHeight = (bottom - top) / 2 * dilation;
    return NormalizedRect(
      left: _unit(centerX - halfWidth),
      top: _unit(centerY - halfHeight),
      right: _unit(centerX + halfWidth),
      bottom: _unit(centerY + halfHeight),
    );
  }

  static double _unit(double value) => value.clamp(0, 1).toDouble();
}
