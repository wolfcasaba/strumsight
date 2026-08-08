library;

export 'domain/vision_setup_profile.dart';
export 'domain/quality/frame_quality_assessor.dart';
export 'domain/quality/quality_thresholds.dart';
export 'domain/quality/vision_frame_quality.dart';
export 'domain/quality/vision_quality_summary.dart';
export 'domain/calibration/calibration_validity.dart';
export 'domain/calibration/camera_calibration_profile.dart';
export 'domain/calibration/guitar_calibration.dart';
export 'domain/landmarks/hand_landmarks.dart';
export 'domain/landmarks/hand_track.dart';
export 'domain/landmarks/hand_track_assigner.dart';
export 'domain/landmarks/landmark_smoothing.dart';
export 'domain/landmarks/pose_landmarks.dart';
export 'domain/landmarks/posture_baseline.dart';
export 'domain/landmarks/track_continuity.dart';
export 'domain/geometry/guitar_landmark_mapper.dart';
export 'domain/geometry/guitar_region.dart';
export 'domain/geometry/geometry_confidence.dart';
export 'domain/geometry/geometry_tracker.dart';
export 'application/calibration_loss_machine.dart';
export 'domain/metrics/fretting_metric_engine.dart';
export 'domain/metrics/fretting_metrics.dart';
export 'domain/metrics/metric_definition.dart';
export 'domain/metrics/metric_observation.dart';
export 'data/guitar/edge_geometry_tracker.dart';
export 'data/persistence/vision_calibration_codec.dart';
export 'data/persistence/vision_calibration_repository.dart';
export 'data/landmarks/hand_landmark_provider.dart';
export 'data/landmarks/native_hand_landmark_provider.dart';
export 'data/landmarks/recorded_hand_landmark_provider.dart';
export 'data/landmarks/pose_landmark_provider.dart';
export 'data/landmarks/native_pose_landmark_provider.dart';
export 'data/landmarks/recorded_pose_landmark_provider.dart';
export '../../core/camera/camera_coordinate_space.dart'
    show NormalizedPoint, NormalizedRect;
export '../../core/ml/vision_model_manifest.dart'
    show
        VisionModelStatus,
        VisionModelEntry,
        VisionModelManifestReport,
        VisionModelManifestReader,
        FileVisionModelManifestReader,
        handLandmarksOutputSchema,
        poseLandmarksOutputSchema,
        visionModelOutputSchemas;
export 'presentation/screens/vision_setup_screen.dart';
export 'presentation/screens/guitar_calibration_screen.dart';
