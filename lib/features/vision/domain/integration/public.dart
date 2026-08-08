/// Domain-safe Vision contracts available to feature integrations.
///
/// This deliberately excludes landmark, geometry, provider and presentation
/// types. Cross-feature consumers must depend on aggregate evidence only.
library;

export 'vision_practice_contract.dart';
export 'vision_song_contract.dart';
export '../../application/vision_cadence_policy.dart';
export '../metrics/metric_definition.dart';
export '../metrics/picking_metrics.dart';
export '../metrics/posture_metrics.dart';
export '../quality/vision_frame_quality.dart';
export '../vision_session_result.dart';
export '../vision_setup_profile.dart';
