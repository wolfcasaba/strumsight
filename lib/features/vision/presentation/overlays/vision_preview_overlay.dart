import 'package:flutter/material.dart';

import '../../../../core/camera/camera_coordinate_space.dart';
import '../../../../core/camera/camera_transform.dart';
import '../../../../core/camera/preview_fit.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/vision_session_state.dart';
import '../../domain/feedback/insight_code.dart';
import '../../domain/quality/vision_frame_quality.dart';
import '../../application/calibration_loss_machine.dart';

/// Privacy-preserving Vision preview overlay.
///
/// It renders only status chips and the R23-selected cue by default. Debug
/// landmarks are supplied separately from provider state, so toggling them can
/// never turn immutable session state into a frame or landmark buffer.
class VisionPreviewOverlay extends StatelessWidget {
  const VisionPreviewOverlay({
    required this.quality,
    required this.realtimeCue,
    required this.detailedOverlayEnabled,
    this.debugLandmarks = const <NormalizedPoint>[],
    this.imageSize = const UprightSize(width: 1, height: 1),
    this.fitMode = PreviewFitMode.fill,
    this.mirrorPreview = false,
    super.key,
  });

  final VisionOverlayQuality quality;
  final VisionInsight? realtimeCue;
  final bool detailedOverlayEnabled;
  final List<NormalizedPoint> debugLandmarks;
  final UprightSize imageSize;
  final PreviewFitMode fitMode;
  final bool mirrorPreview;

  /// R07's normalized-to-preview mapping; no widget-local correction is made.
  static Offset mapLandmark({
    required NormalizedPoint point,
    required PreviewFit fit,
    required bool mirrorPreview,
  }) {
    final preview = fit.toPreview(mirrorPreview: mirrorPreview).apply(point);
    final overlay = CameraTransform.previewToOverlay().apply(preview);
    return Offset(overlay.x, overlay.y);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0.0;
        final fit = PreviewFit(
          imageSize: imageSize,
          viewport: PreviewRect(left: 0, top: 0, width: width, height: height),
          mode: fitMode,
        );
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (detailedOverlayEnabled)
              CustomPaint(
                key: const Key('vision-preview-skeleton'),
                painter: _LandmarkPainter(
                  points: debugLandmarks
                      .map(
                        (point) => mapLandmark(
                          point: point,
                          fit: fit,
                          mirrorPreview: mirrorPreview,
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            Positioned(
              left: 12,
              top: 12,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _QualityChip(
                    key: const Key('vision-quality-hand'),
                    label: l10n.visionSessionHandQuality,
                    value: _metricLabel(l10n, quality.hand),
                    good: quality.hand == VisionMetricState.good,
                  ),
                  _QualityChip(
                    key: const Key('vision-quality-pose'),
                    label: l10n.visionSessionPoseQuality,
                    value: _metricLabel(l10n, quality.pose),
                    good: quality.pose == VisionMetricState.good,
                  ),
                  _QualityChip(
                    key: const Key('vision-quality-guitar'),
                    label: l10n.visionSessionGuitarQuality,
                    value: _guitarLabel(l10n, quality.guitar),
                    good: quality.guitar == CalibrationLossState.tracking,
                  ),
                ],
              ),
            ),
            if (realtimeCue != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Semantics(
                  liveRegion: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _cueText(l10n, realtimeCue!),
                        key: const Key('vision-realtime-cue'),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _metricLabel(AppLocalizations l10n, VisionMetricState value) =>
      switch (value) {
        VisionMetricState.good => l10n.visionSessionQualityGood,
        VisionMetricState.needsImprovement => l10n.visionSessionQualityAdjust,
        VisionMetricState.notObservable => l10n.visionSessionQualityUnavailable,
      };

  static String _guitarLabel(
    AppLocalizations l10n,
    CalibrationLossState value,
  ) => switch (value) {
    CalibrationLossState.tracking => l10n.visionSessionQualityGood,
    CalibrationLossState.degraded => l10n.visionSessionQualityAdjust,
    CalibrationLossState.lost => l10n.visionSessionQualityUnavailable,
  };

  static String _cueText(AppLocalizations l10n, VisionInsight insight) =>
      switch (insight.code) {
        InsightCode.setupNotObservable => l10n.visionInsightSetupNotObservable,
        InsightCode.frettingStable => l10n.visionInsightFrettingStable,
        InsightCode.frettingFocus => l10n.visionInsightFrettingFocus,
        InsightCode.frettingImproved => l10n.visionInsightFrettingImproved,
        InsightCode.pickingStable => l10n.visionInsightPickingStable,
        InsightCode.pickingFocus => l10n.visionInsightPickingFocus,
        InsightCode.pickingImproved => l10n.visionInsightPickingImproved,
        InsightCode.postureStable => l10n.visionInsightPostureStable,
        InsightCode.postureFocus => l10n.visionInsightPostureFocus,
        InsightCode.postureImproved => l10n.visionInsightPostureImproved,
        InsightCode.experimentalObservation =>
          l10n.visionInsightExperimentalObservation,
      };
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({
    required this.label,
    required this.value,
    required this.good,
    super.key,
  });

  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(good ? Icons.check_circle : Icons.info_outline, size: 18),
    label: Text('$label: $value'),
  );
}

class _LandmarkPainter extends CustomPainter {
  const _LandmarkPainter({required this.points});

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill;
    for (final point in points) {
      canvas.drawCircle(point, 4, paint);
    }
  }

  @override
  bool shouldRepaint(_LandmarkPainter oldDelegate) =>
      oldDelegate.points != points;
}
