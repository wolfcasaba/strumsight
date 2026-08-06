/// The first four camera-framing profiles available to the Vision setup.
///
/// The values intentionally match the SDD's stable profile vocabulary. The
/// later Song Trainer and experimental fretboard profiles belong to their own
/// rollout rounds and must not be inferred from this initial setup flow.
enum VisionSetupProfile {
  leftHandFocus,
  rightHandFocus,
  fullUpperBody,
  practiceBalanced;

  String get storageValue => name;

  static VisionSetupProfile fromStorage(String? value) =>
      VisionSetupProfile.values.firstWhere(
        (profile) => profile.storageValue == value,
        orElse: () => VisionSetupProfile.leftHandFocus,
      );

  /// Recommends the fretting-hand framing for the player's handedness.
  ///
  /// This is a suggestion, never a constraint: the setup UI always lets a
  /// player select any profile afterwards.
  static VisionSetupProfile recommendedFor({required bool leftHanded}) =>
      leftHanded ? rightHandFocus : leftHandFocus;
}

/// A persisted camera identifier abstraction, not a request to the platform
/// adapter to select a particular physical lens.
enum VisionCameraPreference {
  back,
  front;

  String get storageValue => name;

  static VisionCameraPreference fromStorage(String? value) =>
      VisionCameraPreference.values.firstWhere(
        (camera) => camera.storageValue == value,
        orElse: () => VisionCameraPreference.back,
      );
}
