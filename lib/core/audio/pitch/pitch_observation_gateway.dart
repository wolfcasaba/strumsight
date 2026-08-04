import '../../foundation/app_result.dart';
import 'pitch_observation.dart';
import 'pitch_observation_config.dart';

/// Lifecycle boundary for a source of pitch observations.
abstract interface class PitchObservationGateway {
  Stream<PitchObservation> get observations;

  Future<AppResult<void>> start(PitchObservationConfig config);

  Future<AppResult<void>> stop();
}
