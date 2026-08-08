import 'package:strumsight/features/vision/public.dart';

/// Whether a completed Practice session used optional Vision evidence.
enum PracticeVisionMode { audioOnly, audioAndVision }

/// Practice-facing result of the optional Vision capability and quality gates.
final class PracticeVisionEvaluation {
  const PracticeVisionEvaluation({required this.quality, required this.mode});

  final VisionPracticeQuality quality;
  final PracticeVisionMode mode;

  /// Vision is optional, so every pilot can start with audio alone.
  bool get isPracticeAvailable => true;
}

/// Converts the public Vision contract into Practice's audio-safe fallback.
final class PracticeVisionAdapter {
  const PracticeVisionAdapter();

  PracticeVisionEvaluation evaluate({
    required VisionPracticeContract contract,
    required VisionPracticeCapabilities availableCapabilities,
    VisionSessionResult? session,
  }) {
    if (!availableCapabilities.supports(contract.requiredCapabilities)) {
      return const PracticeVisionEvaluation(
        quality: VisionPracticeQuality.unavailable,
        mode: PracticeVisionMode.audioOnly,
      );
    }

    final quality = visionPracticeQualityFor(session);
    return PracticeVisionEvaluation(
      quality: quality,
      mode: quality == VisionPracticeQuality.good
          ? PracticeVisionMode.audioAndVision
          : PracticeVisionMode.audioOnly,
    );
  }
}
