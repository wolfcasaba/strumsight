/// Thermal pressure injected into Vision scheduling.
///
/// The value is deliberately platform-agnostic. A future device-tier round
/// may supply it, but this policy never reads a platform API itself.
final class VisionThermalLoad {
  VisionThermalLoad(this.value) {
    if (value < minimum || value > maximum) {
      throw ArgumentError.value(
        value,
        'value',
        'Must be in the inclusive range $minimum..$maximum.',
      );
    }
  }

  factory VisionThermalLoad.normal() => VisionThermalLoad(minimum);

  static const int minimum = 0;
  static const int maximum = 100;

  final int value;

  @override
  bool operator ==(Object other) =>
      other is VisionThermalLoad && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// The amount of optional Vision work permitted alongside audio playback.
enum VisionCadence { full, reduced, audioOnly, visionDisabled }

/// A thermal decision that never represents a Song Trainer transport failure.
final class VisionCadenceDecision {
  const VisionCadenceDecision(this.cadence);

  final VisionCadence cadence;

  bool get isError => false;
  bool get requiresTransportStop => false;
  bool get isVisionEnabled =>
      cadence != VisionCadence.audioOnly &&
      cadence != VisionCadence.visionDisabled;

  @override
  bool operator ==(Object other) =>
      other is VisionCadenceDecision && other.cadence == cadence;

  @override
  int get hashCode => cadence.hashCode;
}

/// Pure Vision scheduling policy for audio-priority integrations.
///
/// `40` begins reduced cadence and `80` begins audio-only operation. The
/// boundaries are public so every caller and test uses the same contract.
final class VisionCadencePolicy {
  const VisionCadencePolicy();

  static const int reducedCadenceThermalLoad = 40;
  static const int audioOnlyThermalLoad = 80;

  VisionCadenceDecision decide({
    required VisionThermalLoad thermalLoad,
    required bool supportsVision,
  }) {
    if (!supportsVision) {
      return const VisionCadenceDecision(VisionCadence.visionDisabled);
    }
    if (thermalLoad.value >= audioOnlyThermalLoad) {
      return const VisionCadenceDecision(VisionCadence.audioOnly);
    }
    if (thermalLoad.value >= reducedCadenceThermalLoad) {
      return const VisionCadenceDecision(VisionCadence.reduced);
    }
    return const VisionCadenceDecision(VisionCadence.full);
  }
}
