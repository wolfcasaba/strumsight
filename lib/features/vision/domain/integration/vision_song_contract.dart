import '../vision_setup_profile.dart';

/// Aggregate-only Vision contract for the Song Trainer.
///
/// Song, section and loop identifiers remain stable strings at this feature
/// boundary so Vision never needs a dependency on Song Trainer internals.
final class VisionSongContract {
  VisionSongContract({
    required this.id,
    required this.setupProfile,
    required this.minimumPostureSectionDuration,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (minimumPostureSectionDuration <= Duration.zero) {
      throw ArgumentError.value(
        minimumPostureSectionDuration,
        'minimumPostureSectionDuration',
        'Must be positive.',
      );
    }
  }

  final String id;
  final VisionSetupProfile setupProfile;

  /// Short loops do not have enough evidence for a posture-drift aggregate.
  final Duration minimumPostureSectionDuration;
}
