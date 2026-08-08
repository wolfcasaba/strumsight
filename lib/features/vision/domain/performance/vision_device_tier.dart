import 'package:strumsight/features/vision/data/landmarks/hand_landmark_provider.dart'
    show VisionDeviceTier;

/// Deterministic input to the device-tier classifier.
///
/// The input is a measured processing time, not a device make or model. This
/// keeps the classification portable and reproducible across supported devices.
final class VisionDeviceTierBenchmarkInput {
  const VisionDeviceTierBenchmarkInput(this.averageFrameProcessingTimeMs);

  final int averageFrameProcessingTimeMs;

  @override
  bool operator ==(Object other) =>
      other is VisionDeviceTierBenchmarkInput &&
      other.averageFrameProcessingTimeMs == averageFrameProcessingTimeMs;

  @override
  int get hashCode => averageFrameProcessingTimeMs.hashCode;
}

/// Result of a successful deterministic device-tier benchmark.
final class VisionDeviceTierClassification {
  const VisionDeviceTierClassification({
    required this.tier,
    required this.profile,
  });

  final VisionDeviceTier tier;
  final VisionDeviceTierProfile profile;

  @override
  bool operator ==(Object other) =>
      other is VisionDeviceTierClassification &&
      other.tier == tier &&
      other.profile == profile;

  @override
  int get hashCode => Object.hash(tier, profile);
}

/// Measured-frame-time classifier for the existing [VisionDeviceTier] enum.
///
/// At most 33 ms per processed frame is flagship, 34–66 ms is mid, and a
/// slower positive sample is basic. The inclusive boundaries intentionally
/// correspond to the documented 30 FPS and 15 FPS processing budgets.
final class VisionDeviceTierClassifier {
  const VisionDeviceTierClassifier();

  static const int flagshipMaximumFrameProcessingTimeMs = 33;
  static const int midMaximumFrameProcessingTimeMs = 66;

  VisionDeviceTierClassification classify(
    VisionDeviceTierBenchmarkInput input,
  ) {
    final processingTimeMs = input.averageFrameProcessingTimeMs;
    if (processingTimeMs <= 0) {
      throw ArgumentError.value(
        processingTimeMs,
        'averageFrameProcessingTimeMs',
        'Must be greater than zero.',
      );
    }

    final tier = switch (processingTimeMs) {
      <= flagshipMaximumFrameProcessingTimeMs => VisionDeviceTier.flagship,
      <= midMaximumFrameProcessingTimeMs => VisionDeviceTier.mid,
      _ => VisionDeviceTier.basic,
    };
    return VisionDeviceTierClassification(
      tier: tier,
      profile: VisionDeviceTierProfiles.forTier(tier),
    );
  }
}

/// The controlled inference profile for a measured device tier.
final class VisionDeviceTierProfile {
  const VisionDeviceTierProfile({
    required this.handFramesPerSecond,
    required this.poseCadenceEveryNthFrame,
    required this.inputResolutionPx,
    required this.overlayFramesPerSecond,
  });

  final int handFramesPerSecond;
  final int poseCadenceEveryNthFrame;
  final int inputResolutionPx;
  final int overlayFramesPerSecond;

  @override
  bool operator ==(Object other) =>
      other is VisionDeviceTierProfile &&
      other.handFramesPerSecond == handFramesPerSecond &&
      other.poseCadenceEveryNthFrame == poseCadenceEveryNthFrame &&
      other.inputResolutionPx == inputResolutionPx &&
      other.overlayFramesPerSecond == overlayFramesPerSecond;

  @override
  int get hashCode => Object.hash(
    handFramesPerSecond,
    poseCadenceEveryNthFrame,
    inputResolutionPx,
    overlayFramesPerSecond,
  );
}

/// Explicit tier-to-profile mapping. This round deliberately does not wire
/// profiles into landmark providers; a later wiring round owns that boundary.
final class VisionDeviceTierProfiles {
  const VisionDeviceTierProfiles._();

  static const VisionDeviceTierProfile basic = VisionDeviceTierProfile(
    handFramesPerSecond: 8,
    poseCadenceEveryNthFrame: 8,
    inputResolutionPx: 192,
    overlayFramesPerSecond: 15,
  );
  static const VisionDeviceTierProfile mid = VisionDeviceTierProfile(
    handFramesPerSecond: 12,
    poseCadenceEveryNthFrame: 6,
    inputResolutionPx: 256,
    overlayFramesPerSecond: 24,
  );
  static const VisionDeviceTierProfile flagship = VisionDeviceTierProfile(
    handFramesPerSecond: 15,
    poseCadenceEveryNthFrame: 4,
    inputResolutionPx: 320,
    overlayFramesPerSecond: 30,
  );

  static VisionDeviceTierProfile forTier(VisionDeviceTier tier) =>
      switch (tier) {
        VisionDeviceTier.basic => basic,
        VisionDeviceTier.mid => mid,
        VisionDeviceTier.flagship => flagship,
      };
}
