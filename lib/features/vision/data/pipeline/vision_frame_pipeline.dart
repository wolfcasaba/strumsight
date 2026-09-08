/// The frame pipeline the Vision session feeds (E09-R28a).
///
/// Until this round `VisionSessionController._onFrame` counted deliveries and
/// dropped every buffer, so the three overlay chips were permanently
/// `notObservable` and the session result carried the empty quality summary.
/// This pipeline closes that gap for everything that is measurable without a
/// model: luminance-based frame quality, the persisted manual calibration, and
/// the one honest cue those two can justify.
///
/// It lives under `data/` on purpose. `tool/check_architecture.dart` forbids
/// the raw payload types (`Uint8List`, `GrayscaleFrame`, ...) inside
/// `application/` provider state and `data/persistence/`; the pipeline touches
/// pixels, so it belongs here and hands the application layer only immutable
/// summaries.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../../../core/camera/camera_format.dart';
import '../../../../core/camera/camera_frame.dart';
import '../../application/calibration_loss_machine.dart';
import '../../application/feedback_policy_engine.dart';
import '../../domain/evidence/evidence_provenance.dart';
import '../../domain/evidence/vision_evidence.dart';
import '../../domain/evidence/vision_observation.dart';
import '../../domain/feedback/cue_budget.dart';
import '../../domain/feedback/insight_classifier.dart';
import '../../domain/feedback/insight_code.dart';
import '../../domain/metrics/metric_definition.dart';
import '../../domain/quality/frame_quality_assessor.dart';
import '../../domain/quality/vision_frame_quality.dart';
import '../../domain/quality/vision_quality_summary.dart';
import '../../domain/sync/sync_quality.dart';
import '../../domain/vision_setup_profile.dart';
import 'vision_session_geometry.dart';
import 'yuv_luminance.dart';

/// One published, summary-only pipeline result.
///
/// Every field is an aggregate or a policy-selected insight. No frame, buffer,
/// or landmark crosses this boundary, which is what lets the controller put
/// the values straight into provider state.
final class VisionPipelineUpdate {
  const VisionPipelineUpdate({
    required this.summary,
    required this.hand,
    required this.pose,
    required this.guitar,
    required this.realtimeCue,
    required this.sessionSummary,
  });

  final VisionQualitySummary summary;
  final VisionMetricState hand;
  final VisionMetricState pose;
  final CalibrationLossState guitar;
  final VisionInsight? realtimeCue;
  final List<VisionInsight> sessionSummary;
}

/// Consumes borrowed camera frames and publishes summaries.
abstract interface class VisionFrameProcessor {
  /// Summaries published on the pipeline's own cadence, not per frame.
  Stream<VisionPipelineUpdate> get updates;

  /// Called inside the capture listener while the frame is still valid.
  void onFrame(CameraFrame frame);

  /// Drops the accumulated window without ending the stream.
  void reset();

  Future<void> dispose();
}

/// The R28a processor: real frame quality, real calibration, no model.
///
/// Hand and pose stay [VisionMetricState.notObservable] because no landmark
/// model is active — that is the measured truth, not a placeholder. The one
/// cue it can justify travels through the production [FeedbackPolicyEngine]
/// and [CueBudget]; nothing here bypasses the policy gates.
final class FrameQualityPipeline implements VisionFrameProcessor {
  FrameQualityPipeline({
    required this.geometry,
    required this.profile,
    required DateTime Function() now,
    FrameQualityAssessor? assessor,
    VisionInsightClassifier classifier = const SetupOnlyInsightClassifier(),
    this.publishInterval = defaultPublishInterval,
    this.windowFrameLimit = defaultWindowFrameLimit,
  }) : assert(windowFrameLimit > 0, 'The window must hold at least one frame'),
       assert(publishInterval > Duration.zero, 'Publishing needs a cadence'),
       _assessor = assessor ?? FrameQualityAssessor(),
       _classifier = classifier,
       _engine = FeedbackPolicyEngine(cueBudget: CueBudget(now: now)),
       _updates = StreamController<VisionPipelineUpdate>.broadcast();

  /// How much frame time one published window covers.
  ///
  /// It must stay above the policy's 250 ms `minimumDuration`, otherwise every
  /// candidate is rejected for a too-short evidence window and the session
  /// silently emits nothing.
  static const Duration defaultPublishInterval = Duration(milliseconds: 500);

  /// Upper bound on retained per-frame quality records.
  ///
  /// A window normally clears on publish; this only bounds the pathological
  /// case of a capture whose timestamps stop advancing.
  static const int defaultWindowFrameLimit = 90;

  /// Comparison key for the candidates this pipeline proposes. A standalone
  /// Vision session is not bound to a practice item, so it uses a stable id
  /// of its own rather than borrowing an unrelated one.
  static const String practiceId = 'vision-session';

  /// Model provenance recorded while every vision model stays `deferred`.
  static const String modelVersion = 'deferred';

  /// Version of the classification rules behind the emitted evidence.
  static const String classifierVersion = 'vision-insight-classifier-r28a-v1';

  /// Confidence attached to the "no technique metric is observable" claim.
  ///
  /// It is deliberately 1.0 and is NOT a judgement about the player: with no
  /// landmark model active the fretting, picking and posture metrics are
  /// structurally unreachable, so the claim about observability is certain.
  /// The policy engine still applies its own threshold to it.
  static const double notObservableConfidence = 1.0;

  final VisionSessionGeometry geometry;
  final VisionSetupProfile profile;
  final Duration publishInterval;
  final int windowFrameLimit;

  final FrameQualityAssessor _assessor;
  final VisionInsightClassifier _classifier;
  final FeedbackPolicyEngine _engine;
  final StreamController<VisionPipelineUpdate> _updates;
  final List<VisionFrameQuality> _window = <VisionFrameQuality>[];

  int? _windowStartUs;
  bool _closed = false;

  @override
  Stream<VisionPipelineUpdate> get updates => _updates.stream;

  @override
  void onFrame(CameraFrame frame) {
    if (_closed || !frame.isValid) return;
    // The buffer is borrowed and invalidated the moment this callback
    // returns, so the copy has to happen here, synchronously.
    final luminance = _luminanceOf(frame);
    final quality = _assessor.assess(
      GrayscaleFrame(
        width: frame.width,
        height: frame.height,
        // An unreadable buffer stays unreadable: an empty plane makes the
        // assessor report `notObservable` instead of inventing a black frame.
        luminance: luminance ?? Uint8List(0),
      ),
      profile: profile,
      roi: geometry.roi,
    );
    _record(frame.timestamp.microsecondsSinceSessionStart, quality);
  }

  @override
  void reset() {
    _window.clear();
    _windowStartUs = null;
    _assessor.reset();
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _window.clear();
    _windowStartUs = null;
    await _updates.close();
  }

  Uint8List? _luminanceOf(CameraFrame frame) {
    // Only the YUV layouts begin with a plain luminance plane. Anything else
    // would need a real colour conversion, so it is reported as unreadable
    // rather than misread as grayscale.
    if (frame.format != CameraPixelFormat.yuv420 &&
        frame.format != CameraPixelFormat.nv21) {
      return null;
    }
    return packLuminancePlane(
      bytes: frame.copyBytes(),
      width: frame.width,
      height: frame.height,
      rowStride: frame.luminanceRowStride,
    );
  }

  void _record(int timestampUs, VisionFrameQuality quality) {
    final startUs = _windowStartUs ??= timestampUs;
    _window.add(quality);
    if (_window.length > windowFrameLimit) {
      _window.removeAt(0);
    }
    if (timestampUs - startUs < publishInterval.inMicroseconds) return;
    _publish(startUs: startUs, endUs: timestampUs);
    _window.clear();
    _windowStartUs = null;
  }

  void _publish({required int startUs, required int endUs}) {
    final summary = VisionQualitySummary.fromFrames(_window);
    final decision = _engine.evaluate(
      _classifier.classify(
        VisionInsightInput(
          evidence: <VisionEvidence>[
            _notObservableEvidence(startUs: startUs, endUs: endUs),
          ],
          practiceId: practiceId,
          capabilityLevel: profile.name,
        ),
      ),
    );
    _updates.add(
      VisionPipelineUpdate(
        summary: summary,
        // No landmark model runs in this round, so neither hand nor pose is
        // observable. Reporting anything else would be a fabricated claim.
        hand: VisionMetricState.notObservable,
        pose: VisionMetricState.notObservable,
        guitar: geometry.state,
        realtimeCue: decision.realtimeCue,
        sessionSummary: decision.sessionSummary,
      ),
    );
  }

  VisionEvidence _notObservableEvidence({
    required int startUs,
    required int endUs,
  }) {
    final metric = EvidenceMetric.fretting(FrettingMetricId.handToNeckDistance);
    final window = EvidenceWindow(startUs: startUs, endUs: endUs);
    return VisionEvidence(
      id: VisionEvidence.deterministicId(metric: metric, window: window),
      metric: metric,
      value: null,
      confidence: notObservableConfidence,
      observationState: ObservationState.notObservable,
      provenance: EvidenceProvenance(
        metricId: metric.id,
        window: window,
        modelVersion: modelVersion,
        geometrySource: geometry.source,
        // No audio stream is aligned with this session, so the alignment is
        // recorded as unusable rather than optimistically assumed.
        syncQuality: SyncQuality.poor,
        thresholdsVersion: classifierVersion,
        qualityThresholdsVersion: _assessor.thresholds.thresholdsVersion,
      ),
    );
  }
}
