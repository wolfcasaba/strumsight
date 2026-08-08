import '../metrics/metric_definition.dart';
import '../metrics/picking_metrics.dart';
import '../metrics/posture_metrics.dart';
import '../quality/vision_frame_quality.dart';
import '../vision_session_result.dart';
import '../vision_setup_profile.dart';

/// The three capability families a practice can require from Vision.
///
/// Keeping each existing Vision capability enum in its own set avoids a
/// lossy string vocabulary at the Practice boundary.
final class VisionPracticeCapabilities {
  const VisionPracticeCapabilities({
    this.fretting = const <FrettingCapability>{},
    this.picking = const <PickingCapability>{},
    this.posture = const <PostureCapability>{},
  });

  final Set<FrettingCapability> fretting;
  final Set<PickingCapability> picking;
  final Set<PostureCapability> posture;

  bool supports(VisionPracticeCapabilities required) =>
      fretting.containsAll(required.fretting) &&
      picking.containsAll(required.picking) &&
      posture.containsAll(required.posture);
}

/// The separately rendered quality of optional Vision evidence.
enum VisionPracticeQuality { unavailable, degraded, good }

/// Summary-only feedback keeps Vision from changing audio scoring.
enum VisionPracticeFeedbackMode { sessionSummary }

/// First-release policy: Vision is a separate observation dimension.
enum VisionPracticeScoringPolicy { separateDimension }

/// Narrow, implementation-free Vision metadata for one Practice pilot.
final class VisionPracticeContract {
  const VisionPracticeContract({
    required this.id,
    required this.requiredCapabilities,
    required this.setupProfile,
    required this.metricIds,
    required this.feedbackMode,
    required this.scoringPolicy,
  });

  /// Stable feature-local ID; this is not a `PracticeDefinition` ID.
  final String id;
  final VisionPracticeCapabilities requiredCapabilities;
  final VisionSetupProfile setupProfile;
  final Set<String> metricIds;
  final VisionPracticeFeedbackMode feedbackMode;
  final VisionPracticeScoringPolicy scoringPolicy;
}

/// The three E05-R25 Vision pilots, deliberately outside the builtin catalog.
abstract final class VisionPracticeContracts {
  static const VisionPracticeContract smallStrumMotion = VisionPracticeContract(
    id: 'vision.pilot.small-strum-motion',
    requiredCapabilities: VisionPracticeCapabilities(
      picking: <PickingCapability>{PickingCapability.guitarRelativeTracking},
    ),
    setupProfile: VisionSetupProfile.rightHandFocus,
    metricIds: <String>{'picking.strokeAmplitude'},
    feedbackMode: VisionPracticeFeedbackMode.sessionSummary,
    scoringPolicy: VisionPracticeScoringPolicy.separateDimension,
  );

  static const VisionPracticeContract downUpSymmetry = VisionPracticeContract(
    id: 'vision.pilot.down-up-symmetry',
    requiredCapabilities: VisionPracticeCapabilities(
      picking: <PickingCapability>{PickingCapability.guitarRelativeTracking},
    ),
    setupProfile: VisionSetupProfile.rightHandFocus,
    metricIds: <String>{'picking.downUpAsymmetry'},
    feedbackMode: VisionPracticeFeedbackMode.sessionSummary,
    scoringPolicy: VisionPracticeScoringPolicy.separateDimension,
  );

  static const VisionPracticeContract chordChangeEconomy =
      VisionPracticeContract(
        id: 'vision.pilot.chord-change-economy',
        requiredCapabilities: VisionPracticeCapabilities(
          fretting: <FrettingCapability>{
            FrettingCapability.handTracking,
            FrettingCapability.guitarRelativeTracking,
          },
        ),
        setupProfile: VisionSetupProfile.leftHandFocus,
        metricIds: <String>{'fretting.chordChangeTravel'},
        feedbackMode: VisionPracticeFeedbackMode.sessionSummary,
        scoringPolicy: VisionPracticeScoringPolicy.separateDimension,
      );

  static const List<VisionPracticeContract> pilots = <VisionPracticeContract>[
    smallStrumMotion,
    downUpSymmetry,
    chordChangeEconomy,
  ];
}

/// Maps a Vision result's measured quality to the Practice presentation state.
VisionPracticeQuality visionPracticeQualityFor(VisionSessionResult? session) {
  final overall = session?.qualitySummary.overall;
  return switch (overall) {
    VisionMetricState.good => VisionPracticeQuality.good,
    VisionMetricState.needsImprovement => VisionPracticeQuality.degraded,
    VisionMetricState.notObservable ||
    null => VisionPracticeQuality.unavailable,
  };
}
