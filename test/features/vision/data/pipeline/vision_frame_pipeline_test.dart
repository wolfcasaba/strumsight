// E09-R28a: frames reach the pipeline.
//
// `VisionSessionController._onFrame` used to increment a counter and return,
// so the three overlay chips were permanently `notObservable` and the session
// result always carried `VisionQualitySummary.fromFrames(const [])`. These
// cells pin what the pipeline now measures. The byte-exact padded-row proof
// lives in `yuv_luminance_test.dart`; here the padded frame only has to
// measure identically to the unpadded one it encodes.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/camera/camera_format.dart';
import 'package:strumsight/core/camera/camera_frame.dart';
import 'package:strumsight/core/camera/camera_timestamp.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/data/persistence/vision_calibration_repository.dart';
import 'package:strumsight/features/vision/data/pipeline/vision_frame_pipeline.dart';
import 'package:strumsight/features/vision/data/pipeline/vision_session_geometry.dart';
import 'package:strumsight/features/vision/domain/calibration/camera_calibration_profile.dart';
import 'package:strumsight/features/vision/domain/calibration/guitar_calibration.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_evidence.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_classifier.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';
import 'package:strumsight/features/vision/domain/vision_setup_profile.dart';

const int _width = 16;
const int _height = 16;
const int _framesPerWindow = 6;
const int _frameStepUs = 100000;

final DateTime _savedAt = DateTime.utc(2026, 9, 1, 10);

DateTime _clock() => DateTime.utc(2026, 9, 2, 10);

/// A 4x4-block checkerboard, laid out with [rowStride] bytes per row.
///
/// Sampled at the assessor's downsample factor of 4 every sample lands on a
/// block centre, so mean luminance, clipping ratios and sharpness are all
/// deterministic.
Uint8List _checkerboard({
  int rowStride = _width,
  int dark = 30,
  int light = 200,
}) {
  final bytes = Uint8List(rowStride * _height);
  for (var y = 0; y < _height; y += 1) {
    for (var x = 0; x < _width; x += 1) {
      bytes[y * rowStride + x] = ((x ~/ 4) + (y ~/ 4)).isEven ? dark : light;
    }
  }
  return bytes;
}

CameraFrame _frame({
  required int frameId,
  required Uint8List bytes,
  int? rowStride,
  CameraPixelFormat format = CameraPixelFormat.yuv420,
}) => CameraFrame(
  bytes: bytes,
  frameId: frameId,
  timestamp: CameraTimestamp(frameId * _frameStepUs),
  width: _width,
  height: _height,
  format: format,
  orientation: CameraOrientation.portraitUp,
  rowStride: rowStride,
);

VisionSessionGeometry _calibratedGeometry() {
  final VisionCalibrationRecord record = (
    profile: CameraCalibrationProfile(
      camera: VisionCameraPreference.back,
      orientation: CameraRotation.degrees0,
      zoom: 0.5,
      setupProfile: VisionSetupProfile.leftHandFocus,
      createdAt: _savedAt,
      qualityScore: 0.9,
    ),
    guitar: GuitarCalibration(
      nutAnchor: const NormalizedPoint(0.2, 0.4),
      bridgeAnchor: const NormalizedPoint(0.8, 0.5),
      neckPolygon: const <NormalizedPoint>[
        NormalizedPoint(0.2, 0.35),
        NormalizedPoint(0.8, 0.45),
        NormalizedPoint(0.8, 0.55),
        NormalizedPoint(0.2, 0.45),
      ],
      createdAt: _savedAt,
    ),
  );
  return VisionSessionGeometry.resolve(
    record: record,
    context: VisionGeometryContext(
      camera: VisionCameraPreference.back,
      orientation: CameraRotation.degrees0,
      zoom: 0.5,
      now: _clock(),
    ),
  );
}

final class _Rig {
  _Rig(this.pipeline, this.updates, this.cancel);

  final FrameQualityPipeline pipeline;
  final List<VisionPipelineUpdate> updates;
  final Future<void> Function() cancel;

  Future<void> dispose() async {
    await cancel();
    await pipeline.dispose();
  }
}

_Rig _rig({VisionSessionGeometry? geometry, VisionSetupProfile? profile}) {
  final pipeline = FrameQualityPipeline(
    geometry: geometry ?? _calibratedGeometry(),
    profile: profile ?? VisionSetupProfile.leftHandFocus,
    now: _clock,
  );
  final updates = <VisionPipelineUpdate>[];
  final subscription = pipeline.updates.listen(updates.add);
  final rig = _Rig(pipeline, updates, subscription.cancel);
  addTearDown(rig.dispose);
  return rig;
}

void _feed(
  _Rig rig, {
  required int firstFrameId,
  required int count,
  Uint8List? bytes,
  int? rowStride,
  CameraPixelFormat format = CameraPixelFormat.yuv420,
}) {
  for (var index = 0; index < count; index += 1) {
    final frame = _frame(
      frameId: firstFrameId + index,
      bytes: bytes ?? _checkerboard(rowStride: rowStride ?? _width),
      rowStride: rowStride,
      format: format,
    );
    rig.pipeline.onFrame(frame);
    frame.invalidate();
  }
}

/// Feeds one publish window and lets the broadcast stream deliver.
Future<void> _feedWindow(
  _Rig rig, {
  required int firstFrameId,
  Uint8List? bytes,
  int? rowStride,
  CameraPixelFormat format = CameraPixelFormat.yuv420,
}) async {
  _feed(
    rig,
    firstFrameId: firstFrameId,
    count: _framesPerWindow,
    bytes: bytes,
    rowStride: rowStride,
    format: format,
  );
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('FrameQualityPipeline publishing', () {
    test('publishes nothing before a full window of frame time', () async {
      final rig = _rig();

      // A shorter window would be rejected for the policy's 250 ms minimum
      // duration anyway, so publishing early would emit nothing but noise.
      _feed(rig, firstFrameId: 0, count: _framesPerWindow - 1);
      await Future<void>.delayed(Duration.zero);

      expect(rig.updates, isEmpty);
    });

    test('publishes one measured summary per window', () async {
      final rig = _rig();

      await _feedWindow(rig, firstFrameId: 0);

      expect(rig.updates, hasLength(1));
      final summary = rig.updates.single.summary;
      expect(summary.frameCount, _framesPerWindow);
      expect(summary.lighting, VisionLighting.good);
      expect(summary.blur, VisionMetricState.good);
      expect(summary.framing, VisionMetricState.good);
      expect(summary.roiCoverage, VisionMetricState.good);
      // The first frame of a session has no predecessor to compare with, so
      // stability is honestly unavailable for that window.
      expect(summary.stability, VisionMetricState.notObservable);
    });

    test('the second window reports stability', () async {
      final rig = _rig();

      await _feedWindow(rig, firstFrameId: 0);
      await _feedWindow(rig, firstFrameId: _framesPerWindow);

      expect(rig.updates, hasLength(2));
      final second = rig.updates.last.summary;
      expect(second.stability, VisionMetricState.good);
      expect(second.overall, VisionMetricState.good);
      expect(second.setupCue, VisionSetupCue.none);
    });

    test('a dark window reports the lighting cue', () async {
      final rig = _rig();

      await _feedWindow(
        rig,
        firstFrameId: 0,
        bytes: _checkerboard(dark: 2, light: 10),
      );

      final summary = rig.updates.single.summary;
      expect(summary.lighting, VisionLighting.tooDark);
      expect(summary.setupCue, VisionSetupCue.improveLighting);
    });
  });

  group('FrameQualityPipeline stride handling', () {
    test('a padded frame measures the same as an unpadded one', () async {
      final unpadded = _rig();
      final padded = _rig();

      await _feedWindow(unpadded, firstFrameId: 0);
      await _feedWindow(padded, firstFrameId: 0, rowStride: _width + 5);

      final plain = unpadded.updates.single.summary;
      final strided = padded.updates.single.summary;
      expect(strided.lighting, plain.lighting);
      expect(strided.blur, plain.blur);
      expect(strided.framing, plain.framing);
      expect(strided.roiCoverage, plain.roiCoverage);
      expect(strided.overall, plain.overall);
    });

    test('a padded frame stays readable rather than degrading', () async {
      final rig = _rig();

      await _feedWindow(rig, firstFrameId: 0, rowStride: _width + 5);

      final summary = rig.updates.single.summary;
      expect(summary.lighting, VisionLighting.good);
      expect(summary.blur, VisionMetricState.good);
    });
  });

  group('FrameQualityPipeline honesty', () {
    test('hand and pose stay unobservable without a landmark model', () async {
      final rig = _rig();

      await _feedWindow(rig, firstFrameId: 0);

      expect(rig.updates.single.hand, VisionMetricState.notObservable);
      expect(rig.updates.single.pose, VisionMetricState.notObservable);
    });

    test('the only cue it emits is the setup one', () async {
      final rig = _rig();

      await _feedWindow(rig, firstFrameId: 0);
      await _feedWindow(rig, firstFrameId: _framesPerWindow);

      for (final update in rig.updates) {
        expect(update.realtimeCue, isNotNull);
        expect(update.realtimeCue!.code, InsightCode.setupNotObservable);
        expect(update.realtimeCue!.direction, InsightDirection.setup);
        // A setup cue is never a technique verdict, so it must not reach the
        // session summary the result screen renders.
        expect(update.sessionSummary, isEmpty);
      }
    });

    test('reports the resolved calibration state', () async {
      final calibrated = _rig();
      final uncalibrated = _rig(
        geometry: const VisionSessionGeometry.uncalibrated(),
      );

      await _feedWindow(calibrated, firstFrameId: 0);
      await _feedWindow(uncalibrated, firstFrameId: 0);

      expect(calibrated.updates.single.guitar, CalibrationLossState.tracking);
      expect(uncalibrated.updates.single.guitar, CalibrationLossState.lost);
    });

    test('without a calibration the framing coverage is unavailable', () async {
      final rig = _rig(geometry: const VisionSessionGeometry.uncalibrated());

      await _feedWindow(rig, firstFrameId: 0);

      final summary = rig.updates.single.summary;
      expect(summary.framing, VisionMetricState.notObservable);
      expect(summary.roiCoverage, VisionMetricState.notObservable);
      expect(summary.overall, VisionMetricState.notObservable);
    });

    test('an unsupported pixel format is unreadable, never assumed', () async {
      final rig = _rig();

      await _feedWindow(
        rig,
        firstFrameId: 0,
        format: CameraPixelFormat.bgra8888,
      );

      final summary = rig.updates.single.summary;
      expect(summary.lighting, VisionLighting.notObservable);
      expect(summary.blur, VisionMetricState.notObservable);
      expect(summary.overall, VisionMetricState.notObservable);
    });

    test('a truncated buffer is unreadable, never a black frame', () async {
      final rig = _rig();

      await _feedWindow(
        rig,
        firstFrameId: 0,
        bytes: Uint8List(_width * _height - 1),
      );

      expect(
        rig.updates.single.summary.overall,
        VisionMetricState.notObservable,
      );
    });
  });

  group('FrameQualityPipeline evidence', () {
    test('the emitted evidence is not observable and carries no value', () {
      final geometry = _calibratedGeometry();
      final classifier = _CapturingClassifier();
      final pipeline = FrameQualityPipeline(
        geometry: geometry,
        profile: VisionSetupProfile.leftHandFocus,
        now: _clock,
        classifier: classifier,
      );
      addTearDown(pipeline.dispose);

      for (var index = 0; index < _framesPerWindow; index += 1) {
        final frame = _frame(frameId: index, bytes: _checkerboard());
        pipeline.onFrame(frame);
        frame.invalidate();
      }

      final input = classifier.inputs.single;
      final evidence = input.evidence.single;
      expect(evidence.observationState, ObservationState.notObservable);
      expect(evidence.value, isNull);
      expect(evidence.provenance.geometrySource, geometry.source);
      expect(
        evidence.provenance.modelVersion,
        FrameQualityPipeline.modelVersion,
      );
      // The window must clear the policy's 250 ms minimum duration, or every
      // candidate is silently rejected and the session says nothing at all.
      expect(
        evidence.provenance.window.duration.inMilliseconds,
        greaterThanOrEqualTo(500),
      );
      expect(input.practiceId, FrameQualityPipeline.practiceId);
    });
  });

  group('FrameQualityPipeline lifecycle', () {
    test('reset drops the accumulated window', () async {
      final rig = _rig();

      _feed(rig, firstFrameId: 0, count: _framesPerWindow - 1);
      rig.pipeline.reset();
      _feed(rig, firstFrameId: _framesPerWindow - 1, count: 1);
      await Future<void>.delayed(Duration.zero);

      expect(rig.updates, isEmpty);
    });

    test('an invalidated frame is ignored rather than read', () async {
      final rig = _rig();

      final frame = _frame(frameId: 0, bytes: _checkerboard())..invalidate();
      rig.pipeline.onFrame(frame);
      await Future<void>.delayed(Duration.zero);

      expect(rig.updates, isEmpty);
    });

    test('a disposed pipeline accepts no further frames', () async {
      final pipeline = FrameQualityPipeline(
        geometry: _calibratedGeometry(),
        profile: VisionSetupProfile.leftHandFocus,
        now: _clock,
      );
      await pipeline.dispose();

      final frame = _frame(frameId: 0, bytes: _checkerboard());
      expect(() => pipeline.onFrame(frame), returnsNormally);
      frame.invalidate();
      await pipeline.dispose();
    });
  });
}

final class _CapturingClassifier implements VisionInsightClassifier {
  final List<VisionInsightInput> inputs = <VisionInsightInput>[];

  @override
  List<FeedbackCandidate> classify(VisionInsightInput input) {
    inputs.add(input);
    return const SetupOnlyInsightClassifier().classify(input);
  }
}
