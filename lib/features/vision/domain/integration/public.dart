/// Domain-safe Vision contracts available to feature integrations.
///
/// This deliberately excludes landmark, geometry, provider and presentation
/// types. Cross-feature consumers must depend on aggregate evidence only.
library;

export 'vision_practice_contract.dart';
export 'vision_song_contract.dart';
export 'vision_context_snapshot.dart';
export 'vision_claim_guard.dart';
export '../vision_session.dart' show VisionSessionId;
export '../../application/vision_cadence_policy.dart';
export '../metrics/metric_definition.dart';
export '../metrics/picking_metrics.dart';
export '../metrics/posture_metrics.dart' show PostureCapability;
export '../quality/vision_frame_quality.dart';
export '../vision_session_result.dart';
export '../vision_setup_profile.dart';
