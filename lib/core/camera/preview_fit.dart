import 'dart:math' as math;

import 'camera_coordinate_space.dart';
import 'camera_transform.dart';

enum PreviewFitMode { fit, fill }

/// Aspect-ratio layout from the non-mirrored normalized frame to a preview.
///
/// [contentRect] may extend outside [viewport] for [PreviewFitMode.fill]; the
/// corresponding [cropRect] identifies the normalized area visible there.
final class PreviewFit {
  PreviewFit({
    required this.imageSize,
    required this.viewport,
    required this.mode,
  }) : contentRect = _contentRect(imageSize, viewport, mode),
       cropRect = _cropRect(_contentRect(imageSize, viewport, mode), viewport);

  final UprightSize imageSize;
  final PreviewRect viewport;
  final PreviewFitMode mode;
  final PreviewRect contentRect;
  final NormalizedRect cropRect;

  /// The intersection of rendered content and the preview viewport.
  ///
  /// In fit mode this excludes letterbox bars; in fill mode it is the viewport.
  PreviewRect get visibleContentRect => PreviewRect(
    left: math.max(contentRect.left, viewport.left),
    top: math.max(contentRect.top, viewport.top),
    width:
        math.min(contentRect.right, viewport.right) -
        math.max(contentRect.left, viewport.left),
    height:
        math.min(contentRect.bottom, viewport.bottom) -
        math.max(contentRect.top, viewport.top),
  );

  CameraTransform<NormalizedPoint, PreviewPoint> toPreview({
    bool mirrorPreview = false,
  }) {
    final transform = CameraTransform<NormalizedPoint, PreviewPoint>.affine(
      a: contentRect.width,
      b: 0,
      c: 0,
      d: contentRect.height,
      tx: contentRect.left,
      ty: contentRect.top,
      fromPoint: NormalizedPoint.new,
      toPoint: PreviewPoint.new,
    );
    return mirrorPreview
        ? transform.compose(CameraTransform.previewMirror(viewport))
        : transform;
  }

  CameraTransform<PreviewPoint, NormalizedPoint> toNormalized({
    bool mirrorPreview = false,
  }) => toPreview(mirrorPreview: mirrorPreview).inverse();

  /// Model input is always the original, non-mirrored normalized space.
  CameraTransform<NormalizedPoint, NormalizedPoint> toModelInput() =>
      CameraTransform<NormalizedPoint, NormalizedPoint>.affine(
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        tx: 0,
        ty: 0,
        fromPoint: NormalizedPoint.new,
        toPoint: NormalizedPoint.new,
      );

  static PreviewRect _contentRect(
    UprightSize imageSize,
    PreviewRect viewport,
    PreviewFitMode mode,
  ) {
    final scale = switch (mode) {
      PreviewFitMode.fit => math.min(
        viewport.width / imageSize.width,
        viewport.height / imageSize.height,
      ),
      PreviewFitMode.fill => math.max(
        viewport.width / imageSize.width,
        viewport.height / imageSize.height,
      ),
    };
    final width = imageSize.width * scale;
    final height = imageSize.height * scale;
    return PreviewRect(
      left: viewport.left + (viewport.width - width) / 2,
      top: viewport.top + (viewport.height - height) / 2,
      width: width,
      height: height,
    );
  }

  static NormalizedRect _cropRect(
    PreviewRect contentRect,
    PreviewRect viewport,
  ) => NormalizedRect(
    left: math.max(0, (viewport.left - contentRect.left) / contentRect.width),
    top: math.max(0, (viewport.top - contentRect.top) / contentRect.height),
    right: math.min(1, (viewport.right - contentRect.left) / contentRect.width),
    bottom: math.min(
      1,
      (viewport.bottom - contentRect.top) / contentRect.height,
    ),
  );
}
